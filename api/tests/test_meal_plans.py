from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.main import app
from app.meal_plans import repository

client = TestClient(app)


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "select", "eq", "gte", "lte", "order", "insert", "update", "delete"):
        getattr(m, method).return_value = m
    return m


# ── repository: plans ─────────────────────────────────────────────────────────────


@patch("app.meal_plans.repository.get_supabase")
def test_list_plans_filters_by_user_newest_first(mock_db):
    db = _fluent(execute_data=[{"id": "p1", "name": "Carnivore week"}])
    mock_db.return_value = db
    out = repository.list_plans("u-9")
    assert out[0]["name"] == "Carnivore week"
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-9") in eq_calls
    db.order.assert_called_with("created_at", desc=True)


@patch("app.meal_plans.repository.get_supabase")
def test_create_plan_inserts_user_scoped_row(mock_db):
    db = _fluent(execute_data=[{"id": "p1"}])
    mock_db.return_value = db
    out = repository.create_plan("u1", "Low-carb reset", "Two weeks")
    db.table.assert_called_with("meal_plans")
    inserted = db.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["name"] == "Low-carb reset"
    assert inserted["description"] == "Two weeks"
    assert out["id"] == "p1"


@patch("app.meal_plans.repository.get_supabase")
def test_delete_plan_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_plan("u1", "p1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "p1") in eq_calls


# ── repository: planned meals ─────────────────────────────────────────────────────


@patch("app.meal_plans.repository.get_supabase")
def test_list_planned_meals_filters_by_user(mock_db):
    db = _fluent(execute_data=[{"id": "m1", "food_name": "Ribeye"}])
    mock_db.return_value = db
    out = repository.list_planned_meals("u-3")
    assert out[0]["food_name"] == "Ribeye"
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-3") in eq_calls


@patch("app.meal_plans.repository.get_supabase")
def test_list_planned_meals_applies_date_window(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    repository.list_planned_meals("u1", "2026-06-01", "2026-06-07")
    db.gte.assert_called_with("scheduled_on", "2026-06-01")
    db.lte.assert_called_with("scheduled_on", "2026-06-07")


@patch("app.meal_plans.repository.get_supabase")
def test_create_planned_meal_inserts_user_scoped_row(mock_db):
    db = _fluent(execute_data=[{"id": "m1"}])
    mock_db.return_value = db
    out = repository.create_planned_meal(
        "u1",
        {
            "scheduled_on": "2026-06-02",
            "meal": "dinner",
            "food_name": "Ribeye steak",
            "quantity_g": 250,
            "energy_kcal": 728,
        },
    )
    db.table.assert_called_with("planned_meals")
    inserted = db.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["food_name"] == "Ribeye steak"
    assert inserted["done"] is False  # defaults when omitted
    assert out["id"] == "m1"


@patch("app.meal_plans.repository.get_supabase")
def test_set_planned_meal_done_updates_flag(mock_db):
    db = _fluent(execute_data=[{"id": "m1", "done": True}])
    mock_db.return_value = db
    out = repository.set_planned_meal_done("u1", "m1", True)
    db.update.assert_called_with({"done": True})
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "m1") in eq_calls
    assert out["done"] is True


@patch("app.meal_plans.repository.get_supabase")
def test_delete_planned_meal_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_planned_meal("u1", "m1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "m1") in eq_calls


# ── HTTP endpoints ───────────────────────────────────────────────────────────────


@patch("app.meal_plans.router.repository.list_plans")
def test_list_plans_endpoint(mock_list):
    mock_list.return_value = [{"id": "p1", "name": "Carnivore week"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/meal-plans")
        assert res.status_code == 200
        assert res.json()[0]["name"] == "Carnivore week"
    finally:
        app.dependency_overrides.clear()


@patch("app.meal_plans.router.repository.create_plan")
def test_create_plan_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "p1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post("/meal-plans", json={"name": "Carnivore week"})
        assert res.status_code == 201
        mock_create.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_create_plan_endpoint_rejects_empty_name():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post("/meal-plans", json={"name": "   "})
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.meal_plans.router.repository.list_planned_meals")
def test_calendar_endpoint_passes_window(mock_list):
    mock_list.return_value = [{"id": "m1", "food_name": "Eggs"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/meal-plans/calendar?start=2026-06-01&end=2026-06-07")
        assert res.status_code == 200
        assert res.json()[0]["food_name"] == "Eggs"
        mock_list.assert_called_once_with("u1", "2026-06-01", "2026-06-07")
    finally:
        app.dependency_overrides.clear()


@patch("app.meal_plans.router.repository.create_planned_meal")
def test_create_planned_meal_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "m1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/meal-plans/calendar",
            json={"scheduled_on": "2026-06-02", "meal": "dinner", "food_name": "Ribeye"},
        )
        assert res.status_code == 201
        mock_create.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_create_planned_meal_endpoint_rejects_invalid_meal():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/meal-plans/calendar",
            json={"scheduled_on": "2026-06-02", "meal": "brunch", "food_name": "Ribeye"},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.meal_plans.router.repository.set_planned_meal_done")
def test_patch_planned_meal_endpoint(mock_set):
    mock_set.return_value = {"id": "m1", "done": True}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.patch("/meal-plans/calendar/m1", json={"done": True})
        assert res.status_code == 200
        mock_set.assert_called_once_with("u1", "m1", True)
    finally:
        app.dependency_overrides.clear()


@patch("app.meal_plans.router.repository.delete_planned_meal")
def test_delete_planned_meal_endpoint(mock_del):
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.delete("/meal-plans/calendar/m1")
        assert res.status_code == 200
        mock_del.assert_called_once_with("u1", "m1")
    finally:
        app.dependency_overrides.clear()
