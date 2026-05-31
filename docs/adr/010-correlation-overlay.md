# ADR-010: Correlation Overlay — Diet Annotations on Biomarker Charts

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)  
**Sprint:** 3

---

## Context

The whole point of the app is to see whether what you eat moves your numbers.
Until now the biomarker chart showed the trend line and its reference range, but
there was nothing to mark *when* the user changed their regimen. Without that, a
dip in LDL is just a dip — you can't tell if it lines up with the day you went
carnivore, started a supplement, or did an extended fast.

Sprint 3 adds a **correlation overlay**: user-defined "diet events" drawn on top
of every biomarker trend chart so the user can eyeball the relationship.

A hard requirement: this must not overstate what it shows. A visual line-up is
**not** statistical correlation and certainly not causation. The feature is a
context aid, and the UI says so explicitly.

---

## Decision

- **New `diet_events` table** (migration `004_diet_events.sql`), one row per
  event, RLS self-scoped like the rest of the schema. Columns: `label`, `kind`
  (`diet` / `fast` / `supplement` / `medication` / `lifestyle` / `other`),
  `started_on`, optional `ended_on`, optional `note`. A CHECK constraint enforces
  `ended_on >= started_on`.

- **Account-wide, not per-biomarker.** A regimen change affects the whole panel,
  so one set of events annotates *every* chart rather than being attached to a
  single marker. New `GET/POST/DELETE /diet-events` endpoints
  (`app/diet_events/`), mirroring the settings router/repository pattern.

- **Rendered with Recharts primitives already in use.** `BiomarkerChart` gains an
  optional `annotations` prop. A point event becomes a dashed `ReferenceLine`; an
  event with an end date becomes a shaded `ReferenceArea` plus the start line.
  Colour is derived from `kind` using the existing theme palette
  (`var(--color-warning)` etc.).

- **Snap-to-nearest-draw.** The chart's x-axis is *categorical* (one slot per
  blood draw), so an annotation can only sit on a data point. `chartAnnotations.ts`
  projects each event onto the nearest draw by date. The detail page shows a note
  explaining the snap and the correlation-≠-causation caveat.

- **Editing lives on the biomarker detail page** via a `DietEventManager`
  component (add/list/delete). Signed-out visitors see sample annotations
  (`MOCK_DIET_EVENTS`) read-only so the feature is visible in the demo.

---

## Rationale

### Why a categorical snap instead of a true time axis?
The existing chart uses a band (categorical) x-axis with one tick per draw, which
keeps the sparse 3–4-point series readable. Switching to a continuous time scale
to place lines at arbitrary dates would change tick spacing and labelling for the
whole app for marginal benefit — with only a handful of draws, "nearest draw" is
an honest and legible approximation. The snap is disclosed in the UI.

### Why account-wide events?
A diet or supplement change is a property of the person, not of one analyte.
Storing it once and overlaying it everywhere avoids re-entering the same event on
every chart and keeps the data model truthful.

### Why reuse Recharts `ReferenceLine`/`ReferenceArea`?
They are already used for the reference band, support CSS-variable colours, and
need no new dependency.

---

## Medical / honesty considerations

- The detail page states that annotations are **snapped** and show **visual
  context only** — "a marker lining up with a change does not prove cause and
  effect."
- Nothing computes or implies a statistical correlation coefficient; we
  deliberately avoid language that would imply clinical inference.

---

## Consequences

- **Good:** Users can finally see regimen changes against their trends, across
  every marker, with one entry.
- **Good:** No new charting dependency; colours follow the theme automatically.
- **Good:** RLS isolation and the router/repository shape match existing code.
- **Trade-off:** Snap-to-nearest loses sub-draw precision. Acceptable given draw
  frequency, and disclosed.
- **Trade-off:** Duplicate-label collisions are theoretically possible if two
  draws format to the same `"Mon 'YY"` label; not observed with real cadence.

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Per-biomarker annotations | A regimen change isn't marker-specific; duplicative |
| Continuous time x-axis | Reworks every chart's ticks for sparse data; low payoff |
| Computing a correlation statistic | Misleading on 3–4 points; implies causal inference |
| Derive annotations from the diet-focus setting | That's a *view* filter, not a dated event |
