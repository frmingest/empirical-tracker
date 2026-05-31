from unittest.mock import MagicMock, patch

import httpx
from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.food_diary import openfoodfacts, repository
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

@patch("app.food_diary.repository.get_supabase")
def test_list_entries_filters_by_user(mock_db):
    db = _fluent(execute_data=[{"id": "f1", "food_name": "Ribeye"}])
    mock_db.return_value = db
    out = repository.list_entries("u-3")
    assert out[0]["food_name"] == "Ribeye"
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u-3") in eq_calls


@patch("app.food_diary.repository.get_supabase")
def test_list_entries_filters_by_day_when_given(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    repository.list_entries("u1", "2026-05-31")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("logged_on", "2026-05-31") in eq_calls


@patch("app.food_diary.repository.get_supabase")
def test_create_entry_inserts_user_scoped_row(mock_db):
    db = _fluent(execute_data=[{"id": "f1"}])
    mock_db.return_value = db
    out = repository.create_entry(
        "u1",
        {
            "logged_on": "2026-05-31",
            "meal": "dinner",
            "food_name": "Ribeye steak",
            "quantity_g": 250,
            "energy_kcal": 750,
        },
    )
    db.table.assert_called_with("food_entries")
    inserted = db.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["food_name"] == "Ribeye steak"
    assert inserted["quantity_g"] == 250
    assert out["id"] == "f1"


@patch("app.food_diary.repository.get_supabase")
def test_delete_entry_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_entry("u1", "f1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "f1") in eq_calls


# ── Open Food Facts client ───────────────────────────────────────────────────────

def _off_product():
    return {
        "code": "737628064502",
        "product_name": "Ribeye steak",
        "brands": "ButcherCo",
        "quantity": "250 g",
        "nutriments": {
            "energy-kcal_100g": "291",
            "carbohydrates_100g": 0,
            "proteins_100g": "24",
            "fat_100g": "22",
        },
    }


def test_normalise_maps_off_fields():
    out = openfoodfacts._normalise(_off_product())
    assert out["name"] == "Ribeye steak"
    assert out["brand"] == "ButcherCo"
    assert out["energy_kcal_100g"] == 291.0
    assert out["carbs_100g"] == 0.0
    assert out["protein_100g"] == 24.0


def test_normalise_drops_nameless_product():
    assert openfoodfacts._normalise({"code": "1", "product_name": ""}) is None


def test_num_handles_bad_values():
    assert openfoodfacts._num("") is None
    assert openfoodfacts._num(None) is None
    assert openfoodfacts._num("abc") is None
    assert openfoodfacts._num("12.5") == 12.5


@patch("app.food_diary.openfoodfacts.httpx.Client")
def test_search_products_normalises(mock_client_cls):
    mock_client = MagicMock()
    mock_client.__enter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"products": [_off_product(), {"product_name": ""}]}
    mock_client.get.return_value = resp
    mock_client_cls.return_value = mock_client

    out = openfoodfacts.search_products("ribeye")
    assert len(out) == 1  # the nameless product is dropped
    assert out[0]["name"] == "Ribeye steak"


@patch("app.food_diary.openfoodfacts.httpx.Client")
def test_lookup_barcode_returns_none_when_not_found(mock_client_cls):
    mock_client = MagicMock()
    mock_client.__enter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"status": 0}
    mock_client.get.return_value = resp
    mock_client_cls.return_value = mock_client

    assert openfoodfacts.lookup_barcode("000") is None


# ── HTTP endpoints ───────────────────────────────────────────────────────────────

@patch("app.food_diary.router.repository.list_entries")
def test_list_endpoint(mock_list):
    mock_list.return_value = [{"id": "f1", "food_name": "Eggs"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary?date=2026-05-31")
        assert res.status_code == 200
        assert res.json()[0]["food_name"] == "Eggs"
        mock_list.assert_called_once_with("u1", "2026-05-31")
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.repository.create_entry")
def test_create_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "f1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/food-diary",
            json={"logged_on": "2026-05-31", "meal": "dinner", "food_name": "Ribeye"},
        )
        assert res.status_code == 201
        mock_create.assert_called_once()
    finally:
        app.dependency_overrides.clear()


def test_create_endpoint_rejects_invalid_meal():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/food-diary",
            json={"logged_on": "2026-05-31", "meal": "brunch", "food_name": "Ribeye"},
        )
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.openfoodfacts.search_products")
def test_search_endpoint(mock_search):
    mock_search.return_value = [{"code": "1", "name": "Ribeye"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=ribeye")
        assert res.status_code == 200
        assert res.json()[0]["name"] == "Ribeye"
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.openfoodfacts.search_products")
def test_search_endpoint_handles_off_outage(mock_search):
    mock_search.side_effect = httpx.ConnectError("boom")
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=ribeye")
        assert res.status_code == 502
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.openfoodfacts.lookup_barcode")
def test_barcode_endpoint_404_when_missing(mock_lookup):
    mock_lookup.return_value = None
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/barcode/000")
        assert res.status_code == 404
    finally:
        app.dependency_overrides.clear()
