# ADR-021: iOS body metrics — weight, waist & blood-pressure UI

**Status:** Accepted
**Date:** 2026-06-02
**Author:** iOS team
**Sprint:** 8 (iOS)

---

## Context

The body-metrics surface — the `body_metrics` table, the `GET/POST/DELETE
/body-metrics` routes, the both-or-neither / at-least-one validation, the
`source` provenance column, and the GDPR export/erasure wiring — was designed and
shipped on the backend in **ADR-017** (its web Sprint 10). That ADR also specified,
forward-looking, the *presentation* approach: a small generic `BodyMetricChart`
reusing the diet-event correlation overlay, with neutral guideline lines.

Until this sprint the iOS app had only a **stub `BodyMetricsRepository`** and a
**placeholder Body tab**. iOS Sprint 8 (`IOS_MIGRATION_PLAN.md` §3) realises the
full Body tab in SwiftUI: a log form, three trend charts sharing the diet-event
overlay, a history table, and the honesty footer. Like the food diary (ADR-019)
and meal plans (ADR-020) this is a **pure presentation sprint** — it ships no
backend changes, consistent with the migration plan's "reuse the backend"
principle (§1.1).

> Numbering note: ADR-017 carries the **web** sprint number (its Sprint 10) because
> it was authored against the web app. This ADR uses the **iOS** sprint numbering
> from the migration plan, where body metrics are Sprint 8. It realises ADR-017's
> §3 chart design in Swift Charts; it does not supersede it.

---

## Decision

### 1. `BodyMetricChart` — one generic chart, realised in Swift Charts

Per ADR-017 §3 we add a focused `BodyMetricChart` rather than overload the
reference-range-bound `BiomarkerChart`. It takes one or two `Series` (blood
pressure is the two-line case), reads values straight off `BodyMetric` rows, and:

- reuses **`DietEventOverlayContent`** (the Sprint 5 / ADR-010 overlay) for the
  diet-event correlation, handed the metric measurement window so the same
  snap-to-nearest logic and the same "timing, not cause" caveat apply;
- draws optional **guideline** lines (blood pressure 120 / 80) as neutral, dashed,
  always-labelled "guideline" references — deliberately **not** the amber clinical-
  target styling from Sprint 7, because these are general population references, not
  personalised targets;
- carries **no** guideline on weight or waist (a healthy weight is personal; a waist
  threshold depends on sex/ethnicity the app doesn't collect).

Each metric plots its **own series and skips the null rows** (`compactMap` off the
`BodyMetric` array), so a day with only a weight reading still charts cleanly — the
SwiftUI equivalent of the web's `connectNulls`. A chart card is shown only when its
metric has at least one point, so a weight-only user sees one chart, not three.

### 2. Client-side validation mirrors the backend (and the database)

`BodyMetricsViewModel` mirrors the two ADR-017 rules client-side so the user gets a
friendly inline message instead of a 422, while the database `CHECK`s remain the
final guarantor:

- **bp_pair** — systolic and diastolic are both-or-neither;
- **at_least_one_metric** — the Add button stays disabled until weight, waist, or
  blood pressure is entered.

It also range-checks before submit (systolic 40–300, diastolic 20–200, weight/waist
> 0) and parses **Norwegian decimal commas** (reusing the diary's parsing posture,
ADR-016). The neutral "enter at least one" guidance is a footer hint, not a red
error; red surfaces only for an actual conflict (a half-entered BP, an out-of-range
or unparseable value).

### 3. Insert / delete, no edit — consistent with every other log

The screen follows the diet-events / food-diary shape exactly: a `+` opens
`LogBodyMetricSheet`; history is listed **newest-first** with swipe-to-delete; a
mistaken entry is deleted and re-added (no PATCH), matching ADR-017 §2. Charts read
the repository's **oldest-first** ordering directly.

### 4. `note` added to the Swift DTO; provenance surfaced as a forward-compat badge

The stub `BodyMetric` omitted the `note` column that ADR-017 defines; this sprint
adds `note` to both `BodyMetric` and `BodyMetricPayload` so the optional note round-
trips. The existing `source` (`manual | healthkit | withings`) is surfaced as a
small capsule badge that appears **only for non-manual rows** — manual entries are
unadorned. This is deliberate groundwork: Sprints 9–10 (HealthKit / Withings) will
write synced rows, and the UI already labels them.

### 5. Honesty footer

A single combined footer states the screen's three caveats: the overlay shows
visual timing only (not cause), the guideline lines are general references (not
personal targets), and this is decision-support, not medical advice — satisfying
ADR-017's "the footer says so."

---

## Consequences

- **Good:** The Body tab reaches web parity — log + three overlaid charts — and the
  body's fast-responding signals now sit alongside the slow-moving labs and the same
  diet events, closing the last clinical-feedback roadmap surface on iOS.
- **Good:** No backend work; `/body-metrics`, the schema, and GDPR export/erasure
  are unchanged.
- **Good:** Provenance plumbing and the synced-row badge are in place, de-risking
  Sprints 9–10; a stored `weight_kg` is now also available to power the deferred
  **protein g/kg** target.
- **Trade-off:** `BodyMetricChart` is a second chart type beside `BiomarkerChart`
  rather than one unified chart — accepted in ADR-017 §3, restated here: a focused
  chart is simpler than the reference-range conditionals reuse would demand, and it
  takes the two-line BP case naturally.
- **Carried from ADR-017:** no edit (delete-and-re-add); guideline lines stay
  unopinionated; overlaying body metrics *onto the biomarker timeline* remains a
  deferred presentation follow-up — the data and overlay machinery are now in place
  for it.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Extend `BiomarkerChart` to plot metrics | Built around lab reference ranges and a single series; a focused chart is simpler than the conditionals and supports the two-line BP case naturally (ADR-017 §3). |
| Always render all three charts | Noise for a single-metric user; showing a chart only when its metric has data matches the per-series null-skipping. |
| Validate only server-side | A 422 is a poor first-run experience; mirroring the rules client-side keeps the database as the guarantor while giving an inline message. |
| Add a PATCH/edit flow | Delete-and-re-add matches every other log in the app (ADR-017 §2); an editable table can come later if asked for. |
| Style BP guideline like the Sprint 7 target line | That amber now means "tighter-than-range optimal bound" for biomarkers; reusing it for a generic population BP reference would blur a distinction Sprint 7 drew deliberately. |
