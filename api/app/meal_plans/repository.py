from __future__ import annotations

from app.db import get_supabase

# Meal slots a planned meal can belong to. Mirrors the CHECK constraint in
# migrations/006_meal_plans.sql (and the food_entries slots from Sprint 4).
VALID_MEALS = {"breakfast", "lunch", "dinner", "snack", "other"}

_PLAN_COLUMNS = "id,name,description,created_at"
_MEAL_COLUMNS = (
    "id,plan_id,scheduled_on,meal,food_name,brand,barcode,"
    "quantity_g,energy_kcal,carbs_g,protein_g,fat_g,sodium_mg,saturated_fat_g,note,done"
)


# ── Named plans ─────────────────────────────────────────────────────────────────


def list_plans(user_id: str) -> list[dict]:
    """Return the user's meal plans, newest first."""
    db = get_supabase()
    resp = (
        db.table("meal_plans")
        .select(_PLAN_COLUMNS)
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return resp.data or []


def create_plan(user_id: str, name: str, description: str | None) -> dict:
    """Insert a meal plan and return the stored row."""
    db = get_supabase()
    resp = (
        db.table("meal_plans")
        .insert({"user_id": user_id, "name": name, "description": description})
        .execute()
    )
    return resp.data[0] if resp.data else {}


def delete_plan(user_id: str, plan_id: str) -> None:
    """Delete one of the user's plans (no-op if it isn't theirs).

    Scheduled meals survive: the FK is ON DELETE SET NULL, so they stay on the
    calendar with their plan_id cleared.
    """
    db = get_supabase()
    (
        db.table("meal_plans")
        .delete()
        .eq("id", plan_id)
        .eq("user_id", user_id)
        .execute()
    )


# ── Scheduled meals (the calendar) ──────────────────────────────────────────────


def list_planned_meals(
    user_id: str, start: str | None = None, end: str | None = None
) -> list[dict]:
    """Return the user's planned meals, optionally within a [start, end] window.

    Both bounds are inclusive ISO dates ("YYYY-MM-DD"). The calendar view fetches
    one week at a time by passing the week's first and last day.
    """
    db = get_supabase()
    query = db.table("planned_meals").select(_MEAL_COLUMNS).eq("user_id", user_id)
    if start:
        query = query.gte("scheduled_on", start)
    if end:
        query = query.lte("scheduled_on", end)
    resp = query.order("scheduled_on").execute()
    return resp.data or []


def create_planned_meal(user_id: str, meal: dict) -> dict:
    """Insert a planned meal and return the stored row."""
    db = get_supabase()
    row = {
        "user_id": user_id,
        "plan_id": meal.get("plan_id"),
        "scheduled_on": meal["scheduled_on"],
        "meal": meal["meal"],
        "food_name": meal["food_name"],
        "brand": meal.get("brand"),
        "barcode": meal.get("barcode"),
        "quantity_g": meal.get("quantity_g"),
        "energy_kcal": meal.get("energy_kcal"),
        "carbs_g": meal.get("carbs_g"),
        "protein_g": meal.get("protein_g"),
        "fat_g": meal.get("fat_g"),
        "sodium_mg": meal.get("sodium_mg"),
        "saturated_fat_g": meal.get("saturated_fat_g"),
        "note": meal.get("note"),
        "done": meal.get("done", False),
    }
    resp = db.table("planned_meals").insert(row).execute()
    return resp.data[0] if resp.data else {}


def set_planned_meal_done(user_id: str, meal_id: str, done: bool) -> dict:
    """Flip the done flag on one of the user's planned meals."""
    db = get_supabase()
    resp = (
        db.table("planned_meals")
        .update({"done": done})
        .eq("id", meal_id)
        .eq("user_id", user_id)
        .execute()
    )
    return resp.data[0] if resp.data else {}


def delete_planned_meal(user_id: str, meal_id: str) -> None:
    """Delete one of the user's planned meals (no-op if it isn't theirs)."""
    db = get_supabase()
    (
        db.table("planned_meals")
        .delete()
        .eq("id", meal_id)
        .eq("user_id", user_id)
        .execute()
    )
