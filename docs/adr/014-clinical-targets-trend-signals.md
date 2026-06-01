# ADR-014: Clinical Targets vs. Lab Reference + Within-Range Trend Signals

**Status:** Accepted  
**Date:** 2026-06-01  
**Author:** Faiz (solo developer)  
**Sprint:** 7

---

## Context

A clinical review of the app found one central problem: the app treats the lab
**reference range** as if it meant **healthy**. The reference range is a
population interval — roughly where ~95% of a reference population falls — not a
statement that a value is good for *you*. Two failure modes follow:

1. **"In range" hides "above target."** LDL 4.1 mmol/L is flagged green because
   the lab's upper reference is 4.7, even though guideline LDL targets for an
   at-risk person are far lower. The binary flag actively conceals a value the
   user might want to act on.
2. **"In range" hides the trend.** ALT doubling from 25 → 55 U/L stays green
   because it's still under 70. The single most informative thing — that it
   *doubled* — is invisible unless the user studies the chart.

Sprint 7 makes the app *say* what the chart already shows, without overstating
it. Two additions: a **clinical-target layer** distinct from the lab range, and
**within-range trend signals**.

---

## Decision

### 1. Clinical targets live as a static, client-side reference map

`web/src/lib/clinicalTargets.ts` seeds guideline **optimal upper bounds** for the
markers where the gap bites first: **LDL, non-HDL, total cholesterol, and
HbA1c**. Each entry carries the bound, unit, a one-line rationale, and a source
attribution.

These are **general guideline values, not per-user PII** — they depend only on
the marker's identity. So, exactly like the diet-focus lists in
`dietProfiles.ts`, they live as a static map keyed by `markerKey()`, with **no
database table and no migration**. This keeps the feature dependency-free and
keeps health-data tables strictly per-user.

A value is flagged when it sits **at or above** the optimal upper bound while
still inside the lab reference. We seed deliberately **conservative, low-risk**
bounds (e.g. LDL ≤ 3.0, not the aggressive secondary-prevention 1.4–1.8), since
the app cannot know an individual's cardiovascular risk.

### 2. Trend signals are computed from the existing series

`web/src/lib/markerSignals.ts` derives signals purely from the time-ordered
results already returned by `/biomarkers/results` — again **no backend change**:

- **Large step** (`watch`): the last draw moved ≥ 50% vs the previous one
  (captures any doubling/halving) — "Rising fast" / "Falling fast".
- **Notable step** (`info`): ≥ 25% move — "Trending up" / "Trending down".
- **Near a bound** (`info`): an in-range value within 10% of either end of a
  bounded reference range — "Near upper/lower limit".

`assessMarker()` folds the in/out-of-range flag, the target check, and the trend
signals into one `ConcernLevel`: `out_of_range` → `attention` → `ok` →
`unknown`. **An in-range value with a flagged target or a `watch` trend resolves
to `attention`, never plain `ok`** — so the green flag can no longer override a
flagged trend. `levelColor()` maps the level onto the existing theme palette
(`--color-out-range` / `--color-warning` / `--color-in-range` / `--text-muted`).

### 3. UI surfacing

- **`StatusBadge`** gains an `attention` state: in range but flagged → amber
  "Watch" (an out-of-range value still wins).
- **`BiomarkerCard`** colours its dot, value, and sparkline by concern level and
  shows the top signal's label (e.g. "Above target", "Rising fast").
- **`BiomarkerChart`** draws the clinical target as a distinct amber dashed
  `ReferenceLine` (`Target ≤ x`), visually separate from the green lab-reference
  band, with its own legend entry.
- **`MarkerSignals`** (detail page) lists every signal with severity, plus the
  target's rationale and source, under an explicit decision-support caveat.
- **Dashboard** adds a count of in-range-but-flagged markers ("N in range but
  worth a look").

---

## Rationale

### Why static client constants instead of a `marker_targets` table?
Targets are universal guideline values, not user data — putting them in the DB
would add a migration, a join, and an API surface for something that never
varies per user. The existing `dietProfiles.ts` already establishes the pattern
of keying clinical reference data off `markerKey()`. If a future
**server-rendered doctor report** (Sprint 6 follow-up) needs the same numbers,
the constants can be mirrored or promoted to a shared seed then — we defer that
until there's a second consumer rather than over-build now.

### Why cap within-range severity at "watch"?
With only 3–4 draws, calling anything an "alert" on the basis of a trend would
overstate certainty. `watch` says "look at this," which is exactly as strong as
the data supports. Only an actual out-of-range value is rendered as the strong
(rose) state.

### Why thresholds of 50% / 25% / 10%?
They are legible, defensible heuristics, not statistics. 50% guarantees any
doubling/halving trips the loud signal; 25% catches the meaningful-but-smaller
move; "within 10% of a bound" is a simple positional proximity. We avoid slopes,
regressions, or p-values precisely because the draw count can't support them.

---

## Medical / honesty considerations

- Targets are labelled **general guideline values, not personalised** to the
  user's individual risk; `MarkerSignals` states this and cites a source.
- Signals are **descriptive, not diagnostic** — they describe movement and
  proximity, and explicitly disclaim diagnosis, causation, and statistical
  significance.
- The conservative low-risk targets avoid alarming users who may not be at the
  elevated risk that tighter targets assume.

---

## Consequences

- **Good:** The app stops conflating "in range" with "healthy"; the LDL-4.1 and
  ALT-25→55 cases now read as "worth a look" instead of green.
- **Good:** Zero backend/schema change, no new dependency; all logic is pure and
  reuses the existing series and theme palette.
- **Good:** `assessMarker()` is a single source of truth for marker status,
  reused by card, badge, detail page, and dashboard count.
- **Trade-off:** Seeded targets cover only lipids + HbA1c; triglycerides arrive
  with Sprint 8, and other markers have no target until seeded.
- **Trade-off:** Heuristic thresholds can occasionally flag a clinically
  unremarkable wobble; acceptable for a "look at this" prompt, and disclosed.

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| `marker_targets` DB table + API | Migration/join/endpoint for data that never varies per user; no second consumer yet |
| `target_low`/`target_high` columns on `biomarkers` | Per-user rows would duplicate universal constants and risk drift between users |
| Aggressive secondary-prevention targets | App can't know individual risk; would over-alarm low-risk users |
| Regression / slope / correlation on the series | 3–4 draws can't support statistical inference; implies false certainty |
| Reusing the in/out-of-range red for "above target" | Erases the distinction the whole sprint exists to draw |
