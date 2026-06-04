"""ADR-027: anonymise the custom-food catalogue on delete.

Covers the donate-then-delete path (custom.py), the donation scrubbing rules,
and the read side of the anonymous food_catalogue source.
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

from app.food_sources import custom, food_catalogue, registry
from app.food_sources.base import SOURCE_CATALOGUE


def _fluent(execute_data=None):
    """Fluent mock where every chained query method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data)
    for method in ("table", "select", "eq", "ilike", "delete", "insert", "upsert", "limit"):
        getattr(m, method).return_value = m
    return m


def _public_row():
    return {
        "id": "f1",
        "user_id": "u1",
        "food_name": "Brand X Bar",
        "brand": "Brand X",
        "barcode": "737",
        "energy_kcal": 450,
        "carbs_g": 30,
        "protein_g": 10,
        "fat_g": 20,
        "saturated_fat_g": 8,
        "sodium_mg": 200,
        "serving_g": 50,
        "ingredients": "oats, sugar",
        "ocr_raw": {"text": "scraped label text — possibly identifying"},
        "is_public": True,
        "created_at": "2026-01-02T03:04:05Z",
    }


# ── donation scrubbing ──────────────────────────────────────────────────────────

def test_donate_keeps_only_factual_fields_and_drops_identifiers():
    service = _fluent()
    custom.donate_to_catalogue(service, _public_row())

    donated = service.upsert.call_args.args[0]
    # Factual product fields survive.
    assert donated["food_name"] == "Brand X Bar"
    assert donated["barcode"] == "737"
    assert donated["energy_kcal"] == 450
    assert donated["ingredients"] == "oats, sugar"
    # Identifying / unbounded fields are dropped entirely.
    assert "user_id" not in donated
    assert "created_at" not in donated
    assert "ocr_raw" not in donated
    assert "id" not in donated
    assert "is_public" not in donated
    # A coarse donation date with no tie to the user replaces created_at.
    assert "donated_at" in donated


def test_donate_upserts_on_barcode_to_dedupe():
    service = _fluent()
    custom.donate_to_catalogue(service, _public_row())
    service.upsert.assert_called_once()
    assert service.upsert.call_args.kwargs["on_conflict"] == "barcode"
    service.insert.assert_not_called()


def test_donate_inserts_when_no_barcode():
    service = _fluent()
    row = _public_row()
    row["barcode"] = None
    custom.donate_to_catalogue(service, row)
    # No barcode → cannot dedupe, so a plain insert (NULL barcodes stay distinct).
    service.insert.assert_called_once()
    service.upsert.assert_not_called()


# ── delete: donate-then-delete vs hard-delete ───────────────────────────────────

@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_delete_public_food_donates_then_deletes(mock_db, mock_service):
    user_db = _fluent(execute_data=[_public_row()])
    service_db = _fluent()
    mock_db.return_value = user_db
    mock_service.return_value = service_db

    custom.delete_custom_food("u1", "f1")

    # Donated on the service-role client, then erased on the user client.
    service_db.upsert.assert_called_once()
    user_db.delete.assert_called_once()


@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_delete_private_food_is_hard_deleted_without_donation(mock_db, mock_service):
    row = _public_row()
    row["is_public"] = False
    user_db = _fluent(execute_data=[row])
    mock_db.return_value = user_db

    custom.delete_custom_food("u1", "f1")

    # A private row is deleted with nothing kept; the service role is never touched.
    user_db.delete.assert_called_once()
    mock_service.assert_not_called()


@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_delete_missing_food_is_noop(mock_db, mock_service):
    user_db = _fluent(execute_data=[])
    mock_db.return_value = user_db

    custom.delete_custom_food("u1", "nope")

    user_db.delete.assert_not_called()
    mock_service.assert_not_called()


def test_donate_public_foods_donates_each_public_row():
    rows = [_public_row(), {**_public_row(), "id": "f2", "barcode": "738"}]
    service = _fluent(execute_data=rows)
    n = custom.donate_public_foods(service, "u1")
    assert n == 2
    assert service.upsert.call_count == 2
    # Filtered to public rows only.
    eq_calls = [c.args for c in service.eq.call_args_list]
    assert ("is_public", True) in eq_calls


# ── read side: anonymous food_catalogue source ──────────────────────────────────

def test_catalogue_row_maps_to_food_item_with_catalogue_source():
    row = {
        "id": "c1", "food_name": "Donated Bar", "brand": "B",
        "barcode": "737", "energy_kcal": 450, "carbs_g": 30, "protein_g": 10,
        "fat_g": 20, "saturated_fat_g": 8, "sodium_mg": 200, "serving_g": 50,
    }
    item = food_catalogue._row_to_food_item(row)
    assert item["source"] == SOURCE_CATALOGUE
    assert item["name"] == "Donated Bar"
    assert item["energy_kcal_100g"] == 450.0
    assert item["quantity"] == "50 g"


@patch("app.food_sources.food_catalogue.get_supabase")
def test_catalogue_search_is_unscoped(mock_db):
    db = _fluent(execute_data=[{"id": "c1", "food_name": "Bar"}])
    mock_db.return_value = db
    out = asyncio.run(food_catalogue.search_products("bar"))
    assert out[0]["source"] == SOURCE_CATALOGUE
    # No user_id scoping — the donated catalogue is shared (no such column).
    eq_cols = [c.args[0] for c in db.eq.call_args_list]
    assert "user_id" not in eq_cols


@patch("app.food_sources.food_catalogue.get_supabase")
def test_catalogue_barcode_lookup(mock_db):
    db = _fluent(execute_data=[{"id": "c1", "food_name": "Bar", "barcode": "737"}])
    mock_db.return_value = db
    hit = asyncio.run(food_catalogue.lookup_barcode("737"))
    assert hit is not None and hit["source"] == SOURCE_CATALOGUE


# ── registry dispatch ───────────────────────────────────────────────────────────

def test_registry_dispatches_catalogue_single_source():
    cat_hit = [{"name": "Donated", "source": SOURCE_CATALOGUE}]
    with patch(
        "app.food_sources.food_catalogue.search_products",
        new=AsyncMock(return_value=cat_hit),
    ):
        out = asyncio.run(registry.search("donated", SOURCE_CATALOGUE))
    assert out[0]["source"] == SOURCE_CATALOGUE


def test_registry_all_includes_catalogue():
    cat_hit = [{"name": "Donated", "source": SOURCE_CATALOGUE}]
    with (
        patch("app.food_sources.matvaretabellen.search_products", new=AsyncMock(return_value=[])),
        patch("app.food_sources.usda.search_products", new=AsyncMock(return_value=[])),
        patch(
            "app.food_sources.openfoodfacts.search_products", new=AsyncMock(return_value=[])
        ),
        patch(
            "app.food_sources.food_catalogue.search_products",
            new=AsyncMock(return_value=cat_hit),
        ),
    ):
        out = asyncio.run(registry.search("donated", registry.SOURCE_ALL))
    assert any(i["source"] == SOURCE_CATALOGUE for i in out)
