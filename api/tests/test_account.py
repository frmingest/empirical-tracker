import io
import json
import re
import zipfile
from pathlib import Path
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.account import repository
from app.auth import current_user_id
from app.main import app

client = TestClient(app)

MIGRATIONS_DIR = Path(__file__).resolve().parents[1] / "supabase" / "migrations"


def _user_owned_tables_from_migrations() -> set[str]:
    """Every table whose CREATE TABLE declares a column referencing ``auth.users``.

    Such tables hold user-owned, RLS-scoped rows, so each one MUST appear in both
    ``USER_TABLES`` (Art. 20 export) and ``DELETE_ORDER`` (Art. 17 erasure). The
    anonymous catalogues (``food_catalogue`` / ``recipe_catalogue``) carry no
    ``auth.users`` reference, so they are correctly ignored here.

    Parsing the migrations rather than hand-listing the tables is the whole point:
    when a future feature adds a user-owned table (as ADR-033's ``activity_metrics``
    did) this guard fails until the table is registered — it can't be forgotten.
    """
    create_re = re.compile(r"create\s+table\s+(?:public\.)?(\w+)", re.IGNORECASE)
    owned: set[str] = set()
    for sql_path in MIGRATIONS_DIR.glob("*.sql"):
        lines = sql_path.read_text().splitlines()
        i = 0
        while i < len(lines):
            match = create_re.search(lines[i])
            if not match:
                i += 1
                continue
            table = match.group(1)
            # Collect the CREATE TABLE body up to its terminating ");" line.
            body: list[str] = []
            i += 1
            while i < len(lines) and lines[i].strip() not in (");", ")"):
                body.append(lines[i])
                i += 1
            if "references auth.users" in "\n".join(body).lower():
                owned.add(table)
    return owned


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "select", "eq", "delete", "insert", "order"):
        getattr(m, method).return_value = m
    return m


# ── repository: export ────────────────────────────────────────────────────────

@patch("app.account.repository.get_supabase")
def test_collect_user_data_queries_every_table_scoped_to_user(mock_db):
    db = _fluent(execute_data=[{"id": "x", "user_id": "u1"}])
    mock_db.return_value = db
    out = repository.collect_user_data("u1")
    # One key per user-owned table, all returned.
    assert set(out.keys()) == set(repository.USER_TABLES)
    queried = [call.args[0] for call in db.table.call_args_list]
    assert queried == list(repository.USER_TABLES)
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert all(("user_id", "u1") in eq_calls for _ in repository.USER_TABLES)


@patch("app.account.repository.get_supabase")
def test_collect_user_data_coerces_none_to_empty(mock_db):
    db = _fluent(execute_data=None)
    mock_db.return_value = db
    out = repository.collect_user_data("u1")
    assert out["biomarkers"] == []


@patch("app.account.repository.get_supabase")
def test_build_export_wraps_data_with_metadata(mock_db):
    db = _fluent(execute_data=[{"id": "x", "user_id": "u1"}])
    mock_db.return_value = db
    export = repository.build_export("u1")
    assert export["export_meta"]["user_id"] == "u1"
    assert export["export_meta"]["app"] == "Empirical Tracker"
    assert export["export_meta"]["row_counts"]["results"] == 1
    assert "exported_at" in export["export_meta"]
    assert export["data"]["results"][0]["id"] == "x"


# ── repository: deletion ──────────────────────────────────────────────────────

@patch("app.account.repository.get_service_supabase")
def test_delete_user_data_erases_every_table_child_first(mock_db):
    # Erasure is the one sanctioned service-role data path (ADR-026): it removes
    # the auth user via the admin API and must complete regardless of RLS.
    db = _fluent()
    mock_db.return_value = db
    out = repository.delete_user_data("u1")
    tables = [call.args[0] for call in db.table.call_args_list]
    # The donation reads come first — custom_foods (ADR-027) then recipes
    # (ADR-028) — followed by the explicit child-first erase loop.
    assert tables == ["custom_foods", "recipes", *repository.DELETE_ORDER]
    # Both catalogues' source tables join the explicit erase path (ADR-013 gap).
    assert "custom_foods" in repository.DELETE_ORDER
    assert "recipes" in repository.DELETE_ORDER
    deleted = tables[2:]
    # recipe_favorites (a child of recipes) is erased before recipes.
    assert deleted.index("recipe_favorites") < deleted.index("recipes")
    # results (a child of panels) is erased before its parents.
    assert deleted.index("results") < deleted.index("panels")
    assert deleted.index("results") < deleted.index("biomarkers")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    db.auth.admin.delete_user.assert_called_once_with("u1")
    assert out == {"data_deleted": True, "account_deleted": True}


