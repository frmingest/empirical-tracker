# ADR-017: Body metrics & longitudinal context — weight, waist, blood pressure

**Status:** Accepted  
**Date:** 2026-06-01  
**Author:** Faiz (solo developer)  
**Sprint:** 10

> **iOS note:** the SwiftUI realisation of this surface — the Body tab, the
> `BodyMetricChart` described in §3, and the client-side mirror of the validation
> below — ships as **iOS Sprint 8**, recorded in
> [ADR-021](021-ios-body-metrics.md). This ADR (web Sprint 10) remains the source
> of the schema, routes, and chart design.

---

## Context

The clinical review (see "Clinical-feedback roadmap" in `docs/SOLUTION.md`) found
that, for diet tracking, **weight, waist, and blood pressure respond faster — and
often matter more — than most labs**, and that blood pressure ties directly to the
app's sodium emphasis (Sprint 9). Yet the app held no body metrics at all: it
tracked blood biomarkers and food, but not the body's own headline responses to a
diet change.

This is the last sprint in the clinical-feedback roadmap. It also unblocks a
deferred Sprint 9 item: the **protein g/kg body weight** target, which needs a
stored body weight to compute.

---

## Decision

### 1. One `body_metrics` table, one row per measurement session

A new `body_metrics` table (migration `008`), RLS self-scoped like every other
user table:

| Column | Type | Notes |
|--------|------|-------|
| `measured_on` | `date` | the measurement day |
| `weight_kg` | `numeric` | kilograms |
| `waist_cm` | `numeric` | centimetres |
| `systolic` / `diastolic` | `integer` | blood pressure, mmHg |
| `note` | `text` | optional |

Every metric is **optional**, so a user can log just their weight one day and just
their blood pressure another. Two database CHECK constraints keep a row coherent:

- **`bp_pair`** — `(systolic is null) = (diastolic is null)`: a blood-pressure
  reading is meaningless with only one half, so the two are both-or-neither.
- **`at_least_one_metric`** — a row must carry at least one metric; an empty
  measurement is never stored.

The same two rules are mirrored in the Pydantic `BodyMetricIn` model (a
`model_validator`) and again client-side, so the user gets a friendly inline
message rather than a 422, while the database remains the final guarantor.

We chose **one row per measurement session** (mirroring `panels`, `food_entries`,
and `diet_events`) over a tall one-row-per-metric table. It matches the rest of
the schema, keeps a single date's readings together, and maps cleanly onto the
charts, which plot each metric's own series and simply skip the rows where that
metric is null (`connectNulls`).

### 2. Insert / delete CRUD, no update — consistent with the rest of the app

`GET/POST/DELETE /body-metrics`, served by `app/body_metrics/{router,repository}.py`,
follow the diet-events shape exactly. There is no PATCH: like the food diary and
diet events, a mistaken entry is deleted and re-added. List is ordered oldest-first
(chart-friendly); the page re-sorts newest-first for the log table.

### 3. Reuse the existing trend chart + correlation overlay, don't extend the biomarker chart

Body metrics plot on the **same timeline and the same diet-event correlation
overlay** as biomarkers, but the biomarker chart (`BiomarkerChart`) is tightly
coupled to `BiomarkerWithSeries` and lab reference ranges, neither of which fits
weight/waist/BP. Rather than overload it, we add a small generic
`BodyMetricChart` that:

- takes one or two `MetricLine`s (blood pressure is the two-line case), reading
  values straight off `BodyMetric` rows;
- reuses `buildAnnotations()` (ADR-010) for the diet overlay by handing it a
  synthetic series of the measurement dates — the same snap-to-nearest-draw logic,
  with the same honesty caveat that it shows **timing, not cause and effect**;
- draws optional **guideline** lines (blood pressure 120 / 80) as neutral, dashed,
  always-labelled "guideline" references — deliberately *not* styled like the
  Sprint 7 clinical-target line, because these are general population references,
  not personalised targets or a verdict.

Weight and waist carry **no** guideline line: a healthy weight is personal, and a
waist threshold depends on sex/ethnicity the app doesn't collect — drawing one
would imply a precision we don't have.

### 4. Wire the new table into the GDPR export/erasure contract

Per the ADR-013 maintenance contract (and the explicit reminder in ADR-016),
a **new table** must be added to `USER_TABLES` and `DELETE_ORDER` in
`api/app/account/repository.py`. `body_metrics` is now in both. It has no child
tables, so its position in the delete order is free; it sits before `meal_plans`.

---

## Consequences

- The user can now see weight, waist, and blood pressure trend together with their
  biomarkers and against their diet events — the body's fast-responding signals
  next to the slow-moving labs.
- A stored `weight_kg` is now available to power the deferred Sprint 9 **protein
  g/kg** target once that targets UI is built. This sprint captures the weight; it
  does not yet build the targets view (that remains the Sprint 9 follow-up).
- The "optional" roadmap item — overlaying body metrics *onto the biomarker
  timeline* (e.g. weight behind LDL) — is **deferred**. The data and the overlay
  machinery are now in place for it; it is a presentation follow-up, not new
  infrastructure.
- Still **decision-support, not medical advice**: the page logs and trends the
  numbers, guideline lines are general references, and the diet overlay implies no
  causation. The footer says so.

---

## Alternatives considered

- **One row per metric (tall table).** Rejected — inconsistent with the existing
  per-session tables, splits a single day's readings across rows, and buys nothing
  for charts that already skip nulls.
- **Add weight/waist/BP as columns on `panels`.** Rejected — body metrics are
  recorded far more often than blood draws and on their own cadence; coupling them
  to a lab panel would force a blood-draw row to exist for a home weigh-in.
- **Extend `BiomarkerChart` to handle metrics.** Rejected — it is built around lab
  reference ranges and a single value series; a focused `BodyMetricChart` is
  simpler than the conditionals that reuse would require, and supports the
  two-line blood-pressure case naturally.
- **Style guideline lines like the Sprint 7 clinical target (amber).** Rejected —
  that colour now means "guideline optimal bound, tighter than the lab range" for
  biomarkers; reusing it for a generic population BP reference would blur a
  distinction Sprint 7 deliberately drew. Neutral dashed + "guideline" label keeps
  them clearly unopinionated.
- **A PATCH endpoint to edit a measurement.** Rejected for now — delete-and-re-add
  matches every other log in the app; an editable table can come later if needed.
