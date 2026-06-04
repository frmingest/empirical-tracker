"""Upload, OCR, and CORS hardening tests (ADR-026 F3/F4/F9)."""

import io
from unittest.mock import MagicMock, patch

import openpyxl
from fastapi.testclient import TestClient

from app import rate_limit as rl
from app.auth import current_user_id
from app.main import app

client = TestClient(app)


def teardown_function() -> None:
    rl._limiter.reset()
    app.dependency_overrides.clear()


def _valid_xlsx_bytes() -> bytes:
    wb = openpyxl.Workbook()
    buf = io.BytesIO()
    wb.save(buf)
    return buf.getvalue()


# ── F3: upload hardening ────────────────────────────────────────────────────────

def test_import_rejects_non_xlsx_extension():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post(
        "/biomarkers/import",
        files={"file": ("data.csv", b"PK\x03\x04stuff", "text/csv")},
    )
    assert res.status_code == 400


def test_import_rejects_wrong_magic_bytes():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post(
        "/biomarkers/import",
        files={"file": ("data.xlsx", b"not a zip at all", "application/octet-stream")},
    )
    assert res.status_code == 400
    assert "valid .xlsx" in res.json()["detail"]


def test_import_rejects_zip_magic_but_corrupt():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    payload = b"PK\x03\x04corrupt-not-real-zip"
    res = client.post(
        "/biomarkers/import",
        files={"file": ("data.xlsx", payload, "application/octet-stream")},
    )
    assert res.status_code == 400


@patch("app.biomarkers.router.get_settings")
def test_import_rejects_oversized_upload(mock_settings):
    mock_settings.return_value = MagicMock(
        max_upload_bytes=1024, max_xlsx_uncompressed_bytes=10_000_000
    )
    app.dependency_overrides[current_user_id] = lambda: "u1"
    big = _valid_xlsx_bytes() + b"\x00" * 4096
    res = client.post(
        "/biomarkers/import",
        files={"file": ("data.xlsx", big, "application/octet-stream")},
    )
    assert res.status_code == 413


def test_import_accepts_valid_xlsx_through_guards():
    # A well-formed (but empty) workbook passes the magic/zip-bomb guards and is
    # rejected only later for having no usable data — proving the guards let
    # legitimate files through.
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post(
        "/biomarkers/import",
        files={"file": ("data.xlsx", _valid_xlsx_bytes(), "application/octet-stream")},
    )
    assert res.status_code == 422  # "No usable data found in file"


# ── F4: OCR text cap ────────────────────────────────────────────────────────────

@patch("app.food_diary.router.get_settings")
def test_parse_label_rejects_oversized_ocr_text(mock_settings):
    mock_settings.return_value = MagicMock(max_ocr_chars=50)
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post("/food-diary/parse-label", json={"ocr_text": "x" * 100})
    assert res.status_code == 422


# ── F9: CORS no longer credentialed ─────────────────────────────────────────────

def test_cors_is_not_credentialed():
    res = client.get("/health", headers={"Origin": "http://localhost:3000"})
    assert res.headers.get("access-control-allow-origin") == "http://localhost:3000"
    # Credentialed CORS is dropped: the header must be absent (ADR-026 F9).
    assert "access-control-allow-credentials" not in res.headers
