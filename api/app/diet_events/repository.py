from __future__ import annotations

from app.db import get_supabase

# Kinds a diet event can take. Mirrors the CHECK constraint in
# migrations/004_diet_events.sql.
VALID_KINDS = {"diet", "fast", "supplement", "medication", "lifestyle", "other"}

_COLUMNS = "id,label,kind,started_on,ended_on,note"


def list_events(user_id: str) -> list[dict]:
    """Return the user's diet events, oldest first (chart-friendly order)."""
    db = get_supabase()
    resp = (
        db.table("diet_events")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .order("started_on")
        .execute()
    )
    return resp.data or []


def create_event(
    user_id: str,
    label: str,
    kind: str,
    started_on: str,
    ended_on: str | None,
    note: str | None,
) -> dict:
    """Insert a diet event and return the stored row."""
    db = get_supabase()
    resp = (
        db.table("diet_events")
        .insert(
            {
                "user_id": user_id,
                "label": label,
                "kind": kind,
                "started_on": started_on,
                "ended_on": ended_on,
                "note": note,
            }
        )
        .execute()
    )
    return resp.data[0] if resp.data else {}


def delete_event(user_id: str, event_id: str) -> None:
    """Delete one of the user's diet events (no-op if it isn't theirs)."""
    db = get_supabase()
    (
        db.table("diet_events")
        .delete()
        .eq("id", event_id)
        .eq("user_id", user_id)
        .execute()
    )
