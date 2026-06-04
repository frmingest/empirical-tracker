import io
import json
import zipfile
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.account import repository
from app.auth import current_user_id
from app.main import app

client = TestClient(app)


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
    tabled = [call.args[0] for call in db.table.call_args_list]
    # The first touch is the public-recipe donation read (ADR-028); the rest is
    # the explicit child-first erase loop.
    assert tabled[0] == "recipes"
    assert tabled[1:] == list(repository.DELETE_ORDER)
    # recipe_favorites (a child of recipes) is erased before recipes.
    assert tabled[1:].index("recipe_favorites") < tabled[1:].index("recipes")
    # results (a child of panels) is erased before its parents.
    deleted = tabled[1:]
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
    donated = db.insert.call_args.args[0]
    assert donated[0]["title"] == "Ribeye"
    assert "user_id" not in donated[0]
    assert "image_url" not in donated[0]
    assert "created_at" not in donated[0]


@patch("app.account.repository.get_service_supabase")
def test_delete_user_data_survives_admin_failure(mock_db):
    db = _fluent()
    db.auth.admin.delete_user.side_effect = RuntimeError("admin api unavailable")
    mock_db.return_value = db
    out = repository.delete_user_data("u1")
    # Data still erased even though the auth record could not be removed.
    assert out == {"data_deleted": True, "account_deleted": False}


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
