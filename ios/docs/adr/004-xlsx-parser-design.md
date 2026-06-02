# ADR-004: XLSX Parser Design

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

The user's blood panels arrive as a single Excel file with a specific Norwegian lab format:
- Row 1: headers (biomarker name col A, reference range col B, test dates cols C+)
- Rows 2+: biomarker data rows
- Known quirks: Norwegian decimal commas (`4,3`), mixed string/numeric cells, three reference
  range formats, sparse/blank values, bilingual names in parentheses

The parser is the most fragile component in the system — format changes in future lab reports
could silently corrupt data.

---

## Decision

A single pure function `parse_xlsx(path) -> ParsedSheet` with no side effects:
- Uses openpyxl in `data_only=True` mode (reads computed cell values, not formulas)
- Normalizes Norwegian commas to dots in a single helper `_to_float_str()`
- Parses reference ranges with a regex after normalization: handles `bounded`, `lt`, `gt`, `none`
- Returns a dataclass `ParsedSheet` with typed fields — no dicts, no untyped returns
- Row filtering: skips any row where `name_no` is None or blank (handles trailing empty rows)

The parser lives in `api/app/biomarkers/parser.py` and has no database imports — it can be
tested in isolation with just a file path.

---

## Rationale

### Pure function with dataclass return
The parser has zero dependencies on the database, Supabase, or FastAPI. This means:
- Unit tests only need the xlsx file — no mocking, no fixtures
- The same parser can be used from the import endpoint, a CLI tool, or future batch processing
- Type errors are caught at parse time, not at database insert time

### Why normalize commas before regex?
openpyxl sometimes returns string cells (`'4,3'`) and sometimes numeric cells (`4.3`) for the
same column, depending on whether the cell was manually typed or computed. Normalizing commas
in the string representation handles both cases consistently.

### Why store `ref_range_raw`?
The raw string from the lab report (`"4,5 - 5,8"`) is what the doctor wrote. The user should
see this exactly as it appears in their lab report, not a reformatted version.

### Why `data_only=True` instead of reading formulas?
Lab result spreadsheets contain static values, not formulas. `data_only=True` reads the last
computed value stored in the file. Without this flag, cells that happen to look like formulas
would return `None`.

---

## Consequences

- **Good:** 19/19 unit tests pass against the real xlsx file
- **Good:** Norwegian comma handling is tested explicitly for the `S-Kalium` and `P-TSH` rows
  which have string cells
- **Trade-off:** The parser assumes column layout (A=name, B=ref, C+=dates) is fixed.
  If the lab changes the format, the parser breaks. Mitigation: the tests against the real
  file will catch this immediately
- **Future:** If the user switches labs with a different format, the parser can be extended
  with a format-detection step without changing the `ParsedSheet` interface

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| pandas read_excel | Heavy dependency; openpyxl gives more control over cell types |
| CSV export from Excel | Loses cell type info; Norwegian decimal handling is worse |
| Google Sheets API | Requires OAuth scope; lab files aren't in Google Drive |
| Hardcode column positions | Same as current — the format is fixed by the lab, not by us |
