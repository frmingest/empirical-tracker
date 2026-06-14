# ADR-030: Body map as the default dashboard view

**Status:** Accepted  
**Date:** 2026-06-05  
**Author:** Faiz (solo developer)  
**Sprint:** 12 (dashboard UX — builds on ADR-021 body metrics, ADR-014 clinical signals)

---

## Context

The original Home tab opened to a **flat categorical grid** of biomarker sparklines — a
compact but text-dense list that gives no spatial or physiological orientation. A user
returning from the lab or checking in after a diet change has to scan the whole list to
find what moved; there is no at-a-glance summary of body state.

Two orthogonal surfaces existed but lived in separate tabs:

- **Body metrics** (ADR-021) — weight, waist, BP trends.
- **Biomarker categories** (ADR-014) — clinical status per marker.

Neither gave a unified "how is my body doing right now?" answer. The body map concept
addresses this by mapping biomarker category status onto an anatomical silhouette,
combining the spatial framing with the existing clinical-signal colours — and placing
it where the user looks first.

### Requirements driving this decision

1. **Glanceable headline state** — show the user which body regions have flagged
   markers without requiring them to scan a list.
2. **Body-metric context on the same screen** — weight, waist, BMI, and BP alongside
   the biomarker status, so the "body picture" is complete.
3. **Drill-down without navigation friction** — tapping a region should surface its
   markers and allow drill-through to the full detail view without leaving Home.
4. **Preserve the grid** — power users who prefer the list should still get it; the
   mode switch must be one tap.

---

## Decision

**Replace the default Home tab view with a body-map canvas; keep the biomarker grid
one tap away via a toolbar toggle.**

### 1. `DashboardViewMode` enum and default

```swift
enum DashboardViewMode: String, CaseIterable {
    case grid    // existing biomarker grid
    case bodyMap // new default
}
```

`DashboardView` initialises `dashboardMode` to `.bodyMap`. The toolbar renders a
segmented picker (`square.grid.2x2` / `figure.stand`) so switching is a single tap
and the choice persists for the session (not persisted to `UserDefaults` — resets to
body map on cold launch, which keeps the glanceable view as the default intent).

### 2. `DashboardBodyMapView` — anatomy canvas + overlay panels

The body map canvas (`BodyMapCanvas`, `HumanBodySilhouette`) renders a human
silhouette SVG-equivalent with a pin per `BodyRegion`. Each pin is coloured by
`BodyMapViewModel`, which maps biomarker categories to regions and picks the
worst marker status in that region:

| Status | Colour |
|--------|--------|
| Out of range | `Color.outRange` (red) |
| Watch (above clinical target) | `.orange` |
| In range | `Color.inRange` (green) |
| No data | `Color.textMuted` (grey) |

Pins have a minimum 44 pt tap target. Tapping a pin presents `BodyRegionSheet` as a
sheet listing that region's markers and allowing drill-through to `BiomarkerDetailView`.
Tapping a region *header* in the sheet pushes `CategoryGraphsView` into the `DashboardView`
`NavigationStack` (no extra stack — reuses the existing `navigationDestination`).

### 3. Health stats overlay (top-right)

`BodyMetricsStatsPanel` is an `ultraThinMaterial` rounded rectangle, always rendered
(so `@Observable` tracking fires on first pass — avoiding a late-load blank flash):

| Row | Value |
|-----|-------|
| Height | `@AppStorage("body.heightCm")` — same key as Body tab |
| Weight | Latest `body_metrics.weightKg` |
| Waist | Latest `body_metrics.waistCm` |
| BMI | `weight_kg / height_m²` — derived, shown only when both are present |
| BP | Latest systolic/diastolic, omitted when no BP reading exists |

Height is read from `@AppStorage` (set once in first-run onboarding or Body tab
settings) rather than a backend table — there is currently no `user_profile` table
and adding a round-trip for a single static attribute is not justified.

### 4. BP stats panel (bottom-left)

`BPStatsPanel` shows **Latest BP** and **Avg BP** (integer mean over all readings).
Colour coding: red (`Color.outRange`) at sys ≥ 130 or dia ≥ 80 (ACC/AHA 2017
guideline threshold used as a neutral reference only — not a personalised clinical
target). Hides entirely when `body_metrics` has no BP entries.

### 5. Legend

A bottom-centre capsule legend labels the four pin colours. Always visible.

### 6. `CategoryGraphsView`

