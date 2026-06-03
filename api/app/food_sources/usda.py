"""USDA FoodData Central — lab-analysed American whole foods, proxied & cached.

FoodData Central (FDC, USDA Agricultural Research Service) is the American
equivalent of Matvaretabellen and the broadest, most permissively licensed
(public-domain / CC0) food-composition database. It's the natural default for any
non-Norwegian user.

Unlike Matvaretabellen, FDC is large and best queried live, so we proxy it
server-side:

  * It needs a free ``api.data.gov`` key, rate-limited ~1 000 req/h **per key**
    (shared across all our users). The key is a server-only env var; if it's
    unset we degrade gracefully to "no USDA results", exactly like an OFF outage.
  * We query the analysed whole-food datasets (``Foundation`` + ``SR Legacy``)
    **and** the manufacturer-supplied ``Branded`` dataset. Branded was originally
    excluded ("OFF owns branded"), but OFF's crowd-sourced branded entries are
    frequently missing nutriments, leaving the diary blank; FDC Branded is
    manufacturer-declared, near-complete, public-domain (CC0), and carries UPC
    barcodes — a strictly better branded source where it overlaps OFF.
  * Identical queries ("egg", "beef") are served from a small in-memory TTL cache
    so common searches don't burn the shared quota (ADR-018).

FDC publishes nutrients per 100 g; we map them to the diary's ``FoodItem`` shape,
taking values as published — never invented.
"""

from __future__ import annotations

import time

import httpx

from app.config import get_settings
from app.food_sources.base import SOURCE_USDA, FoodItem, make_food_item

_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
# Analysed whole foods (Foundation, SR Legacy) plus manufacturer-declared
# Branded — the latter fills the branded-nutrient gap OFF leaves blank (ADR-018).
_DATA_TYPES = ["Foundation", "SR Legacy", "Branded"]
_TIMEOUT = 20.0
_CACHE_TTL_SECONDS = 3600.0  # common queries change rarely; an hour is plenty.

# FDC nutrient numbers (USDA's stable identifiers), per 100 g.
_NUTRIENT_NUMBERS = {
    "208": "energy_kcal_100g",  # Energy (kcal)
    "205": "carbs_100g",        # Carbohydrate, by difference
    "203": "protein_100g",      # Protein
    "204": "fat_100g",          # Total lipid (fat)
    "606": "saturated_fat_100g",  # Fatty acids, total saturated
    "307": "sodium_mg_100g",    # Sodium, Na (mg)
}

# Tiny in-memory TTL cache: query -> (expires_at, results).
_cache: dict[tuple[str, int], tuple[float, list[FoodItem]]] = {}


def _round1(value: float | None) -> float | None:
    return None if value is None else round(value, 1)


def _normalise(food: dict) -> FoodItem | None:
    """Reduce an FDC search hit to the diary's shape; None if it has no name."""
    name = (food.get("description") or "").strip()
    if not name:
        return None
    nutrients: dict[str, float] = {}
    for entry in food.get("foodNutrients") or []:
        number = str(entry.get("nutrientNumber") or entry.get("number") or "")
        field = _NUTRIENT_NUMBERS.get(number)
        if field is None:
            continue
        value = entry.get("value")
        if value is None:
            value = entry.get("amount")
        if value is not None:
            try:
                nutrients[field] = _round1(float(value))
            except (TypeError, ValueError):
                pass
    return make_food_item(
        source=SOURCE_USDA,
        code=str(food.get("fdcId") or ""),
        name=name,
        # Whole foods are unbranded; a Branded hit carries the consumer-facing
        # brand name (falling back to the owning company) and a package size.
        brand=(food.get("brandName") or food.get("brandOwner") or "").strip() or None,
        quantity=(food.get("packageWeight") or "").strip() or None,
        energy_kcal_100g=nutrients.get("energy_kcal_100g"),
        carbs_100g=nutrients.get("carbs_100g"),
        protein_100g=nutrients.get("protein_100g"),
        fat_100g=nutrients.get("fat_100g"),
        saturated_fat_100g=nutrients.get("saturated_fat_100g"),
        sodium_mg_100g=nutrients.get("sodium_mg_100g"),
    )


def _cache_get(key: tuple[str, int]) -> list[FoodItem] | None:
    hit = _cache.get(key)
    if hit is None:
        return None
    expires_at, results = hit
    if expires_at < time.monotonic():
        _cache.pop(key, None)
        return None
    return results


async def search_products(query: str, page_size: int = 20) -> list[FoodItem]:
    """Search FDC whole foods; [] when no key is configured (graceful degrade)."""
    api_key = get_settings().usda_fdc_api_key
    if not api_key:
        # No key → the source is simply unavailable, like a third-party outage.
        return []

    key = (query.strip().lower(), page_size)
    cached = _cache_get(key)
    if cached is not None:
        return cached

    payload = {
        "query": query,
        "dataType": _DATA_TYPES,
        "pageSize": page_size,
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.post(
            _SEARCH_URL, params={"api_key": api_key}, json=payload
        )
        resp.raise_for_status()
        data = resp.json()

    foods = data.get("foods") or []
    items = [_normalise(f) for f in foods]
    results = [i for i in items if i is not None]
    _cache[key] = (time.monotonic() + _CACHE_TTL_SECONDS, results)
    return results
