"""Anonymous donated-facts catalogue (``food_catalogue`` table).

When a user deletes a *public* custom food — or their whole account — its factual
fields are copied into ``food_catalogue``, stripped of ``user_id`` / ``created_at``
/ ``ocr_raw``, and the user-owned row is hard-deleted (ADR-027). This module is
the **read** side: it surfaces those anonymous facts in search and barcode lookup
for the whole userbase, which is the entire point of keeping them. The **write**
(donation) side lives in :mod:`app.food_sources.custom`, on the service-role
client.

Reads run on the request-scoped, RLS-enforcing client: ``food_catalogue``'s
SELECT policy lets any authenticated user read every donated row (there is no
``user_id`` to scope on), mirroring how the read-only external sources behave.
"""

from __future__ import annotations

from app.db import get_supabase
from app.food_sources.base import SOURCE_CATALOGUE, FoodItem, make_food_item

_COLUMNS = (
    "id,food_name,brand,barcode,"
    "energy_kcal,carbs_g,protein_g,fat_g,saturated_fat_g,sodium_mg,serving_g,"
    "ingredients,verified,contributor_count"
)


def _to_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


def _row_to_food_item(row: dict) -> FoodItem:
    return make_food_item(
        source=SOURCE_CATALOGUE,
        code=row["id"],
        name=row["food_name"],
        brand=row.get("brand"),
        quantity=f"{row['serving_g']} g" if row.get("serving_g") else None,
        energy_kcal_100g=_to_float(row.get("energy_kcal")),
        carbs_100g=_to_float(row.get("carbs_g")),
        protein_100g=_to_float(row.get("protein_g")),
        fat_100g=_to_float(row.get("fat_g")),
        saturated_fat_100g=_to_float(row.get("saturated_fat_g")),
        sodium_mg_100g=_to_float(row.get("sodium_mg")),
        ingredients=row.get("ingredients"),
    )


async def search_products(query: str, page_size: int = 20) -> list[FoodItem]:
    """Case-insensitive substring match against the donated catalogue.

    Unscoped by design: the donated facts are anonymous and shared, so every
    authenticated user sees the whole catalogue (the table has no ``user_id``).
    Ordered so the trusted master record surfaces first (ADR-035): ``verified``
    rows (corroborated by ≥2 independent contributors), then by corroboration
    count. The registry merges catalogue results as an ordered block, so this
    ranking carries through to the "all" search.
    """
    db = get_supabase()
    resp = (
        db.table("food_catalogue")
        .select(_COLUMNS)
        .ilike("food_name", f"%{query}%")
        .order("verified", desc=True)
        .order("contributor_count", desc=True)
        .limit(page_size)
        .execute()
    )
    return [_row_to_food_item(r) for r in (resp.data or [])]


async def lookup_barcode(barcode: str) -> FoodItem | None:
    """Exact barcode match against the donated catalogue.

    Prefers the trusted master record (ADR-035) if the raw barcode somehow maps to
    more than one row (raw ``barcode`` is no longer unique — ``barcode_norm`` is).
    """
    db = get_supabase()
    resp = (
        db.table("food_catalogue")
        .select(_COLUMNS)
        .eq("barcode", barcode)
        .order("verified", desc=True)
        .order("contributor_count", desc=True)
        .limit(1)
        .execute()
    )
    if resp.data:
        return _row_to_food_item(resp.data[0])
    return None
