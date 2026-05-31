from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.main import app
from app.settings import repository

client = TestClient(app)


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "select", "eq", "limit", "upsert", "order"):
        getattr(m, method).return_value = m
    return m


# ── repository.get_settings ────────────────────────────────────────────────────

@patch("app.settings.repository.get_supabase")
def test_get_settings_defaults_when_empty(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    assert repository.get_settings("u1") == {"diet": "all", "custom_markers": []}


@patch("app.settings.repository.get_supabase")
def test_get_settings_returns_existing_row(mock_db):
    db = _fluent(
        execute_data=[{"diet": "carnivore", "custom_markers": ["P-Ferritin"]}]
    )
    mock_db.return_value = db
    out = repository.get_settings("u1")
    assert out["diet"] == "carnivore"
    assert out["custom_markers"] == ["P-Ferritin"]


@patch("app.settings.repository.get_supabase")
def test_get_settings_filters_by_user(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    repository.get_settings("u-42")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-42") in eq_calls


@patch("app.settings.repository.get_supabase")
def test_get_settings_coerces_null_custom_markers(mock_db):
    db = _fluent(execute_data=[{"diet": "fasting", "custom_markers": None}])
    mock_db.return_value = db
    assert repository.get_settings("u1")["custom_markers"] == []


# ── repository.upsert_settings ─────────────────────────────────────────────────

@patch("app.settings.repository.get_supabase")
def test_upsert_settings_persists_and_returns(mock_db):
    db = _fluent(execute_data=[{"diet": "custom", "custom_markers": ["P-Jern"]}])
    mock_db.return_value = db
    out = repository.upsert_settings("u1", "custom", ["P-Jern"])
    db.table.assert_called_with("user_settings")
    db.upsert.assert_called_once()
    assert out == {"diet": "custom", "custom_markers": ["P-Jern"]}


# ── HTTP endpoints ─────────────────────────────────────────────────────────────

@patch("app.settings.router.repository.get_settings")
def test_get_settings_endpoint(mock_get):
    mock_get.return_value = {"diet": "low_carb", "custom_markers": []}
    app.dependency_overrides[current_user_id] = lambda: "user-1"
    try:
        res = client.get("/settings")
        assert res.status_code == 200
        assert res.json()["diet"] == "low_carb"
    finally:
        app.dependency_overrides.clear()


@patch("app.settings.router.repository.upsert_settings")
def test_put_settings_endpoint_ok(mock_up):
    mock_up.return_value = {"diet": "fasting", "custom_markers": []}
    app.dependency_overrides[current_user_id] = lambda: "user-1"
    try:
        res = client.put("/settings", json={"diet": "fasting", "custom_markers": []})
        assert res.status_code == 200
        assert res.json()["diet"] == "fasting"
        mock_up.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_put_settings_rejects_invalid_diet():
    app.dependency_overrides[current_user_id] = lambda: "user-1"
    try:
        res = client.put("/settings", json={"diet": "banana", "custom_markers": []})
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()
