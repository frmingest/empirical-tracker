from __future__ import annotations

from datetime import UTC, datetime

from app.db import get_supabase

VALID_DIETS = {"all", "carnivore", "low_carb", "fasting", "custom"}

DEFAULT_SETTINGS = {"diet": "all", "custom_markers": []}


def get_settings(user_id: str) -> dict:
    """Return the user's settings row, or sensible defaults if none exists yet."""
    db = get_supabase()
    resp = (
        db.table("user_settings")
        .select("diet,custom_markers")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if resp.data:
        row = resp.data[0]
        return {
            "diet": row.get("diet", "all"),
            "custom_markers": row.get("custom_markers") or [],
        }
    return {"diet": "all", "custom_markers": []}


def upsert_settings(user_id: str, diet: str, custom_markers: list[str]) -> dict:
    """Insert or update the user's settings row; return the stored values."""
    db = get_supabase()
    resp = (
        db.table("user_settings")
        .upsert(
            {
                "user_id": user_id,
                "diet": diet,
                "custom_markers": custom_markers,
                "updated_at": datetime.now(UTC).isoformat(),
            },
            on_conflict="user_id",
        )
        .execute()
    )
    row = resp.data[0] if resp.data else {}
    return {
        "diet": row.get("diet", diet),
        "custom_markers": row.get("custom_markers") or custom_markers,
    }
