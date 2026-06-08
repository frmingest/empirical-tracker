"""Lab document import — parser, repository apply, and endpoints (ADR-032)."""

from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app import rate_limit as rl
from app.auth import current_user_id
from app.biomarkers import lab_parser, repository
from app.main import app

client = TestClient(app)


def teardown_function() -> None:
    rl._limiter.reset()
    app.dependency_overrides.clear()


def _fluent(execute_data=None):
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "upsert", "insert", "update", "delete", "select", "eq", "order"):
        getattr(m, method).return_value = m
    return m


def _claude_returning(text: str):
    """A fake anthropic module whose Anthropic().messages.create returns `text`."""
    fake = MagicMock()
    msg = MagicMock()
    msg.content = [MagicMock(text=text)]
    fake.Anthropic.return_value.messages.create.return_value = msg
    return fake


# ── parser ──────────────────────────────────────────────────────────────────────

@patch("app.biomarkers.lab_parser.get_settings")
def test_parse_lab_text_cleans_panels(mock_settings):
    mock_settings.return_value = MagicMock(anthropic_api_key="k")
    payload = """{
      "panels": [
        {"tested_at": "2026-01-02", "results": [
          {"name_no": "B-Hemoglobin", "value": "14,5", "unit": "g/dL",
           "ref_range_raw": "13.4 - 17.0"},
          {"name_no": "  ", "value": 1},
          {"name_no": "S-CRP", "value": null, "value_text": "Negativ"}
        ]}
      ]
    }"""
    with patch.object(lab_parser, "anthropic", _claude_returning(payload)):
        out = lab_parser.parse_lab_text("raw report text")

    assert len(out["panels"]) == 1
    panel = out["panels"][0]
    assert panel["tested_at"] == "2026-01-02"
    # The nameless row is dropped; Norwegian comma is normalised; null stays null.
    names = [r["name_no"] for r in panel["results"]]
    assert names == ["B-Hemoglobin", "S-CRP"]
    assert panel["results"][0]["value"] == 14.5
    assert panel["results"][1]["value"] is None
    assert panel["results"][1]["value_text"] == "Negativ"


@patch("app.biomarkers.lab_parser.get_settings")
def test_parse_lab_text_strips_code_fences(mock_settings):
    mock_settings.return_value = MagicMock(anthropic_api_key="k")
    fenced = '```json\n{"panels": []}\n```'
    with patch.object(lab_parser, "anthropic", _claude_returning(fenced)):
        out = lab_parser.parse_lab_text("x")
    assert out == {"panels": []}


@patch("app.biomarkers.lab_parser.get_settings")
def test_parse_lab_text_requires_key(mock_settings):
    mock_settings.return_value = MagicMock(anthropic_api_key="")
    with pytest.raises(ValueError, match="not configured"):
        lab_parser.parse_lab_text("x")


@patch("app.biomarkers.lab_parser.get_settings")
def test_parse_lab_text_rejects_non_json(mock_settings):
    mock_settings.return_value = MagicMock(anthropic_api_key="k")
    with patch.object(lab_parser, "anthropic", _claude_returning("not json")):
        with pytest.raises(ValueError):
            lab_parser.parse_lab_text("x")


# ── repository.apply_panels ──────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_apply_panels_upserts_and_counts(mock_db):
    db = _fluent()
    mock_db.return_value = db
    # biomarkers select-back, panel upsert, results upsert all read .data
    db.execute.side_effect = [
        MagicMock(data=[{"id": "u"}]),  # biomarkers upsert
        MagicMock(data=[{"id": "bio-1", "name_no": "B-Hemoglobin",
                         "ref_low": 13.4, "ref_high": 17.0, "ref_type": "bounded"}]),  # select ids
        MagicMock(data=[{"id": "panel-1"}]),  # panel upsert
        MagicMock(data=[{"id": "res-1"}]),  # results upsert
    ]
    panels = [
        {"tested_at": "2026-01-02", "results": [
            {"name_no": "B-Hemoglobin", "value": 14.5, "unit": "g/dL",
             "ref_range_raw": "13.4 - 17.0"},
        ]}
    ]
    summary = repository.apply_panels("u1", panels)
    assert summary == {"panels_applied": 1, "results_inserted": 1}
    db.table.assert_any_call("biomarkers")
    db.table.assert_any_call("panels")
    db.table.assert_any_call("results")


