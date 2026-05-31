from datetime import date
from unittest.mock import MagicMock, patch

import pytest

from app.biomarkers import repository


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in ("table", "upsert", "insert", "delete", "select", "eq", "order"):
        getattr(m, method).return_value = m
    return m


# ── upsert_biomarkers ──────────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_upsert_returns_ids_in_order(mock_db):
    db = _fluent()
    mock_db.return_value = db
    # upsert call returns nothing we need; select returns the IDs
    db.execute.return_value = MagicMock(
        data=[
            {"id": "id-b", "name_no": "B-Hemoglobin"},
            {"id": "id-a", "name_no": "B-Ferritin"},
        ]
    )
    biomarkers = [
        {"name_no": "B-Ferritin", "ref_range_raw": "30 - 470", "ref_low": 30.0, "ref_high": 470.0, "ref_type": "bounded"},
        {"name_no": "B-Hemoglobin", "ref_range_raw": "13,4 - 17,0", "ref_low": 13.4, "ref_high": 17.0, "ref_type": "bounded"},
    ]
    result = repository.upsert_biomarkers("user-1", biomarkers)
    assert result == ["id-a", "id-b"]


@patch("app.biomarkers.repository.get_supabase")
def test_upsert_calls_table_biomarkers(mock_db):
    db = _fluent(execute_data=[{"id": "x", "name_no": "B-Hemoglobin"}])
    mock_db.return_value = db
    repository.upsert_biomarkers(
        "user-1",
        [{"name_no": "B-Hemoglobin", "ref_range_raw": "", "ref_low": None, "ref_high": None, "ref_type": "none"}],
    )
    db.table.assert_any_call("biomarkers")


# ── create_panel ───────────────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_create_panel_returns_id(mock_db):
    db = _fluent(execute_data=[{"id": "panel-uuid-1"}])
    mock_db.return_value = db
    result = repository.create_panel("user-1", date(2026, 5, 22))
    assert result == "panel-uuid-1"
    db.table.assert_called_with("panels")


# ── insert_results ─────────────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_insert_results_skips_none_values(mock_db):
    db = _fluent(execute_data=[{"id": "r1"}, {"id": "r2"}])
    mock_db.return_value = db
    count = repository.insert_results(
        "user-1", "panel-1",
        ["bio-a", "bio-b", "bio-c"],
        [1.5, None, 3.2],
        [True, None, False],
    )
    assert count == 2


@patch("app.biomarkers.repository.get_supabase")
def test_insert_results_all_none_returns_zero(mock_db):
    db = _fluent()
    mock_db.return_value = db
    count = repository.insert_results(
        "user-1", "panel-1",
        ["bio-a"],
        [None],
        [None],
    )
    assert count == 0
    db.insert.assert_not_called()


# ── delete_panel ───────────────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_delete_panel_calls_delete(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_panel("user-1", "panel-id-1")
    db.table.assert_called_with("panels")
    db.delete.assert_called_once()


@patch("app.biomarkers.repository.get_supabase")
def test_delete_panel_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_panel("user-1", "panel-id-1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "user-1") in eq_calls


# ── delete_all_panels ──────────────────────────────────────────────────────────

@patch("app.biomarkers.repository.get_supabase")
def test_delete_all_panels(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_all_panels("user-1")
    db.table.assert_called_with("panels")
    db.delete.assert_called_once()
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "user-1") in eq_calls
