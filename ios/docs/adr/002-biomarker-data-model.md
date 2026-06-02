# ADR-002: Biomarker Data Model

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

Norwegian blood panels are delivered as Excel files where:
- Each row is a biomarker (e.g. "P-HDL-kolesterol")
- Column B is a reference range in one of three formats: bounded `4,5 - 5,8`, one-sided `<42`, or blank
- Each subsequent column is a test date (`DD.MM.YYYY`), with the actual measured value at the intersection
- Values use Norwegian decimal commas (`4,3`) and many cells are blank (sparse data)

We need a schema that:
1. Stores the biomarker catalog once per user (not duplicated per import)
2. Groups measurements by test session (a "panel")
3. Preserves the raw reference range string alongside parsed numeric bounds
4. Enables efficient time-series queries for trend charts

---

## Decision

Three tables: `biomarkers`, `panels`, `results`.

```
biomarkers (id, user_id, name_no, name_en, unit, ref_range_raw, ref_low, ref_high, ref_type)
panels     (id, user_id, tested_at, source)
results    (id, user_id, panel_id → panels, biomarker_id → biomarkers, value, in_range)
```

The `in_range` boolean is computed at import time and stored, not recomputed on read.  
`ref_range_raw` stores the original string for display; `ref_low`, `ref_high`, `ref_type`
are the parsed numeric form for query filtering and charting.

The unique constraint on `(user_id, name_no)` in `biomarkers` means re-importing the same
file will upsert biomarker definitions without creating duplicates.

The unique constraint on `(panel_id, biomarker_id)` in `results` prevents duplicate
measurements for the same biomarker in the same test session.

---

## Rationale

### Why three tables instead of one wide table?
A single table with one row per (biomarker, date) was considered. Three tables are better because:
- Biomarker metadata (ref ranges, units) is stored once, not repeated per result
- A "panel" is a real clinical concept — a blood draw session on a date
- Deleting one import (one panel) is a single FK cascade, not a scan of all rows
- Time-series queries (`SELECT * FROM results WHERE biomarker_id = ?`) hit a narrow index

### Why store `in_range` redundantly?
Reference ranges could change (e.g. as the user updates them). Storing `in_range` at write
time preserves the clinical interpretation at the time of import. Recomputing on read would
silently change historical assessments if a range is edited.

### Why keep `ref_range_raw`?
The raw string (`"4,5 - 5,8"`, `"27- 42"`, `"<42"`) is exactly what the lab report shows.
Displaying it to the user preserves accuracy. The parsed `ref_low`/`ref_high` are for
programmatic use. Both are needed.

### Why `user_id` on every table (not just `biomarkers`)?
RLS policies use `auth.uid() = user_id`. Having it on `results` means the RLS check doesn't
require a join through `panels` → `biomarkers` — it's a direct equality. This is also a
security belt-and-suspenders: even if a FK constraint were ever wrong, a result row can't
be accessed unless its own `user_id` matches.

---

## Consequences

- **Good:** Import is idempotent — re-uploading the same file is safe
- **Good:** Cascade delete on `panels` cleans up all results atomically
- **Good:** Biomarker catalog per user means different users can have different labs
- **Trade-off:** The upsert-then-select pattern in `upsert_biomarkers()` costs 2 round-trips;
  acceptable at single-user scale
- **Future:** When adding an English name or unit to a biomarker, it's a single UPDATE;
  no migration needed on results

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Wide table (one column per date) | Schema changes every time a new test date is added |
| JSONB column for values | Loses type safety, can't index individual biomarker time-series |
| No `in_range` column — compute on read | Historical assessments change when ref ranges are edited |
| Separate schema per user | Supabase doesn't support dynamic schema creation; RLS is sufficient |