@patch("app.account.repository.get_service_supabase")
def test_delete_user_data_donates_public_recipes_before_erasing(mock_db):
    # The user's public recipes are anonymised into recipe_catalogue (factual
    # fields only) before the rows themselves are hard-deleted (ADR-028).
    db = _fluent(
        execute_data=[
            {
                "id": "r1",
                "user_id": "u1",
                "title": "Ribeye",
                "category": "Beef",
                "image_url": "https://cdn/u1/ribeye.jpg",
                "is_public": True,
                "created_at": "2026-01-01T00:00:00+00:00",
            }
        ]
    )
    mock_db.return_value = db
    repository.delete_user_data("u1")
    # donate_public_recipes runs last, so the final insert is the recipe donation:
    # a single de-identified facts dict (factual fields + coarse donated_at).
    donated = db.insert.call_args.args[0]
    assert donated["title"] == "Ribeye"
    assert "donated_at" in donated
    assert "user_id" not in donated
    assert "image_url" not in donated
    assert "created_at" not in donated


@patch("app.account.repository.get_service_supabase")
def test_delete_user_data_survives_admin_failure(mock_db):
    db = _fluent()
    db.auth.admin.delete_user.side_effect = RuntimeError("admin api unavailable")
    mock_db.return_value = db
    out = repository.delete_user_data("u1")
    # Data still erased even though the auth record could not be removed.
    assert out == {"data_deleted": True, "account_deleted": False}


# ── schema-drift guard: every user-owned table is registered ──────────────────
# These are the "never let it happen again" checks. The mock-based tests above
# pass even when a real user-owned table is missing from the lists (the mock
# answers for any table name), so they cannot catch a forgotten registration.
# These guards read the actual schema and fail the build until a new table is
# wired into BOTH the export and the erasure path.


def test_every_user_owned_table_is_exported_and_erased():
    owned = _user_owned_tables_from_migrations()
    # Sanity: the parser actually found the schema (guards against a silent
    # empty-set pass if the migrations move or the parser breaks).
    assert "biomarkers" in owned and "activity_metrics" in owned
    missing_from_export = owned - set(repository.USER_TABLES)
    missing_from_erase = owned - set(repository.DELETE_ORDER)
    assert not missing_from_export, (
        "User-owned tables missing from USER_TABLES (GDPR Art. 20 export): "
        f"{sorted(missing_from_export)}. Register them in app/account/repository.py."
    )
    assert not missing_from_erase, (
        "User-owned tables missing from DELETE_ORDER (GDPR Art. 17 erasure): "
        f"{sorted(missing_from_erase)}. Register them in app/account/repository.py."
    )


def test_export_and_erasure_cover_the_same_tables():
    # Export and erasure must describe the same footprint: a table we hand back in
    # an Art. 20 export but never erase (or vice versa) is a compliance bug.
    assert set(repository.USER_TABLES) == set(repository.DELETE_ORDER)


# ── HTTP endpoints ────────────────────────────────────────────────────────────

@patch("app.account.router.repository.build_export")
def test_export_json_is_downloadable(mock_build):
    mock_build.return_value = {
        "export_meta": {"app": "Empirical Tracker", "user_id": "u1", "row_counts": {}},
        "data": {"results": [{"id": "x"}]},
    }
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/account/export")
        assert res.status_code == 200
        assert res.headers["content-type"].startswith("application/json")
        assert "attachment" in res.headers["content-disposition"]
        assert ".json" in res.headers["content-disposition"]
        body = json.loads(res.content)
        assert body["data"]["results"][0]["id"] == "x"
    finally:
        app.dependency_overrides.clear()


@patch("app.account.router.repository.build_export")
def test_export_csv_returns_zip_with_one_file_per_nonempty_table(mock_build):
    mock_build.return_value = {
        "export_meta": {"app": "Empirical Tracker", "user_id": "u1", "row_counts": {}},
        "data": {
            "results": [{"id": "x", "value": 1.2}],
            "panels": [],
        },
    }
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/account/export?format=csv")
        assert res.status_code == 200
        assert res.headers["content-type"] == "application/zip"
        zf = zipfile.ZipFile(io.BytesIO(res.content))
        names = set(zf.namelist())
        assert "results.csv" in names
        assert "export_meta.json" in names
        assert "panels.csv" not in names  # empty table omitted
        assert "id,value" in zf.read("results.csv").decode()
    finally:
        app.dependency_overrides.clear()


def test_export_rejects_unknown_format():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/account/export?format=pdf")
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.account.router.repository.delete_user_data")
def test_delete_account_endpoint(mock_delete):
    mock_delete.return_value = {"data_deleted": True, "account_deleted": True}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.delete("/account")
        assert res.status_code == 200
        assert res.json()["data_deleted"] is True
        mock_delete.assert_called_once_with("u1")
    finally:
        app.dependency_overrides.clear()


def test_export_requires_auth():
    res = client.get("/account/export")
    assert res.status_code == 403  # no bearer token


# ── security headers middleware ───────────────────────────────────────────────

def test_security_headers_present_on_responses():
    res = client.get("/health")
    assert res.headers["X-Content-Type-Options"] == "nosniff"
    assert res.headers["X-Frame-Options"] == "DENY"
    assert res.headers["Referrer-Policy"] == "no-referrer"
    assert "max-age" in res.headers["Strict-Transport-Security"]
    assert "default-src 'none'" in res.headers["Content-Security-Policy"]
