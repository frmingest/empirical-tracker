from datetime import date
from pathlib import Path

import pytest

from app.biomarkers.parser import (
    _parse_ref_range,
    _parse_value,
    parse_xlsx,
)

XLSX = Path(r"E:\Carnivore 2026 (1).xlsx")


# ── Unit: ref-range parser ─────────────────────────────────────────────────────

def test_bounded_norwegian_comma():
    low, high, kind = _parse_ref_range("4,5 - 5,8")
    assert kind == "bounded"
    assert low == pytest.approx(4.5)
    assert high == pytest.approx(5.8)


def test_bounded_no_spaces():
    low, high, kind = _parse_ref_range("27- 42")
    assert kind == "bounded"
    assert low == pytest.approx(27.0)
    assert high == pytest.approx(42.0)


def test_bounded_integers():
    low, high, kind = _parse_ref_range("39 - 51")
    assert kind == "bounded"
    assert low == 39.0
    assert high == 51.0


def test_lt_range():
    low, high, kind = _parse_ref_range("<42")
    assert kind == "lt"
    assert high == pytest.approx(42.0)
    assert low is None


def test_gt_range():
    low, high, kind = _parse_ref_range(">0,5")
    assert kind == "gt"
    assert low == pytest.approx(0.5)
    assert high is None


def test_none_range():
    low, high, kind = _parse_ref_range(None)
    assert kind == "none"
    assert low is None
    assert high is None


def test_blank_range():
    low, high, kind = _parse_ref_range("")
    assert kind == "none"


# ── Unit: value parser ─────────────────────────────────────────────────────────

def test_value_native_float():
    assert _parse_value(5.4) == pytest.approx(5.4)


def test_value_norwegian_comma_string():
    assert _parse_value("4,3") == pytest.approx(4.3)


def test_value_none():
    assert _parse_value(None) is None


def test_value_dash():
    assert _parse_value("-") is None


def test_value_empty_string():
    assert _parse_value("") is None


# ── Integration: parse the real XLSX ──────────────────────────────────────────

@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_dates_parsed():
    sheet = parse_xlsx(XLSX)
    assert len(sheet.dates) == 4
    assert date(2026, 5, 22) in sheet.dates
    assert date(2025, 3, 13) in sheet.dates
    assert date(2024, 5, 31) in sheet.dates
    assert date(2023, 9, 15) in sheet.dates


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_biomarker_count():
    sheet = parse_xlsx(XLSX)
    assert len(sheet.biomarkers) == 34


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_all_values_are_float_or_none():
    sheet = parse_xlsx(XLSX)
    for b in sheet.biomarkers:
        for v in b.values:
            assert v is None or isinstance(v, float), f"Bad value {v!r} in {b.name_no}"


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_norwegian_comma_values_parsed():
    sheet = parse_xlsx(XLSX)
    tsh = next(b for b in sheet.biomarkers if "TSH" in b.name_no)
    non_none = [v for v in tsh.values if v is not None]
    assert len(non_none) >= 2
    # Values like "0,37" must come back as floats < 1
    assert all(v < 1.0 for v in non_none)


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_lt_range_biomarker_present():
    sheet = parse_xlsx(XLSX)
    # Row 28 in the sheet has ref_range "<42"
    lt_rows = [b for b in sheet.biomarkers if b.ref_type == "lt"]
    assert len(lt_rows) >= 1
    for b in lt_rows:
        assert b.ref_high is not None
        assert b.ref_low is None


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_bounded_range_biomarker():
    sheet = parse_xlsx(XLSX)
    hb = next(b for b in sheet.biomarkers if b.name_no == "B-Hemoglobin")
    assert hb.ref_type == "bounded"
    assert hb.ref_low == pytest.approx(13.4)
    assert hb.ref_high == pytest.approx(17.0)


@pytest.mark.skipif(not XLSX.exists(), reason="test data file not present")
def test_sparse_values_handled():
    sheet = parse_xlsx(XLSX)
    # Most biomarkers have sparse data — verify per-column length matches dates
    for b in sheet.biomarkers:
        assert len(b.values) == len(sheet.dates)
