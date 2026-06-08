from __future__ import annotations

import tempfile
import zipfile
from collections import defaultdict
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, UploadFile
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.biomarkers import parser, repository
from app.config import get_settings
from app.db import get_supabase
from app.rate_limit import rate_limit

router = APIRouter(prefix="/biomarkers", tags=["biomarkers"])

# .xlsx files are ZIP containers; every valid one starts with the local-file
# header magic. Checking the bytes (not just the extension) stops a renamed
# payload from reaching the XML parser (ADR-026 F3).
_ZIP_MAGIC = b"PK\x03\x04"


async def _read_capped(file: UploadFile, max_bytes: int) -> bytes:
    """Read an upload into memory, refusing anything over ``max_bytes``.

    Reads in chunks so an oversized (or unknown-length) upload is rejected
    without first buffering the whole thing — closing the memory-exhaustion
    surface of an unbounded ``await file.read()`` (ADR-026 F3).
    """
    chunks: list[bytes] = []
    total = 0
    while chunk := await file.read(1024 * 1024):
        total += len(chunk)
        if total > max_bytes:
            raise HTTPException(
                status_code=413,
                detail=f"File too large (limit {max_bytes // (1024 * 1024)} MiB)",
            )
        chunks.append(chunk)
    return b"".join(chunks)


def _assert_safe_xlsx(path: Path, max_uncompressed: int) -> None:
    """Reject non-zip payloads and zip bombs before openpyxl parses the XML.

    openpyxl parses attacker-controlled XML inside the zip; capping the total
    declared uncompressed size guards against decompression-bomb amplification
    (ADR-026 F3).
    """
    if not zipfile.is_zipfile(path):
        raise HTTPException(status_code=400, detail="File is not a valid .xlsx workbook")
    with zipfile.ZipFile(path) as zf:
        if zf.testzip() is not None:
            raise HTTPException(status_code=400, detail="File is not a valid .xlsx workbook")
        total = sum(info.file_size for info in zf.infolist())
    if total > max_uncompressed:
        raise HTTPException(status_code=413, detail="File expands to an unsafe size")


def _in_range(
    value: float | None,
    ref_low: float | None,
    ref_high: float | None,
    ref_type: str,
) -> bool | None:
    if value is None:
        return None
    if ref_type == "bounded" and ref_low is not None and ref_high is not None:
        return ref_low <= value <= ref_high
    if ref_type == "lt" and ref_high is not None:
        return value < ref_high
    if ref_type == "gt" and ref_low is not None:
        return value > ref_low
    return None


class ManualResultIn(BaseModel):
    biomarker_id: str
    tested_at: str   # "YYYY-MM-DD"
    value: float


class LabDocumentIn(BaseModel):
    """On-device-extracted lab-report text (PDFKit text layer / Vision OCR)."""

    text: str
    source_kind: str = "text"  # 'text' | 'pdf' | 'image'

    @field_validator("text")
    @classmethod
    def _non_empty_capped(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("text must not be empty")
        # Same cap as the OCR path so a single request cannot amplify LLM spend
        # or smuggle a large prompt-injection payload (ADR-026 F4).
        max_chars = get_settings().max_ocr_chars
        if len(v) > max_chars:
            raise ValueError(f"text must be at most {max_chars} characters")
        return v

    @field_validator("source_kind")
    @classmethod
    def _known_kind(cls, v: str) -> str:
        if v not in {"text", "pdf", "image"}:
            raise ValueError("source_kind must be one of text, pdf, image")
        return v


class LabResultIn(BaseModel):
    name_no: str
    value: float | None = None
    value_text: str | None = None
    unit: str | None = None
    ref_range_raw: str | None = None


class LabPanelIn(BaseModel):
    tested_at: str | None = None  # "YYYY-MM-DD"; required at apply time
    results: list[LabResultIn] = []


class ApplyLabImportIn(BaseModel):
    panels: list[LabPanelIn]


# ── Import ─────────────────────────────────────────────────────────────────────

@router.post("/import")
async def import_xlsx(
    file: UploadFile,
    user_id: str = Depends(rate_limit("biomarkers_import", expensive=True)),
) -> dict:
    if not file.filename or not file.filename.lower().endswith(".xlsx"):
        raise HTTPException(status_code=400, detail="Only .xlsx files are accepted")

    settings = get_settings()
    data = await _read_capped(file, settings.max_upload_bytes)
    if not data.startswith(_ZIP_MAGIC):
        raise HTTPException(status_code=400, detail="File is not a valid .xlsx workbook")

    with tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False) as tmp:
        tmp.write(data)
        tmp_path = Path(tmp.name)

    try:
        _assert_safe_xlsx(tmp_path, settings.max_xlsx_uncompressed_bytes)
        sheet = parser.parse_xlsx(tmp_path)
    finally:
        tmp_path.unlink(missing_ok=True)

    if not sheet.dates or not sheet.biomarkers:
        raise HTTPException(status_code=422, detail="No usable data found in file")

    biomarker_dicts = [
        {
            "name_no": b.name_no,
            "ref_range_raw": b.ref_range_raw,
            "ref_low": b.ref_low,
            "ref_high": b.ref_high,
            "ref_type": b.ref_type,
        }
        for b in sheet.biomarkers
    ]
    biomarker_ids = repository.upsert_biomarkers(user_id, biomarker_dicts)

    panels_created = 0
    results_inserted = 0

    for col_idx, test_date in enumerate(sheet.dates):
        col_values = [
            b.values[col_idx] if col_idx < len(b.values) else None
            for b in sheet.biomarkers
        ]
        if all(v is None for v in col_values):
            continue

        panel_id = repository.create_panel(user_id, test_date, source="xlsx_import")
        panels_created += 1

        flags = [
            _in_range(
                col_values[i],
                sheet.biomarkers[i].ref_low,
                sheet.biomarkers[i].ref_high,
                sheet.biomarkers[i].ref_type,
            )
            for i in range(len(sheet.biomarkers))
        ]
        results_inserted += repository.insert_results(
            user_id, panel_id, biomarker_ids, col_values, flags
        )

    return {"panels_created": panels_created, "results_inserted": results_inserted}


