from __future__ import annotations

from app.db import get_supabase

_COLUMNS = "id,measured_on,steps,active_energy_kcal,exercise_minutes,source,created_at"


def list_metrics(user_id: str) -> list[dict]:
    db = get_supabase()
    resp = (
        db.table("activity_metrics")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .order("measured_on")
        .limit(50000)
        .execute()
    )
    return resp.data or []


def upsert_metrics_batch(user_id: str, metrics: list[dict]) -> list[dict]:
    """Upsert a batch of daily activity rows.

    ON CONFLICT (user_id, measured_on) → overwrite all three columns so that
    re-syncing a still-growing day (e.g. today's step count) settles to the
    latest value rather than keeping the first partial reading.
    """
    if not metrics:
        return []
    db = get_supabase()
    rows = [
        {
            "user_id": user_id,
            "measured_on": m["measured_on"],
            "steps": m.get("steps"),
            "active_energy_kcal": m.get("active_energy_kcal"),
            "exercise_minutes": m.get("exercise_minutes"),
            "source": m.get("source", "healthkit"),
        }
        for m in metrics
    ]
    resp = (
        db.table("activity_metrics")
        .upsert(rows, on_conflict="user_id,measured_on")
        .execute()
    )
    return resp.data or []


def delete_metrics_by_source(user_id: str, source: str) -> int:
    db = get_supabase()
    resp = (
        db.table("activity_metrics")
        .delete()
        .eq("user_id", user_id)
        .eq("source", source)
        .execute()
    )
    return len(resp.data) if resp.data else 0
