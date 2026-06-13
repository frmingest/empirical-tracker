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
    for method in (
        "table", "select", "eq", "ilike", "delete",
        "insert", "update", "upsert", "limit", "order", "rpc",
    ):
        getattr(m, method).return_value = m
    return m


def _rpc_facts(mock_client):
    """The de-identified facts payload passed to the donate_catalogue RPC."""
    return mock_client.rpc.call_args.args[1]["p_facts"]


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

    donated = _rpc_facts(service)
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


def test_donate_goes_through_donate_catalogue_rpc():
    service = _fluent()
    custom.donate_to_catalogue(service, _public_row())
    # ADR-035: donation runs through the atomic RPC (upsert + conflict policy +
    # corroboration count), not a plain table upsert/insert.
    service.rpc.assert_called_once()
    assert service.rpc.call_args.args[0] == "donate_catalogue"
    service.upsert.assert_not_called()
    service.insert.assert_not_called()


def test_donate_forwards_prior_catalogue_id_for_corroboration_count():
    service = _fluent()
    row = {**_public_row(), "catalogue_id": "cat-existing"}
    custom.donate_to_catalogue(service, row)
    # ADR-035: the donor's CURRENT back-pointer is passed so the RPC can tell a new
    # corroboration (newly linking row) from a re-sync — without storing identity.
    assert service.rpc.call_args.args[1]["p_prior_catalogue_id"] == "cat-existing"


def test_donate_barcodeless_still_goes_through_rpc():
    service = _fluent()
    row = _public_row()
    row["barcode"] = None
    custom.donate_to_catalogue(service, row)
    # ADR-034/035: the SQL function picks dedup_key internally; the barcodeless
    # row still merges cross-user via the same RPC, never a fresh insert.
    service.rpc.assert_called_once()
    assert _rpc_facts(service)["barcode"] is None
    service.insert.assert_not_called()


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
    service_db.rpc.assert_called_once()
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
    assert service.rpc.call_count == 2
    # Filtered to public rows only.
    eq_calls = [c.args for c in service.eq.call_args_list]
    assert ("is_public", True) in eq_calls


# ── proactive donation: mirror on create / update (ADR-029) ─────────────────────

@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_create_public_food_mirrors_to_catalogue(mock_db, mock_service):
    stored = {**_public_row(), "catalogue_id": None}
    user_db = _fluent(execute_data=[stored])
    service_db = _fluent(execute_data=[{"id": "cat1"}])
    mock_db.return_value = user_db
    mock_service.return_value = service_db

    custom.create_custom_food(
        "u1", {"food_name": "Brand X Bar", "barcode": "737", "is_public": True}
    )

    # Donated to the catalogue at create time via the RPC, de-identified.
    service_db.rpc.assert_called_once()
    donated = _rpc_facts(service_db)
    assert "user_id" not in donated and "ocr_raw" not in donated
    # The de-identified back-pointer is recorded on the user's own row.
    update_args = [c.args[0] for c in user_db.update.call_args_list]
    assert {"catalogue_id": "cat1"} in update_args


@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_create_private_food_is_not_mirrored(mock_db, mock_service):
    stored = {**_public_row(), "is_public": False, "catalogue_id": None}
    user_db = _fluent(execute_data=[stored])
    mock_db.return_value = user_db

    custom.create_custom_food("u1", {"food_name": "Brand X Bar", "is_public": False})

    # Nothing shared → nothing retained; the service role is never touched.
    mock_service.assert_not_called()


@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_create_barcodeless_public_food_merges_on_dedup_key_and_links(mock_db, mock_service):
    stored = {**_public_row(), "barcode": None, "catalogue_id": None}
    user_db = _fluent(execute_data=[stored])
    service_db = _fluent(execute_data=[{"id": "cat9"}])
    mock_db.return_value = user_db
    mock_service.return_value = service_db

    custom.create_custom_food("u1", {"food_name": "Brand X Bar", "is_public": True})

    # ADR-034/035: barcodeless → merges cross-user via the RPC (SQL picks dedup_key
    # internally), then the twin id is linked back.
    service_db.rpc.assert_called_once()
    assert service_db.rpc.call_args.args[0] == "donate_catalogue"
    assert _rpc_facts(service_db)["barcode"] is None
    service_db.insert.assert_not_called()
    update_args = [c.args[0] for c in user_db.update.call_args_list]
    assert {"catalogue_id": "cat9"} in update_args


@patch("app.food_sources.custom.get_service_supabase")
@patch("app.food_sources.custom.get_supabase")
def test_delete_already_mirrored_food_skips_safety_net(mock_db, mock_service):
    # Mirrored at create time (catalogue_id set) → deletion keeps the anonymous
    # twin and does NOT re-donate; it just hard-deletes the user row.
    row = {**_public_row(), "catalogue_id": "cat1"}
    user_db = _fluent(execute_data=[row])
    mock_db.return_value = user_db

    custom.delete_custom_food("u1", "f1")

    user_db.delete.assert_called_once()
    mock_service.assert_not_called()


def test_donate_public_foods_skips_already_mirrored():
    rows = [
        _public_row(),  # not yet mirrored
        {**_public_row(), "id": "f2", "barcode": "738", "catalogue_id": "cat2"},  # mirrored
    ]
    service = _fluent(execute_data=rows)
    n = custom.donate_public_foods(service, "u1")
    # Only the un-mirrored row is donated by the safety net.
    assert n == 1
    service.rpc.assert_called_once()


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
def test_catalogue_search_orders_verified_master_first(mock_db):
    db = _fluent(execute_data=[{"id": "c1", "food_name": "Bar"}])
    mock_db.return_value = db
    asyncio.run(food_catalogue.search_products("bar"))
    # ADR-035: the trusted master record (verified, then most corroborated) is
    # surfaced first; the registry preserves this block order into "all" search.
    ordered = [(c.args[0], c.kwargs.get("desc")) for c in db.order.call_args_list]
    assert ("verified", True) in ordered
    assert ("contributor_count", True) in ordered


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


def test_registry_all_dedupes_owners_own_twin():
    from app.food_sources.base import SOURCE_CUSTOM, make_food_item

    own = [make_food_item(source=SOURCE_CUSTOM, name="Brand X Bar", brand="Brand X")]
    catalogue = [
        # The owner's own donated twin (ADR-029) — must be hidden for them...
        make_food_item(source=SOURCE_CATALOGUE, name="Brand X Bar", brand="Brand X"),
        # ...but another contributor's donated fact still shows.
        make_food_item(source=SOURCE_CATALOGUE, name="Someone Else Bar", brand="Other"),
    ]
    with (
        patch("app.food_sources.matvaretabellen.search_products", new=AsyncMock(return_value=[])),
        patch("app.food_sources.usda.search_products", new=AsyncMock(return_value=[])),
        patch(
            "app.food_sources.openfoodfacts.search_products", new=AsyncMock(return_value=[])
        ),
        patch(
            "app.food_sources.food_catalogue.search_products",
            new=AsyncMock(return_value=catalogue),
        ),
        patch("app.food_sources.custom.search_with_user", new=AsyncMock(return_value=own)),
    ):
        out = asyncio.run(registry.search("bar", registry.SOURCE_ALL, user_id="u1"))

    keyed = [(i["name"], i["source"]) for i in out]
    assert ("Brand X Bar", SOURCE_CUSTOM) in keyed       # own item shown once
    assert ("Brand X Bar", SOURCE_CATALOGUE) not in keyed  # own twin deduped away
    assert ("Someone Else Bar", SOURCE_CATALOGUE) in keyed  # others' facts kept


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
