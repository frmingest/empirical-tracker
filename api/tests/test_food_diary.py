import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.food_diary import repository
from app.food_sources import openfoodfacts
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
    # Sprint 9 columns are always written (None when not supplied).
    assert "sodium_mg" in inserted
    assert "saturated_fat_g" in inserted
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
    assert out["source"] == "off"


def test_normalise_drops_nameless_product():
    assert openfoodfacts._normalise({"code": "1", "product_name": ""}) is None


# ── Sprint 9: sodium, saturated fat, kJ→kcal fallback ────────────────────────────

def test_normalise_maps_saturated_fat():
    product = _off_product()
    product["nutriments"]["saturated-fat_100g"] = "9.5"
    out = openfoodfacts._normalise(product)
    assert out["saturated_fat_100g"] == 9.5


def test_normalise_derives_sodium_from_salt():
    # OFF salt (g) → sodium: salt = sodium × 2.5, returned in mg.
    product = _off_product()
    product["nutriments"]["salt_100g"] = "1.0"  # → 0.4 g sodium → 400 mg
    out = openfoodfacts._normalise(product)
    assert out["sodium_mg_100g"] == 400.0


def test_normalise_prefers_measured_sodium_over_salt():
    product = _off_product()
    product["nutriments"]["sodium_100g"] = "0.5"  # 0.5 g → 500 mg
    product["nutriments"]["salt_100g"] = "9.9"     # ignored when sodium present
    out = openfoodfacts._normalise(product)
    assert out["sodium_mg_100g"] == 500.0


def test_normalise_sodium_none_when_absent():
    product = _off_product()  # no salt or sodium fields
    out = openfoodfacts._normalise(product)
    assert out["sodium_mg_100g"] is None


def test_energy_falls_back_from_kj_when_kcal_absent():
    # Only the kJ field present → convert at 4.184 kJ/kcal.
    product = _off_product()
    del product["nutriments"]["energy-kcal_100g"]
    product["nutriments"]["energy_100g"] = "1000"  # kJ → 239.0 kcal
    out = openfoodfacts._normalise(product)
    assert out["energy_kcal_100g"] == 239.0


def test_energy_prefers_kcal_when_present():
    product = _off_product()
    product["nutriments"]["energy_100g"] = "9999"  # kJ ignored when kcal present
    out = openfoodfacts._normalise(product)
    assert out["energy_kcal_100g"] == 291.0


def test_num_handles_bad_values():
    assert openfoodfacts._num("") is None
    assert openfoodfacts._num(None) is None
    assert openfoodfacts._num("abc") is None
    assert openfoodfacts._num("12.5") == 12.5


@patch("app.food_sources.openfoodfacts.httpx.AsyncClient")
def test_search_products_normalises(mock_client_cls):
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"products": [_off_product(), {"product_name": ""}]}
    mock_client.get.return_value = resp
    mock_client_cls.return_value = mock_client

    out = asyncio.run(openfoodfacts.search_products("ribeye"))
    assert len(out) == 1  # the nameless product is dropped
    assert out[0]["name"] == "Ribeye steak"


@patch("app.food_sources.openfoodfacts.httpx.AsyncClient")
def test_search_products_drops_entries_without_nutriments(mock_client_cls):
    # OFF often returns named products with empty nutriments; those are useless
    # in the diary (all "—"), so search drops them. A named hit with no energy
    # sits alongside the good ribeye and must not appear in the results.
    empty = {"code": "2", "product_name": "Mystery snack", "nutriments": {}}
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"products": [_off_product(), empty]}
    mock_client.get.return_value = resp
    mock_client_cls.return_value = mock_client

    out = asyncio.run(openfoodfacts.search_products("ribeye"))
    assert [i["name"] for i in out] == ["Ribeye steak"]


@patch("app.food_sources.openfoodfacts.httpx.AsyncClient")
def test_lookup_barcode_returns_none_when_not_found(mock_client_cls):
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"status": 0}
    mock_client.get.return_value = resp
    mock_client_cls.return_value = mock_client

    assert asyncio.run(openfoodfacts.lookup_barcode("000")) is None


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


@patch("app.food_diary.router.registry.search")
def test_search_endpoint(mock_search):
    mock_search.return_value = [{"code": "1", "name": "Ribeye", "source": "off"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=ribeye")
        assert res.status_code == 200
        assert res.json()[0]["name"] == "Ribeye"
        # Default source is now "all" — merge every source so results are never
        # blank (ADR-018), rather than the old Open-Food-Facts-only default.
        assert mock_search.call_args.args == ("ribeye", "all")
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.registry.search")
def test_search_endpoint_forwards_source(mock_search):
    mock_search.return_value = []
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=egg&source=mvt")
        assert res.status_code == 200
        assert mock_search.call_args.args == ("egg", "mvt")
    finally:
        app.dependency_overrides.clear()


def test_search_endpoint_rejects_unknown_source():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=egg&source=bogus")
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.registry.search")
def test_search_endpoint_handles_source_outage(mock_search):
    mock_search.side_effect = httpx.ConnectError("boom")
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/search?q=ribeye")
        assert res.status_code == 502
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.openfoodfacts.lookup_barcode")
@patch("app.food_diary.router.custom_source.lookup_barcode_with_user")
def test_barcode_endpoint_404_when_missing(mock_custom_lookup, mock_off_lookup):
    # Custom source returns nothing; OFF also returns nothing → 404.
    mock_custom_lookup.return_value = None
    mock_off_lookup.return_value = None
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/barcode/000")
        assert res.status_code == 404
    finally:
        app.dependency_overrides.clear()


@patch("app.food_diary.router.openfoodfacts.lookup_barcode")
@patch("app.food_diary.router.custom_source.lookup_barcode_with_user")
def test_barcode_endpoint_returns_custom_food_when_found(mock_custom_lookup, mock_off_lookup):
    # Custom source hit takes priority — OFF should not be called.
    custom_item = {"code": "my-id", "name": "My Granola", "source": "custom"}
    mock_custom_lookup.return_value = custom_item
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/food-diary/barcode/4011200296987")
        assert res.status_code == 200
        assert res.json()["source"] == "custom"
        mock_off_lookup.assert_not_called()
    finally:
        app.dependency_overrides.clear()
