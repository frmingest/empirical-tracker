from __future__ import annotations

from app.db import get_supabase

# Columns returned to the client. `created_at` is omitted — the chart and log
# order on `measured_on` only.
_COLUMNS = "id,measured_on,weight_kg,waist_cm,systolic,diastolic,heart_rate_bpm,resting_heart_rate_bpm,hrv_ms,note,source"


def list_metrics(user_id: str) -> list[dict]:
    """Return the user's body metrics, oldest first (chart-friendly order)."""
    db = get_supabase()
    # Supabase/PostgREST defaults to 1 000 rows. Body metrics can exceed that for
    # users who sync years of Apple Health history (daily readings = ~365/yr).
    # 10 000 is well above any realistic lifetime count while still being bounded.
    resp = (
        db.table("body_metrics")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .order("measured_on")
        .limit(10000)
        .execute()
    )
    return resp.data or []


def create_metric(user_id: str, metric: dict) -> dict:
    """Insert a body-metric measurement and return the stored row."""
    db = get_supabase()
    row = {
        "user_id": user_id,
        "measured_on": metric["measured_on"],
        "weight_kg": metric.get("weight_kg"),
        "waist_cm": metric.get("waist_cm"),
        "systolic": metric.get("systolic"),
        "diastolic": metric.get("diastolic"),
        "heart_rate_bpm": metric.get("heart_rate_bpm"),
        "resting_heart_rate_bpm": metric.get("resting_heart_rate_bpm"),
        "hrv_ms": metric.get("hrv_ms"),
        "note": metric.get("note"),
        "source": metric.get("source", "manual"),
    }
    resp = db.table("body_metrics").insert(row).execute()
    return resp.data[0] if resp.data else {}


def delete_metric(user_id: str, metric_id: str) -> None:
    """Delete one of the user's body metrics (no-op if it isn't theirs)."""
    db = get_supabase()
    (
        db.table("body_metrics")
        .delete()
        .eq("id", metric_id)
        .eq("user_id", user_id)
        .execute()
    )


def delete_metrics_by_source(user_id: str, source: str) -> int:
    """Delete all of the user's body metrics from a given source. Returns deleted count."""
    db = get_supabase()
    resp = (
        db.table("body_metrics")
        .delete()
        .eq("user_id", user_id)
        .eq("source", source)
        .execute()
    )
    return len(resp.data) if resp.data else 0