@patch("app.biomarkers.repository.get_supabase")
def test_apply_panels_skips_dateless_and_valueless(mock_db):
    db = _fluent()
    mock_db.return_value = db
    panels = [
        {"tested_at": None, "results": [{"name_no": "X", "value": 1}]},   # no date
        {"tested_at": "2026-01-02", "results": [{"name_no": "Y", "value": None}]},  # no numeric
    ]
    summary = repository.apply_panels("u1", panels)
    assert summary == {"panels_applied": 0, "results_inserted": 0}


# ── endpoints ────────────────────────────────────────────────────────────────────

@patch("app.biomarkers.lab_parser.parse_lab_text")
def test_import_document_stages_candidate(mock_parse):
    mock_parse.return_value = {"panels": [{"tested_at": "2026-01-02", "results": []}]}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "create_lab_import",
                      return_value={"id": "imp-1", "status": "pending_review"}):
        res = client.post("/biomarkers/import/document", json={"text": "some report text"})
    assert res.status_code == 201
    body = res.json()
    assert body["import_id"] == "imp-1"
    assert body["status"] == "pending_review"
    assert body["panels"][0]["tested_at"] == "2026-01-02"


def test_import_document_rejects_empty_text():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post("/biomarkers/import/document", json={"text": "   "})
    assert res.status_code == 422


@patch("app.biomarkers.router.get_settings")
def test_import_document_caps_text(mock_settings):
    mock_settings.return_value = MagicMock(max_ocr_chars=10)
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post("/biomarkers/import/document", json={"text": "x" * 50})
    assert res.status_code == 422


@patch("app.biomarkers.lab_parser.parse_lab_text")
def test_import_document_no_panels_is_422(mock_parse):
    mock_parse.return_value = {"panels": []}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    res = client.post("/biomarkers/import/document", json={"text": "irrelevant text"})
    assert res.status_code == 422


def test_apply_import_writes_and_marks_applied():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "get_lab_import",
                      return_value={"id": "imp-1", "status": "pending_review"}), \
         patch.object(repository, "apply_panels",
                      return_value={"panels_applied": 1, "results_inserted": 3}) as apply_mock, \
         patch.object(repository, "set_lab_import_status") as status_mock:
        res = client.post(
            "/biomarkers/imports/imp-1/apply",
            json={"panels": [{"tested_at": "2026-01-02",
                              "results": [{"name_no": "B-Hemoglobin", "value": 14.5}]}]},
        )
    assert res.status_code == 200
    assert res.json() == {"panels_applied": 1, "results_inserted": 3}
    apply_mock.assert_called_once()
    status_mock.assert_called_once_with("u1", "imp-1", "applied")


def test_apply_import_requires_a_date():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "get_lab_import",
                      return_value={"id": "imp-1", "status": "pending_review"}):
        res = client.post(
            "/biomarkers/imports/imp-1/apply",
            json={"panels": [{"tested_at": None,
                              "results": [{"name_no": "X", "value": 1}]}]},
        )
    assert res.status_code == 422


def test_apply_import_404_when_missing():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "get_lab_import", return_value=None):
        res = client.post(
            "/biomarkers/imports/nope/apply",
            json={"panels": [{"tested_at": "2026-01-02", "results": []}]},
        )
    assert res.status_code == 404


def test_apply_import_409_when_already_resolved():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "get_lab_import",
                      return_value={"id": "imp-1", "status": "applied"}):
        res = client.post(
            "/biomarkers/imports/imp-1/apply",
            json={"panels": [{"tested_at": "2026-01-02", "results": []}]},
        )
    assert res.status_code == 409


def test_discard_import_marks_discarded():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    with patch.object(repository, "get_lab_import",
                      return_value={"id": "imp-1", "status": "pending_review"}), \
         patch.object(repository, "set_lab_import_status") as status_mock:
        res = client.delete("/biomarkers/imports/imp-1")
    assert res.status_code == 200
    assert res.json() == {"discarded": "imp-1"}
    status_mock.assert_called_once_with("u1", "imp-1", "discarded")
