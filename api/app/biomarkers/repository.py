from __future__ import annotations

from datetime import UTC, date, datetime

from fastapi import HTTPException
from postgrest.exceptions import APIError as PostgrestAPIError

from app.biomarkers.parser import _parse_ref_range
from app.db import get_supabase


def _compute_in_range(
    value: float | None,
    ref_low: float | None,
    ref_high: float | None,
    ref_type: str,
) -> bool | None:
    """Tri-state in-range flag; mirrors the import/manual-entry rule."""
    if value is None:
        return None
    if ref_type == "bounded" and ref_low is not None and ref_high is not None:
        return ref_low <= value <= ref_high
    if ref_type == "lt" and ref_high is not None:
        return value < ref_high
    if ref_type == "gt" and ref_low is not None:
        return value > ref_low
    return None


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
                detail=(
                    f"A panel for {tested_at} already exists. "
                    "Delete the existing records first, then re-import."
                ),
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


def list_panels(user_id: str) -> list[dict]:
    """Return all panels for a user with per-panel result counts."""
    db = get_supabase()
    panels_resp = (
        db.table("panels")
        .select("id,tested_at,source")
        .eq("user_id", user_id)
        .order("tested_at", desc=True)
        .execute()
    )
    if not panels_resp.data:
        return []

    results_resp = (
        db.table("results")
        .select("panel_id,in_range")
        .eq("user_id", user_id)
        .execute()
    )

    counts: dict[str, dict] = {}
    for r in results_resp.data:
        pid = r["panel_id"]
        if pid not in counts:
            counts[pid] = {"result_count": 0, "in_range_count": 0, "out_range_count": 0}
        counts[pid]["result_count"] += 1
        if r["in_range"] is True:
            counts[pid]["in_range_count"] += 1
        elif r["in_range"] is False:
            counts[pid]["out_range_count"] += 1

    return [
        {
            "id": p["id"],
            "tested_at": p["tested_at"],
            "source": p["source"],
            **counts.get(p["id"], {"result_count": 0, "in_range_count": 0, "out_range_count": 0}),
        }
        for p in panels_resp.data
    ]


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


# ── Lab document imports (ADR-032) ─────────────────────────────────────────────

def create_lab_import(
    user_id: str,
    source_kind: str,
    posture: str,
    extracted: dict,
) -> dict:
    """Persist a candidate extraction as ``pending_review`` and return the row."""
    db = get_supabase()
    resp = (
        db.table("lab_imports")
        .insert(
            {
                "user_id": user_id,
                "source_kind": source_kind,
                "posture": posture,
                "extracted": extracted,
            }
        )
        .execute()
    )
    return resp.data[0]


def list_lab_imports(user_id: str, status: str = "pending_review") -> list[dict]:
    db = get_supabase()
    resp = (
        db.table("lab_imports")
        .select("id,source_kind,posture,extracted,status,created_at,applied_at")
        .eq("user_id", user_id)
        .eq("status", status)
        .order("created_at", desc=True)
        .execute()
    )
    return resp.data or []


def get_lab_import(user_id: str, import_id: str) -> dict | None:
    db = get_supabase()
    resp = (
        db.table("lab_imports")
        .select("id,source_kind,posture,extracted,status")
        .eq("id", import_id)
        .eq("user_id", user_id)
        .execute()
    )
    return resp.data[0] if resp.data else None


def set_lab_import_status(user_id: str, import_id: str, status: str) -> None:
    db = get_supabase()
    patch: dict = {"status": status}
    if status == "applied":
        patch["applied_at"] = datetime.now(UTC).isoformat()
    (
        db.table("lab_imports")
        .update(patch)
        .eq("id", import_id)
        .eq("user_id", user_id)
        .execute()
    )


def apply_panels(user_id: str, panels: list[dict]) -> dict:
    """Write reviewed candidate panels into biomarkers/panels/results.

    Each panel needs a ``tested_at`` (the review UI requires the user to set one)
    and a list of results carrying ``name_no``, numeric ``value`` and optional
    ``unit`` / ``ref_range_raw``. Biomarkers upsert on ``(user_id, name_no)`` so
    unknown analytes are created on the fly; panels upsert on
    ``(user_id, tested_at)`` and results on ``(biomarker_id, panel_id)`` so a
    re-applied or overlapping import is idempotent rather than a conflict.

    Phase 1 writes numeric values only; rows carrying a qualitative ``value_text``
    are skipped until ``results.value_text`` ships (ADR-032 Phase 3).
    """
    db = get_supabase()
    panels_applied = 0
    results_inserted = 0

    for panel in panels:
        tested_at = panel.get("tested_at")
        results = panel.get("results") or []
        if not tested_at:
            continue
        numeric = [r for r in results if r.get("value") is not None and r.get("name_no")]
        if not numeric:
            continue

        # 1. Upsert the biomarker catalog rows for this panel's analytes.
        bio_rows = []
        for r in numeric:
            ref_low, ref_high, ref_type = _parse_ref_range(r.get("ref_range_raw"))
            bio_rows.append(
                {
                    "user_id": user_id,
                    "name_no": r["name_no"],
                    "unit": r.get("unit"),
                    "ref_range_raw": r.get("ref_range_raw") or "",
                    "ref_low": ref_low,
                    "ref_high": ref_high,
                    "ref_type": ref_type,
                }
            )
        db.table("biomarkers").upsert(bio_rows, on_conflict="user_id,name_no").execute()

        ids_resp = (
            db.table("biomarkers")
            .select("id,name_no,ref_low,ref_high,ref_type")
            .eq("user_id", user_id)
            .execute()
        )
        by_name = {row["name_no"]: row for row in ids_resp.data}

        # 2. Upsert the panel for this date.
        panel_resp = (
            db.table("panels")
            .upsert(
                {"user_id": user_id, "tested_at": tested_at, "source": "document_import"},
                on_conflict="user_id,tested_at",
            )
            .execute()
        )
        panel_id = panel_resp.data[0]["id"]
        panels_applied += 1

        # 3. Upsert each numeric result.
        result_rows = []
        for r in numeric:
            bio = by_name.get(r["name_no"])
            if bio is None:
                continue
            in_range = _compute_in_range(
                r["value"], bio.get("ref_low"), bio.get("ref_high"), bio.get("ref_type", "none")
            )
            result_rows.append(
                {
                    "user_id": user_id,
                    "panel_id": panel_id,
                    "biomarker_id": bio["id"],
                    "value": r["value"],
                    "in_range": in_range,
                }
            )
        if result_rows:
            resp = (
                db.table("results")
                .upsert(result_rows, on_conflict="biomarker_id,panel_id")
                .execute()
            )
            results_inserted += len(resp.data)

    return {"panels_applied": panels_applied, "results_inserted": results_inserted}
