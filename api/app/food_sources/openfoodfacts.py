"""Thin client for the Open Food Facts API.

Open Food Facts (https://world.openfoodfacts.org) is a free, open database of
food products under the Open Database License (ODbL). No API key is required;
the only requirement for read access is a descriptive ``User-Agent`` that
identifies the calling application.

We proxy OFF through our own backend (rather than calling it from the browser)
for three reasons:
  * to attach the required ``User-Agent`` consistently,
  * to normalise OFF's messy nutriment field names into a small, stable shape,
  * to avoid leaking the user's browsing to a third party / hitting CORS.

OFF rate-limits search to ~10 requests/minute; the frontend debounces queries
to stay well under that.
"""

from __future__ import annotations

import httpx

from app.food_sources.base import SOURCE_OFF

# OFF asks every caller to identify itself as "AppName/Version (contact)".
USER_AGENT = "EmpiricalTracker/1.0 (https://github.com/frmingest/empirical-tracker)"

_SEARCH_URL = "https://world.openfoodfacts.org/cgi/search.pl"
_PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
_FIELDS = "code,product_name,brands,quantity,nutriments"
_TIMEOUT = 20.0


def _num(value: object) -> float | None:
    """Coerce an OFF nutriment value (often a string) to float, or None."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _round1(value: float | None) -> float | None:
    """Round to one decimal place, preserving None."""
    return None if value is None else round(value, 1)


def _energy_kcal(nutriments: dict) -> float | None:
    """Energy in kcal per 100 g.

    Prefer OFF's ``energy-kcal_100g``. When that's absent, fall back to the
    kilojoule field (``energy_100g``, in kJ) converted at 4.184 kJ/kcal, rather
    than storing nothing — many OFF products carry only the kJ value.
    """
    kcal = _num(nutriments.get("energy-kcal_100g"))
    if kcal is not None:
        return kcal
    kj = _num(nutriments.get("energy_100g"))
    return _round1(kj / 4.184) if kj is not None else None


def _sodium_mg(nutriments: dict) -> float | None:
    """Sodium in milligrams per 100 g.

    OFF may publish ``sodium_100g`` (grams) directly, or only ``salt_100g``
    (grams). Prefer measured sodium; otherwise derive it from salt using the
    standard 2.5 conversion (salt = sodium × 2.5). Result is in mg to match the
    conventional label unit.
    """
    sodium_g = _num(nutriments.get("sodium_100g"))
    if sodium_g is None:
        salt_g = _num(nutriments.get("salt_100g"))
        sodium_g = salt_g / 2.5 if salt_g is not None else None
    return _round1(sodium_g * 1000) if sodium_g is not None else None


def _normalise(product: dict) -> dict | None:
    """Reduce a raw OFF product to the fields the food diary cares about.

    All nutrient values are *per 100 g* exactly as published by Open Food Facts
    — we never invent or estimate them. Products without a usable name are
    dropped so the search results stay clean.
    """
    name = (product.get("product_name") or "").strip()
    if not name:
        return None
    nutriments = product.get("nutriments") or {}
    return {
        "code": product.get("code") or "",
        "name": name,
        "brand": (product.get("brands") or "").strip() or None,
        "quantity": (product.get("quantity") or "").strip() or None,
        # Per-100g values, straight from Open Food Facts. Energy falls back to
        # kJ→kcal and sodium derives from salt when only those are published.
        "energy_kcal_100g": _energy_kcal(nutriments),
        "carbs_100g": _num(nutriments.get("carbohydrates_100g")),
        "protein_100g": _num(nutriments.get("proteins_100g")),
        "fat_100g": _num(nutriments.get("fat_100g")),
        "saturated_fat_100g": _num(nutriments.get("saturated-fat_100g")),
        "sodium_mg_100g": _sodium_mg(nutriments),
        "source": SOURCE_OFF,
    }


async def search_products(query: str, page_size: int = 20) -> list[dict]:
    """Full-text search Open Food Facts; return normalised food items."""
    params = {
        "search_terms": query,
        "search_simple": 1,
        "action": "process",
        "json": 1,
        "page_size": page_size,
        "fields": _FIELDS,
    }
    async with httpx.AsyncClient(timeout=_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
        resp = await client.get(_SEARCH_URL, params=params)
        resp.raise_for_status()
        data = resp.json()
    products = data.get("products") or []
    items = [_normalise(p) for p in products]
    # OFF is crowd-sourced: many search hits carry a name but *no* nutriments at
    # all, which would render as a useless all-"—" row in the diary. We drop
    # those here so search results only show foods we can actually log. Energy is
    # the gate — without it (after the kJ fallback) the entry has no usable
    # numbers. Barcode lookup does NOT filter: a deliberately scanned product is
    # shown as-is. This never invents data; it only hides empties (ADR-018).
    return [i for i in items if i is not None and i["energy_kcal_100g"] is not None]


async def lookup_barcode(barcode: str) -> dict | None:
    """Look up a single product by its barcode; None if not found."""
    url = _PRODUCT_URL.format(barcode=barcode)
    async with httpx.AsyncClient(timeout=_TIMEOUT, headers={"User-Agent": USER_AGENT}) as client:
        resp = await client.get(url, params={"fields": _FIELDS})
        resp.raise_for_status()
        data = resp.json()
    if data.get("status") != 1:  # 1 = found, 0 = not found
        return None
    return _normalise(data.get("product") or {})
