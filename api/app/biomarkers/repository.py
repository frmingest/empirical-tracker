from __future__ import annotations

from datetime import date

from app.db import get_supabase
from fastapi import HTTPException
from postgrest.exceptions import APIError as PostgrestAPIError


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
    try:
        resp = (
            db.table("panels")
            .insert({"user_id": user_id, "tested_at": tested_at.isoformat(), "source": source})
            .execute()
        )
        return resp.data[0]["id"]
    except PostgrestAPIError as exc:
        if exc.code == "23505":
            raise HTTPException(
                status_code=409,
                detail=f"A panel for {tested_at} already exists. Delete the existing records first, then re-import.",
            ) from exc
        raise


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


def add_manual_result(
    user_id: str,
    biomarker_id: str,
    tested_at: str,
    value: float,
) -> dict:
    """Add or update a single result for a given biomarker + date.

    Steps:
    1. Fetch the biomarker to get ref_type, ref_low, ref_high.
    2. Compute in_range.
    3. Upsert the panel for (user_id, tested_at).
    4. Upsert the result on (biomarker_id, panel_id).
    """
    db = get_supabase()

    # 1. Fetch biomarker
    bio_resp = (
        db.table("biomarkers")
        .select("id,ref_type,ref_low,ref_high")
        .eq("id", biomarker_id)
        .eq("user_id", user_id)
        .single()
        .execute()
    )
    bio = bio_resp.data

    # 2. Compute in_range
    ref_type: str = bio.get("ref_type", "none")
    ref_low: float | None = bio.get("ref_low")
    ref_high: float | None = bio.get("ref_high")

    in_range: bool | None = None
    if ref_type == "bounded" and ref_low is not None and ref_high is not None:
        in_range = ref_low <= value <= ref_high
    elif ref_type == "lt" and ref_high is not None:
        in_range = value < ref_high
    elif ref_type == "gt" and ref_low is not None:
        in_range = value > ref_low

    # 3. Upsert panel for this date
    panel_resp = (
        db.table("panels")
        .upsert(
            {"user_id": user_id, "tested_at": tested_at, "source": "manual"},
            on_conflict="user_id,tested_at",
        )
        .execute()
    )
    panel_id: str = panel_resp.data[0]["id"]

    # 4. Upsert result
    result_resp = (
        db.table("results")
        .upsert(
            {
                "user_id": user_id,
                "panel_id": panel_id,
                "biomarker_id": biomarker_id,
                "value": value,
                "in_range": in_range,
            },
            on_conflict="biomarker_id,panel_id",
        )
        .execute()
    )
    return result_resp.data[0]
