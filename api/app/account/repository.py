from __future__ import annotations

from datetime import UTC, datetime

from app.db import get_service_supabase, get_supabase
from app.recipes import repository as recipes_repository

# Every table that holds user-owned rows. All carry a `user_id` column and an
# RLS policy scoping rows to their owner, so a single per-user query is enough
# to gather (export) or erase (delete) a user's complete footprint.
USER_TABLES: tuple[str, ...] = (
    "biomarkers",
    "panels",
    "results",
    "user_settings",
    "diet_events",
    "food_entries",
    "meal_plans",
    "planned_meals",
    "body_metrics",
    "recipes",
    "recipe_favorites",
)

# Deletion order: children before parents, so foreign-key constraints never
# block erasure (results → panels/biomarkers; planned_meals → meal_plans;
# recipe_favorites → recipes). body_metrics is a standalone table (no children),
# so its position is free.
DELETE_ORDER: tuple[str, ...] = (
    "results",
    "planned_meals",
    "food_entries",
    "diet_events",
    "body_metrics",
    "meal_plans",
    "panels",
    "biomarkers",
    "user_settings",
    "recipe_favorites",
    "recipes",
)


def collect_user_data(user_id: str) -> dict[str, list[dict]]:
    """Gather every row this user owns, keyed by table (GDPR Art. 20 export)."""
    db = get_supabase()
    data: dict[str, list[dict]] = {}
    for table in USER_TABLES:
        resp = db.table(table).select("*").eq("user_id", user_id).execute()
        data[table] = resp.data or []
    return data


def build_export(user_id: str) -> dict:
    """A full export document: metadata plus all of the user's data."""
    data = collect_user_data(user_id)
    return {
        "export_meta": {
            "app": "Empirical Tracker",
            "user_id": user_id,
            "exported_at": datetime.now(UTC).isoformat(),
            "format_version": 1,
            "row_counts": {table: len(rows) for table, rows in data.items()},
        },
        "data": data,
    }


def delete_user_data(user_id: str) -> dict:
    """Erase all of a user's data, then remove the auth account itself.

    Right-to-erasure (GDPR Art. 17). Data rows are deleted explicitly — child
    tables first — rather than leaning on the ``auth.users`` ON DELETE CASCADE,
    so erasure is transparent and unit-testable. The auth user is then removed
    so the account is fully gone; if the admin step is unavailable the health
    data is already deleted, and we report that the login record may linger.

    Erasure is a genuinely administrative operation — it removes the auth user
    via the admin API and must complete regardless of any RLS edge case — so it
    runs on the service-role client (the one sanctioned service-role data path,
    ADR-026). The export path, by contrast, uses the user's RLS-scoped client.
    """
    db = get_service_supabase()

    # Before erasing, donate the user's *public* recipes into the anonymous
    # `recipe_catalogue` so the curated catalogue value survives de-identified
    # (ADR-028). Private recipes are kept out, and the `recipes` rows themselves
    # are then hard-deleted with the rest of the user's data below.
    public_recipes = (
        db.table("recipes")
        .select("*")
        .eq("user_id", user_id)
        .eq("is_public", True)
        .execute()
    )
    recipes_repository.donate_recipes(db, public_recipes.data or [])

    for table in DELETE_ORDER:
        db.table(table).delete().eq("user_id", user_id).execute()

    try:
        db.auth.admin.delete_user(user_id)
        account_deleted = True
    except Exception:
        # The data is already erased; only the auth record may remain.
        account_deleted = False

    return {"data_deleted": True, "account_deleted": account_deleted}