A new `ios/EmpiricalTracker/Features/CategoryGraphs/CategoryGraphsView.swift` view
accepts an initial `BiomarkerCategory` and renders the full set of that category's
markers as stacked Swift Charts trend views — the same chart logic as
`BiomarkerDetailView` but scoped to a category rather than a single marker. It is
pushed from both the body-map drill-down and the existing category-header tap in the
grid view.

---

## Rationale

- **Glanceable by default.** An anatomical framing maps naturally to "which part of
  my body has something flagged" — faster to parse than a list with no spatial structure.
- **Body metrics and biomarkers unified.** The user no longer has to switch to the Body
  tab to see weight/BMI alongside their lipid panel — it's all on one screen.
- **Zero loss for grid users.** The existing grid is one tap away; nothing is removed.
- **No new data models.** The body map reuses `BodyMapViewModel` (which already
  existed from the Body tab's silhouette work), `body_metrics` data already loaded by
  `BodyMetricsViewModel`, and the existing clinical-signal colours.
- **@Observable stability trick.** Rendering the stats panels even when data is absent
  (showing `--`) avoids the SwiftUI issue where an `@Observable` view that is not in the
  hierarchy on first render misses the first update notification.

---

## Consequences

- **Height source is `@AppStorage`.** Until a `user_profile` backend table is added,
  height doesn't sync across devices. This is acceptable for the current single-device
  use case; the `@AppStorage` key (`body.heightCm`) is already shared between the
  Body tab and the dashboard panel so the user sets it once.
- **BMI is informational only.** The panel computes BMI but carries no clinical
  interpretation — no colour coding, no target line. BMI is a population measure with
  well-known limits for muscle-carrying individuals; the display is explicit that it is
  a derived number.
- **BP threshold is not personalised.** The 130/80 red threshold is the ACC/AHA Stage 1
  boundary used as a neutral reference. It is not an in-app clinical target or verdict;
  the same "not medical advice" framing applies.
- **Mode does not persist across launches.** The body map is always the cold-start
  default. If user preference persistence is added later, `@AppStorage("dashboard.mode")`
  is the natural slot.
- **`CategoryGraphsView` is shared.** Both the body-map drill-down path and the
  category-header tap in the grid use the same view — consistent behaviour and a single
  maintenance point.

---

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Keep the grid as default | No at-a-glance spatial orientation; user still has to scan the full list. |
| Replace the grid entirely | Power users and accessibility users may prefer the list; removing it breaks the escape hatch. |
| Show body map in a separate tab | Adds a tab slot and splits the "health overview" concept across two tabs instead of unifying it. |
| Pull height from a backend `user_profile` table | Adds a schema migration and a round-trip for a single static attribute; deferred until there is a broader profile need. |
| Colour-code BMI in the stats panel | BMI's limitations (muscle mass, frame size) make red/green colouring potentially misleading for the app's target users (athletes, carnivore dieters). Neutral display is the safer default. |

---

## Amendment (2026-06-14): vitals bar + toolbar filter

**Status:** Accepted — supersedes the overlay-panel layout in §3–§5 above.

The original design overlaid two `ultraThinMaterial` stat cards on the canvas (heart
metrics top-left, body metrics top-right) plus a "Latest results" filter pill in its
own band above the figure. In practice this crowded the top third of the silhouette —
the cards floated directly over the head/chest where the heart and upper biomarker pins
sit — and spent a full row of chrome on a single toggle.

**Change (decluttering, "Option A"):**

1. **Single vitals bar.** The two floating cards are replaced by one slim, full-width
   `VitalsSummaryBar` (a `CardView`) anchored *above* the silhouette — not overlaid on
   it. It carries the same numbers (Resting HR, HRV, Weight, BMI, Height, Waist) as
   icon + label + value cells on one line, with the sync-freshness indicator trailing.
   The heart group remains a single tap target that opens the plain-language
   `HeartMetricsInfoSheet`. On narrow devices the row scrolls horizontally rather than
   dropping any metric.
2. **Canvas is overlay-free.** `BodyMapCanvas` now occupies the full remaining height
   with nothing layered on top, so the markers have room to breathe.
3. **Filter moved to the toolbar.** The "Latest results" toggle becomes a `.principal`
   segmented control (`Latest | All`) contributed by `DashboardBodyMapView`. Because
   that view is only built in `.bodyMap` mode, the control appears only there — it does
   not leak into the grid view's toolbar.

Rationale: the silhouette is the hero of this screen; chrome dropped from three bands
to one and no longer occludes the figure, while every metric stays glanceable. The
bottom strip is still avoided for any control (it sits behind the floating tab bar and
the `NavigationStack` does not honour the reserved safe-area inset — see PR #128).
