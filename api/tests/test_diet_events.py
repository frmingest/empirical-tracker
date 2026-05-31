from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.diet_events import repository
from app.main import app

client = TestClient(app)


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "select", "eq", "order", "insert", "delete"):
        getattr(m, method).return_value = m
    return m


# ── repository ──────────────────────────────────────────────────────────────────

@patch("app.diet_events.repository.get_supabase")
def test_list_events_filters_by_user_and_orders(mock_db):
    db = _fluent(execute_data=[{"id": "e1", "label": "Started carnivore"}])
    mock_db.return_value = db
    out = repository.list_events("u-7")
    assert out == [{"id": "e1", "label": "Started carnivore"}]
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-7") in eq_calls
    db.order.assert_called_with("started_on")


@patch("app.diet_events.repository.get_supabase")
def test_list_events_coerces_none_to_empty(mock_db):
    db = _fluent(execute_data=None)
    mock_db.return_value = db
    assert repository.list_events("u1") == []


@patch("app.diet_events.repository.get_supabase")
def test_create_event_inserts_user_scoped_row(mock_db):
    db = _fluent(execute_data=[{"id": "e1", "label": "Started carnivore"}])
    mock_db.return_value = db
    out = repository.create_event("u1", "Started carnivore", "diet", "2026-01-01", None, None)
    db.table.assert_called_with("diet_events")
    inserted = db.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["label"] == "Started carnivore"
    assert inserted["ended_on"] is None
    assert out["id"] == "e1"


@patch("app.diet_events.repository.get_supabase")
def test_delete_event_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_event("u1", "e1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "e1") in eq_calls


# ── HTTP endpoints ───────────────────────────────────────────────────────────────

@patch("app.diet_events.router.repository.list_events")
def test_list_endpoint(mock_list):
    mock_list.return_value = [{"id": "e1", "label": "Fast", "kind": "fast"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/diet-events")
        assert res.status_code == 200
        assert res.json()[0]["kind"] == "fast"
    finally:
        app.dependency_overrides.clear()


@patch("app.diet_events.router.repository.create_event")
def test_create_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "e1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/diet-events",
            json={"label": "Started carnivore", "kind": "diet", "started_on": "2026-01-01"},
        )
        assert res.status_code == 201
        mock_create.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_invalid_kind():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/diet-events",
            json={"label": "x", "kind": "banana", "started_on": "2026-01-01"},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_empty_label():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/diet-events",
            json={"label": "   ", "kind": "diet", "started_on": "2026-01-01"},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.diet_events.router.repository.delete_event")
def test_delete_endpoint(mock_del):
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.delete("/diet-events/e1")
        assert res.status_code == 200
        mock_del.assert_called_once_with("u1", "e1")
    finally:
        app.dependency_overrides.clear()
