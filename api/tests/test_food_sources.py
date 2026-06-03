import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import httpx

from app.food_sources import matvaretabellen, registry, usda
from app.food_sources.base import (
    SOURCE_MVT,
    SOURCE_OFF,
    SOURCE_USDA,
    make_food_item,
)

# ── base shape ────────────────────────────────────────────────────────────────

def test_make_food_item_stamps_source_and_defaults():
    item = make_food_item(source=SOURCE_MVT, name="Egg", protein_100g=12.6)
    assert item["source"] == SOURCE_MVT
    assert item["name"] == "Egg"
    assert item["protein_100g"] == 12.6
    # Unspecified nutrients default to None, never a guess.
    assert item["carbs_100g"] is None
    assert item["code"] == ""


# ── Matvaretabellen (vendored, in-process) ──────────────────────────────────────

def test_mvt_search_finds_whole_food():
    out = matvaretabellen.search("egg")
    assert out, "expected the vendored table to contain egg"
    assert all(i["source"] == SOURCE_MVT for i in out)
    assert any("egg" in i["name"].lower() for i in out)
    # Whole foods carry the macros the diary tracks.
    top = out[0]
    assert top["protein_100g"] is not None
    assert top["energy_kcal_100g"] is not None


def test_mvt_search_requires_all_terms():
    # "ribeye" is part of the entrecôte entry; a nonsense second term excludes it.
    assert matvaretabellen.search("storfe ribeye")
    assert matvaretabellen.search("storfe xyzzy") == []


def test_mvt_search_empty_query_returns_nothing():
    assert matvaretabellen.search("   ") == []


def test_mvt_search_respects_page_size():
    out = matvaretabellen.search("storfe", page_size=1)
    assert len(out) <= 1


def test_mvt_search_products_is_async_wrapper():
    out = asyncio.run(matvaretabellen.search_products("smør"))
    assert any("smør" in i["name"].lower() for i in out)


# ── USDA FoodData Central (keyed, cached proxy) ─────────────────────────────────

def _fdc_food():
    return {
        "fdcId": 123,
        "description": "Egg, whole, raw, fresh",
        "foodNutrients": [
            {"nutrientNumber": "208", "value": 143},
            {"nutrientNumber": "203", "value": 12.6},
            {"nutrientNumber": "204", "value": 9.5},
            {"nutrientNumber": "205", "value": 0.7},
            {"nutrientNumber": "606", "value": 3.1},
            {"nutrientNumber": "307", "value": 142},
        ],
    }


def test_usda_normalise_maps_nutrient_numbers():
    out = usda._normalise(_fdc_food())
    assert out["source"] == SOURCE_USDA
    assert out["name"] == "Egg, whole, raw, fresh"
    assert out["energy_kcal_100g"] == 143.0
    assert out["protein_100g"] == 12.6
    assert out["saturated_fat_100g"] == 3.1
    assert out["sodium_mg_100g"] == 142.0
    assert out["code"] == "123"


def test_usda_normalise_drops_nameless():
    assert usda._normalise({"fdcId": 1, "description": ""}) is None


def test_usda_normalise_maps_branded_brand_and_package():
    # A Branded hit carries a consumer brand name and a package weight (ADR-018).
    branded = {
        "fdcId": 999,
        "description": "Grass-Fed Ribeye",
        "brandName": "ButcherCo",
        "brandOwner": "ButcherCo Holdings LLC",
        "packageWeight": "340 g",
        "foodNutrients": [{"nutrientNumber": "208", "value": 291}],
    }
    out = usda._normalise(branded)
    assert out["brand"] == "ButcherCo"  # brandName preferred over brandOwner
    assert out["quantity"] == "340 g"
    assert out["energy_kcal_100g"] == 291.0


def test_usda_search_returns_empty_without_key():
    with patch("app.food_sources.usda.get_settings") as mock_settings:
        mock_settings.return_value = MagicMock(usda_fdc_api_key="")
        out = asyncio.run(usda.search_products("egg"))
    assert out == []