@router.delete("/import/{panel_id}")
async def delete_panel(
    panel_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_panel(user_id, panel_id)
    return {"deleted": panel_id}


@router.delete("/import")
async def delete_all_imports(
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_all_panels(user_id)
    return {"deleted": "all"}


# ── Panels list ────────────────────────────────────────────────────────────────

@router.get("/panels")
async def list_panels(user_id: str = Depends(current_user_id)) -> list:
    """Return all panels (blood-draw sessions) with per-panel result counts."""
    return repository.list_panels(user_id)


# ── Manual entry ───────────────────────────────────────────────────────────────

@router.post("/results/manual", status_code=201)
async def add_manual_result(
    body: ManualResultIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    """Upsert a single manually-entered result."""
    try:
        result = repository.add_manual_result(
            user_id=user_id,
            biomarker_id=body.biomarker_id,
            tested_at=body.tested_at,
            value=body.value,
        )
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    return result


# ── Document import (PDF / image → candidate → review → apply) ──────────────────
#
# Unlike the .xlsx import, a document import is *probabilistic* and medical, so it
# never auto-writes to `results`. It produces a candidate the user reviews and
# explicitly applies (ADR-032). Phase 1 receives text the device already
# extracted (PDFKit text layer / Vision OCR); the consent-gated vision posture is
# Phase 4.

@router.post("/import/document", status_code=201)
async def import_document(
    body: LabDocumentIn,
    user_id: str = Depends(rate_limit("biomarkers_import_document", expensive=True)),
) -> dict:
    """Structure lab-report text into a reviewable candidate, staged for apply."""
    from app.biomarkers.lab_parser import parse_lab_text

    try:
        extracted = parse_lab_text(body.text)
    except ValueError as exc:
        if "not configured" in str(exc):
            raise HTTPException(status_code=503, detail="Lab parser not available") from exc
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Lab parsing failed") from exc

    if not extracted.get("panels"):
        raise HTTPException(status_code=422, detail="No usable lab data found")

    row = repository.create_lab_import(
        user_id, source_kind=body.source_kind, posture="ocr_text", extracted=extracted
    )
    return {"import_id": row["id"], "status": row["status"], **extracted}


@router.get("/imports")
async def list_pending_imports(user_id: str = Depends(current_user_id)) -> list:
    """List document imports awaiting review."""
    return repository.list_lab_imports(user_id, status="pending_review")


@router.post("/imports/{import_id}/apply")
async def apply_import(
    import_id: str,
    body: ApplyLabImportIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    """Apply the reviewed (possibly user-edited) candidate to the biomarker store."""
    staged = repository.get_lab_import(user_id, import_id)
    if staged is None:
        raise HTTPException(status_code=404, detail="Import not found")
    if staged["status"] != "pending_review":
        raise HTTPException(status_code=409, detail="Import already resolved")

    panels = [p.model_dump() for p in body.panels]
    if not any(p.get("tested_at") for p in panels):
        raise HTTPException(status_code=422, detail="Each panel needs a test date")

    try:
        summary = repository.apply_panels(user_id, panels)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    repository.set_lab_import_status(user_id, import_id, "applied")
    return summary


@router.delete("/imports/{import_id}")
async def discard_import(
    import_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    """Discard a pending candidate without writing anything."""
    staged = repository.get_lab_import(user_id, import_id)
    if staged is None:
        raise HTTPException(status_code=404, detail="Import not found")
    repository.set_lab_import_status(user_id, import_id, "discarded")
    return {"discarded": import_id}


# ── Read ───────────────────────────────────────────────────────────────────────

@router.get("")
async def list_biomarkers(user_id: str = Depends(current_user_id)) -> list:
    db = get_supabase()
    resp = (
        db.table("biomarkers")
        .select("id,name_no,name_en,unit,ref_range_raw,ref_low,ref_high,ref_type")
        .eq("user_id", user_id)
        .order("name_no")
        .execute()
    )
    return resp.data


@router.get("/results")
async def get_results(user_id: str = Depends(current_user_id)) -> list:
    """Return all biomarkers with their per-panel time-series for charting."""
    db = get_supabase()

    biomarkers_resp = (
        db.table("biomarkers")
        .select("id,name_no,name_en,unit,ref_range_raw,ref_low,ref_high,ref_type")
        .eq("user_id", user_id)
        .order("name_no")
        .execute()
    )

    results_resp = (
        db.table("results")
        .select("biomarker_id,value,in_range,panels(tested_at)")
        .eq("user_id", user_id)
        .execute()
    )

    series_by_biomarker: dict[str, list] = defaultdict(list)
    for r in results_resp.data:
        series_by_biomarker[r["biomarker_id"]].append(
            {
                "tested_at": r["panels"]["tested_at"],
                "value": r["value"],
                "in_range": r["in_range"],
            }
        )

    for series in series_by_biomarker.values():
        series.sort(key=lambda x: x["tested_at"])

    return [
        {"biomarker": b, "series": series_by_biomarker.get(b["id"], [])}
        for b in biomarkers_resp.data
    ]
