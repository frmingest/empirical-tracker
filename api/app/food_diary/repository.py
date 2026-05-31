from __future__ import annotations

from app.db import get_supabase

# Meal slots a food entry can belong to. Mirrors the CHECK constraint in
# migrations/005_food_entries.sql.
VALID_MEALS = {"breakfast", "lunch", "dinner", "snack", "other"}

_COLUMNS = (
    "id,logged_on,meal,food_name,brand,barcode,"
    "quantity_g,energy_kcal,carbs_g,protein_g,fat_g,note"
)


def list_entries(user_id: str, day: str | None = None) -> list[dict]:
    """Return the user's food entries, optionally filtered to a single day."""
    db = get_supabase()
    query = (
        db.table("food_entries")
        .select(_COLUMNS)
        .eq("user_id", user_id)
    )
    if day:
        query = query.eq("logged_on", day)
    resp = query.order("logged_on", desc=True).execute()
    return resp.data or []


def create_entry(user_id: str, entry: dict) -> dict:
    """Insert a food entry and return the stored row."""
    db = get_supabase()
    row = {
        "user_id": user_id,
        "logged_on": entry["logged_on"],
        "meal": entry["meal"],
        "food_name": entry["food_name"],
        "brand": entry.get("brand"),
        "barcode": entry.get("barcode"),
        "quantity_g": entry.get("quantity_g"),
        "energy_kcal": entry.get("energy_kcal"),
        "carbs_g": entry.get("carbs_g"),
        "protein_g": entry.get("protein_g"),
        "fat_g": entry.get("fat_g"),
        "note": entry.get("note"),
    }
    resp = db.table("food_entries").insert(row).execute()
    return resp.data[0] if resp.data else {}


def delete_entry(user_id: str, entry_id: str) -> None:
    """Delete one of the user's food entries (no-op if it isn't theirs)."""
    db = get_supabase()
    (
        db.table("food_entries")
        .delete()
        .eq("id", entry_id)
        .eq("user_id", user_id)
        .execute()
    )
