from __future__ import annotations

from datetime import date

from app.db import get_supabase


def upsert_biomarkers(user_id: str, biomarkers: list[dict]) -> list[str]:
    """Upsert biomarkers for a user; return their IDs in input order."""
    db = get_supabase()

    rows = [
        {
            "user_id": user_id,
            "name_no": b["name_no"],
            "ref_range_raw": b.get("ref_range_raw", ""),
            "ref_low": b.get("ref_low"),
            "ref_high": b.get("ref_high"),
            "ref_type": b.get("ref_type", "none"),
        }
        for b in biomarkers
    ]

    db.table("biomarkers").upsert(rows, on_conflict="user_id,name_no").execute()

    # Fetch back to guarantee we have IDs for both inserted and pre-existing rows.
    resp = (
        db.table("biomarkers")
        .select("id,name_no")
        .eq("user_id", user_id)
        .execute()
    )
    name_to_id: dict[str, str] = {r["name_no"]: r["id"] for r in resp.data}
    return [name_to_id[b["name_no"]] for b in biomarkers]


def create_panel(user_id: str, tested_at: date, source: str = "xlsx_import") -> str:
    db = get_supabase()
    resp = (
        db.table("panels")
        .insert({"user_id": user_id, "tested_at": tested_at.isoformat(), "source": source})
        .execute()
    )
    return resp.data[0]["id"]


def insert_results(
    user_id: str,
    panel_id: str,
    biomarker_ids: list[str],
    values: list[float | None],
    in_range_flags: list[bool | None],
) -> int:
    """Bulk-insert results, skipping rows where value is None."""
    db = get_supabase()

    rows = [
        {
            "user_id": user_id,
            "panel_id": panel_id,
            "biomarker_id": biomarker_ids[i],
            "value": values[i],
            "in_range": in_range_flags[i],
        }
        for i in range(len(biomarker_ids))
        if values[i] is not None
    ]

    if not rows:
        return 0

    resp = db.table("results").insert(rows).execute()
    return len(resp.data)


def delete_panel(user_id: str, panel_id: str) -> None:
    """Delete a panel and its results (cascade via FK)."""
    db = get_supabase()
    (
        db.table("panels")
        .delete()
        .eq("id", panel_id)
        .eq("user_id", user_id)
        .execute()
    )


def delete_all_panels(user_id: str) -> None:
    """Wipe all panels (and cascading results) for a user."""
    db = get_supabase()
    db.table("panels").delete().eq("user_id", user_id).execute()
