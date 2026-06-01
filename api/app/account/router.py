from __future__ import annotations

import csv
import io
import json
import zipfile
from datetime import UTC, datetime

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response

from app.account import repository
from app.auth import current_user_id

router = APIRouter(prefix="/account", tags=["account"])


def _json_bytes(export: dict) -> bytes:
    """Serialise the whole export as a single pretty-printed JSON document."""
    return json.dumps(export, indent=2, ensure_ascii=False, default=str).encode("utf-8")


def _field_order(rows: list[dict]) -> list[str]:
    """Stable union of column names across rows (first-seen order)."""
    fields: list[str] = []
    for row in rows:
        for key in row:
            if key not in fields:
                fields.append(key)
    return fields


def _csv_zip_bytes(export: dict) -> bytes:
    """Serialise the export as a zip with one CSV per non-empty table.

    Empty tables are omitted from the archive but stay documented in
    ``export_meta.json`` (which carries row_counts), so the export is complete.
    """
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr(
            "export_meta.json",
            json.dumps(export["export_meta"], indent=2, ensure_ascii=False, default=str),
        )
        for table, rows in export["data"].items():
            if not rows:
                continue
            fields = _field_order(rows)
            sio = io.StringIO()
            writer = csv.DictWriter(sio, fieldnames=fields)
            writer.writeheader()
            for row in rows:
                writer.writerow({k: row.get(k) for k in fields})
            zf.writestr(f"{table}.csv", sio.getvalue())
    return buf.getvalue()


@router.get("/export")
async def export_account(
    format: str = Query(default="json", pattern="^(json|csv)$"),  # noqa: B008
    user_id: str = Depends(current_user_id),  # noqa: B008
) -> Response:
    """Download all of the authenticated user's data (GDPR data portability)."""
    export = repository.build_export(user_id)
    stamp = datetime.now(UTC).strftime("%Y%m%d")
    if format == "csv":
        return Response(
            content=_csv_zip_bytes(export),
            media_type="application/zip",
            headers={
                "Content-Disposition": f'attachment; filename="empirical-export-{stamp}.zip"'
            },
        )
    return Response(
        content=_json_bytes(export),
        media_type="application/json",
        headers={
            "Content-Disposition": f'attachment; filename="empirical-export-{stamp}.json"'
        },
    )


@router.delete("")
async def delete_account(user_id: str = Depends(current_user_id)) -> dict:  # noqa: B008
    """Permanently erase the user's data and account (GDPR right to erasure)."""
    return repository.delete_user_data(user_id)
