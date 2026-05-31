from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path

import openpyxl


@dataclass
class BiomarkerRow:
    name_no: str
    ref_range_raw: str
    ref_low: float | None
    ref_high: float | None
    ref_type: str  # 'bounded' | 'lt' | 'gt' | 'none'
    values: list[float | None]


@dataclass
class ParsedSheet:
    dates: list[date]
    biomarkers: list[BiomarkerRow]


def _to_float_str(s: str) -> str:
    """Normalize Norwegian decimal comma to dot."""
    return s.replace(",", ".")


def _parse_ref_range(raw: object) -> tuple[float | None, float | None, str]:
    if raw is None:
        return None, None, "none"
    s = str(raw).strip()
    if not s:
        return None, None, "none"

    if s.startswith("<"):
        try:
            return None, float(_to_float_str(s[1:].strip())), "lt"
        except ValueError:
            return None, None, "none"

    if s.startswith(">"):
        try:
            return float(_to_float_str(s[1:].strip())), None, "gt"
        except ValueError:
            return None, None, "none"

    # Bounded: "4,5 - 5,8"  "27- 42"  "83 -136"  "0,35 - 3,6"
    normalized = _to_float_str(s)
    m = re.match(r"^([\d.]+)\s*-\s*([\d.]+)$", normalized)
    if m:
        try:
            return float(m.group(1)), float(m.group(2)), "bounded"
        except ValueError:
            pass

    return None, None, "none"


def _parse_value(v: object) -> float | None:
    if v is None:
        return None
    if isinstance(v, int | float):
        return float(v)
    s = str(v).strip()
    if not s or s == "-":
        return None
    try:
        return float(_to_float_str(s))
    except ValueError:
        return None


def parse_xlsx(path: str | Path) -> ParsedSheet:
    wb = openpyxl.load_workbook(path, data_only=True)
    ws = wb.active

    rows = list(ws.iter_rows(values_only=True))
    wb.close()

    if not rows:
        return ParsedSheet(dates=[], biomarkers=[])

    # Row 0 (spreadsheet row 1): "Analyse" | "Referanseområde" | date … date
    header = rows[0]
    dates: list[date] = []
    for cell in header[2:]:
        if cell is None:
            continue
        try:
            dates.append(datetime.strptime(str(cell).strip(), "%d.%m.%Y").date())
        except ValueError:
            pass

    biomarkers: list[BiomarkerRow] = []
    for row in rows[1:]:
        name_no = row[0]
        if name_no is None or not str(name_no).strip():
            continue

        ref_raw = row[1]
        ref_low, ref_high, ref_type = _parse_ref_range(ref_raw)

        values: list[float | None] = [
            _parse_value(row[2 + i]) if (2 + i) < len(row) else None
            for i in range(len(dates))
        ]

        biomarkers.append(
            BiomarkerRow(
                name_no=str(name_no).strip(),
                ref_range_raw=str(ref_raw).strip() if ref_raw is not None else "",
                ref_low=ref_low,
                ref_high=ref_high,
                ref_type=ref_type,
                values=values,
            )
        )

    return ParsedSheet(dates=dates, biomarkers=biomarkers)
