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
    for method in ("table", "select", "eq", "delete"):
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
    # Donation queries custom_foods first (ADR-027), then every table is erased.
    assert tables == ["custom_foods", *repository.DELETE_ORDER]
    # custom_foods now joins the explicit erase path (closes the ADR-013 gap).
    assert "custom_foods" in repository.DELETE_ORDER
    deleted = tables[1:]
    # results (a child of panels) is erased before its parents.
    assert deleted.index("results") < deleted.index("panels")
    assert deleted.index("results") < deleted.index("biomarkers")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    db.auth.admin.delete_user.assert_called_once_with("u1")
    assert out == {"data_deleted": True, "account_deleted": True}


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
