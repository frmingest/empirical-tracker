"""User-contributed food catalogue (``custom_foods`` table).

Provides search and barcode lookup backed by the user's own additions plus any
items other users have made public.  Unlike the read-only external sources this
module also owns the create/update/delete path so the router stays thin.
"""

from __future__ import annotations

from app.db import get_supabase
from app.food_sources.base import SOURCE_CUSTOM, FoodItem, make_food_item

_COLUMNS = (
    "id,food_name,brand,barcode,"
    "energy_kcal,carbs_g,protein_g,fat_g,saturated_fat_g,sodium_mg,serving_g"
)


def _row_to_food_item(row: dict) -> FoodItem:
    return make_food_item(
        source=SOURCE_CUSTOM,
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
    )


def _to_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


# ── Search ────────────────────────────────────────────────────────────────────

async def search_products(query: str, page_size: int = 20) -> list[FoodItem]:
    """Case-insensitive substring match against food_name and brand.

    RLS on ``custom_foods`` means this automatically returns only the calling
    user's own items plus any items marked ``is_public``.  The Supabase service
    key bypasses RLS, so we must filter by user_id explicitly — however, this
    function is called by the registry which is invoked after auth middleware has
    already resolved ``user_id``; we receive it as a parameter during fan-out via
    :func:`search_with_user`.
    """
    # This thin wrapper is here so the registry can call it with the standard
    # (query, page_size) signature. It returns an empty list — the real call goes
    # through search_with_user below which includes user_id scoping.
    return []


async def search_with_user(query: str, user_id: str, page_size: int = 20) -> list[FoodItem]:
    """Scoped search; must be used instead of search_products in the router."""
    db = get_supabase()
    resp = (
        db.table("custom_foods")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .ilike("food_name", f"%{query}%")
        .limit(page_size)
        .execute()
    )
    return [_row_to_food_item(r) for r in (resp.data or [])]


async def lookup_barcode_with_user(barcode: str, user_id: str) -> FoodItem | None:
    """Exact barcode match scoped to the user's own items."""
    db = get_supabase()
    resp = (
        db.table("custom_foods")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .eq("barcode", barcode)
        .limit(1)
        .execute()
    )
    if resp.data:
        return _row_to_food_item(resp.data[0])
    return None


# ── CRUD ──────────────────────────────────────────────────────────────────────

def create_custom_food(user_id: str, payload: dict) -> dict:
    """Insert a custom food item and return the full stored row."""
    db = get_supabase()
    row = {
        "user_id": user_id,
        "food_name": payload["food_name"],
        "brand": payload.get("brand"),
        "barcode": payload.get("barcode"),
        "energy_kcal": payload.get("energy_kcal"),
        "carbs_g": payload.get("carbs_g"),
        "protein_g": payload.get("protein_g"),
        "fat_g": payload.get("fat_g"),
        "saturated_fat_g": payload.get("saturated_fat_g"),
        "sodium_mg": payload.get("sodium_mg"),
        "serving_g": payload.get("serving_g"),
        "ingredients": payload.get("ingredients"),
        "ocr_raw": payload.get("ocr_raw"),
    }
    resp = db.table("custom_foods").insert(row).execute()
    return resp.data[0] if resp.data else {}


def update_custom_food(user_id: str, food_id: str, payload: dict) -> dict:
    """Update the user's own custom food. Returns the updated row or {} if not found."""
    db = get_supabase()
    updatable = {
        k: v
        for k, v in payload.items()
        if k in {
            "food_name", "brand", "barcode",
            "energy_kcal", "carbs_g", "protein_g", "fat_g",
            "saturated_fat_g", "sodium_mg", "serving_g", "ingredients",
        }
    }
    if not updatable:
        return {}
    resp = (
        db.table("custom_foods")
        .update(updatable)
        .eq("id", food_id)
        .eq("user_id", user_id)
        .execute()
    )
    return resp.data[0] if resp.data else {}


def delete_custom_food(user_id: str, food_id: str) -> None:
    """Delete the user's own custom food (no-op if not theirs)."""
    db = get_supabase()
    (
        db.table("custom_foods")
        .delete()
        .eq("id", food_id)
        .eq("user_id", user_id)
        .execute()
    )
