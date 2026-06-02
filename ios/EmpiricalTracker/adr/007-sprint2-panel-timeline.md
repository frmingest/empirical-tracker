# ADR-007: Sprint 2 — Panel Timeline and Manual Entry

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

Sprint 1 delivered the biomarker import pipeline and a dashboard showing all biomarkers with
sparklines. The missing views for Sprint 2 are:

1. A way to see results organised by *test date* (panel), not by *biomarker*
2. A way to add a single result without re-importing a full Excel file
3. Auth-wired biomarker detail pages (currently showing mock data)

---

## Decision

- **Panel timeline page** (`/panels`): Derives panels from the existing `BiomarkerWithSeries[]`
  data already fetched for the dashboard — no new API endpoint needed. Each panel card shows
  the date, total biomarkers tested, in-range / out-of-range counts, and a list of out-of-range
  biomarker names.

- **Manual entry** (`POST /biomarkers/results/manual`): A new backend endpoint that accepts
  `{ biomarker_id, tested_at, value }`, computes `in_range` using the stored reference range,
  and upserts into the `results` table. Frontend uses a modal form.

- **Auth wiring on detail page**: Convert the `biomarkers/[id]` page to a client component
  using the same auth pattern as the dashboard.

---

## Rationale

### Why derive panels client-side instead of a new API endpoint?
The `GET /biomarkers/results` endpoint already returns all the data needed to reconstruct
panels. Adding a `GET /biomarkers/panels` endpoint would duplicate data and add a round trip.
Panel derivation is O(n) over results already in memory.

### Why a manual entry endpoint instead of re-uploading?
Re-uploading an Excel file to correct a single value is cumbersome. The manual entry path
also handles cases where the user gets a result verbally (e.g., a nurse reads a value) and
wants to record it immediately.

---

## Consequences

- **Good:** No new API fetch for the panel timeline — fast and cache-friendly
- **Good:** Manual entry is backend-validated (`in_range` computed server-side using the
  authoritative reference range, not trusting client-side logic)
- **Trade-off:** The panel timeline is only as fresh as the last `getBiomarkerResults` call —
  it won't auto-update when a manual entry is added. Mitigation: refresh `getBiomarkerResults`
  after a successful manual entry (same pattern as after XLSX import)
