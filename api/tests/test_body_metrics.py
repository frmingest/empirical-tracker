from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.body_metrics import repository
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

@patch("app.body_metrics.repository.get_supabase")
def test_list_metrics_filters_by_user_and_orders(mock_db):
    db = _fluent(execute_data=[{"id": "m1", "weight_kg": 82.0}])
    mock_db.return_value = db
    out = repository.list_metrics("u-7")
    assert out == [{"id": "m1", "weight_kg": 82.0}]
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-7") in eq_calls
    db.order.assert_called_with("measured_on")


@patch("app.body_metrics.repository.get_supabase")
def test_list_metrics_coerces_none_to_empty(mock_db):
    db = _fluent(execute_data=None)
    mock_db.return_value = db
    assert repository.list_metrics("u1") == []


@patch("app.body_metrics.repository.get_supabase")
def test_create_metric_inserts_user_scoped_row(mock_db):
    db = _fluent(execute_data=[{"id": "m1"}])
    mock_db.return_value = db
    out = repository.create_metric(
        "u1",
        {
            "measured_on": "2026-06-01",
            "weight_kg": 82.5,
            "waist_cm": None,
            "systolic": 124,
            "diastolic": 80,
            "note": None,
        },
    )
    db.table.assert_called_with("body_metrics")
    inserted = db.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["weight_kg"] == 82.5
    assert inserted["systolic"] == 124
    assert inserted["waist_cm"] is None
    assert out["id"] == "m1"


@patch("app.body_metrics.repository.get_supabase")
def test_delete_metric_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_metric("u1", "m1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "m1") in eq_calls


# ── HTTP endpoints ───────────────────────────────────────────────────────────────

@patch("app.body_metrics.router.repository.list_metrics")
def test_list_endpoint(mock_list):
    mock_list.return_value = [{"id": "m1", "weight_kg": 82.0}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/body-metrics")
        assert res.status_code == 200
        assert res.json()[0]["weight_kg"] == 82.0
    finally:
        app.dependency_overrides.clear()


@patch("app.body_metrics.router.repository.create_metric")
def test_create_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "m1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/body-metrics",
            json={"measured_on": "2026-06-01", "weight_kg": 82.5},
        )
        assert res.status_code == 201
        mock_create.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_empty_measurement():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post("/body-metrics", json={"measured_on": "2026-06-01"})
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_half_blood_pressure():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/body-metrics",
            json={"measured_on": "2026-06-01", "systolic": 124},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_non_positive_weight():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/body-metrics",
            json={"measured_on": "2026-06-01", "weight_kg": 0},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.body_metrics.router.repository.delete_metric")
def test_delete_endpoint(mock_del):
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.delete("/body-metrics/m1")
        assert res.status_code == 200
        mock_del.assert_called_once_with("u1", "m1")
    finally:
        app.dependency_overrides.clear()