@patch("app.food_sources.usda.httpx.AsyncClient")
def test_usda_search_normalises_and_caches(mock_client_cls):
    usda._cache.clear()
    mock_client = AsyncMock()
    mock_client.__aenter__.return_value = mock_client
    resp = MagicMock()
    resp.json.return_value = {"foods": [_fdc_food(), {"description": ""}]}
    mock_client.post.return_value = resp
    mock_client_cls.return_value = mock_client

    with patch("app.food_sources.usda.get_settings") as mock_settings:
        mock_settings.return_value = MagicMock(usda_fdc_api_key="k")
        out = asyncio.run(usda.search_products("egg whole"))
        assert len(out) == 1  # the nameless hit is dropped
        assert out[0]["source"] == SOURCE_USDA
        # Second identical query is served from cache (no second POST).
        again = asyncio.run(usda.search_products("egg whole"))
    assert again == out
    assert mock_client.post.call_count == 1
    # Branded is queried alongside the analysed whole-food datasets (ADR-018).
    posted = mock_client.post.call_args.kwargs["json"]
    assert "Branded" in posted["dataType"]


# ── registry ────────────────────────────────────────────────────────────────────

def _async_returning(items):
    return AsyncMock(return_value=items)


def _async_failing():
    return AsyncMock(side_effect=httpx.ConnectError("down"))


def test_registry_dispatches_single_source():
    mvt_hit = [{"name": "Egg", "source": "mvt"}]
    with patch.object(matvaretabellen, "search_products", new=_async_returning(mvt_hit)):
        out = asyncio.run(registry.search("egg", SOURCE_MVT))
    assert out[0]["source"] == "mvt"


def test_registry_all_merges_sources():
    with (
        patch.object(
            matvaretabellen, "search_products",
            new=_async_returning([{"name": "Egg", "source": "mvt"}]),
        ),
        patch.object(
            usda, "search_products",
            new=_async_returning([{"name": "Egg US", "source": "usda"}]),
        ),
        patch(
            "app.food_sources.openfoodfacts.search_products",
            new=_async_returning([{"name": "Egg pack", "source": "off"}]),
        ),
    ):
        out = asyncio.run(registry.search("egg", registry.SOURCE_ALL))
    sources = {i["source"] for i in out}
    assert sources == {SOURCE_MVT, SOURCE_USDA, SOURCE_OFF}


def test_registry_all_degrades_when_one_source_fails():
    with (
        patch.object(
            matvaretabellen, "search_products",
            new=_async_returning([{"name": "Egg", "source": "mvt"}]),
        ),
        patch.object(usda, "search_products", new=_async_failing()),
        patch("app.food_sources.openfoodfacts.search_products", new=_async_failing()),
    ):
        out = asyncio.run(registry.search("egg", registry.SOURCE_ALL))
    # The in-memory Norwegian results survive even though the live sources fail.
    assert [i["source"] for i in out] == [SOURCE_MVT]


def test_registry_single_source_propagates_errors():
    with patch.object(usda, "search_products", new=_async_failing()):
        try:
            asyncio.run(registry.search("egg", SOURCE_USDA))
            raised = False
        except httpx.HTTPError:
            raised = True
    assert raised


def test_registry_all_includes_custom_when_user_id_given():
    custom_hit = [{"name": "My Granola", "source": "custom"}]
    with (
        patch.object(
            matvaretabellen, "search_products",
            new=_async_returning([]),
        ),
        patch.object(usda, "search_products", new=_async_returning([])),
        patch("app.food_sources.openfoodfacts.search_products", new=_async_returning([])),
        patch("app.food_sources.custom.search_with_user", new=AsyncMock(return_value=custom_hit)),
    ):
        out = asyncio.run(registry.search("granola", registry.SOURCE_ALL, user_id="u1"))
    assert any(i["source"] == "custom" for i in out)


def test_registry_all_omits_custom_when_no_user_id():
    with (
        patch.object(matvaretabellen, "search_products", new=_async_returning([])),
        patch.object(usda, "search_products", new=_async_returning([])),
        patch("app.food_sources.openfoodfacts.search_products", new=_async_returning([])),
    ):
        out = asyncio.run(registry.search("granola", registry.SOURCE_ALL))
    assert out == []
