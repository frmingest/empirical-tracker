# ADR-031 (companion) — WidgetKit implementation & Xcode setup

> **This is the implementation companion to
> [ADR-031: Home Screen & Lock Screen widgets](031-ios-home-lock-screen-widgets.md).**
> That file is the canonical *decision* record; this one captures the concrete
> source files written and the manual Xcode-target / App-Group setup the widget
> extension still needs. The two share the ADR-031 number deliberately — they
> describe one decision, not two. (Numbering hygiene: future single-file ADRs
> continue from 034.)

**Status:** In progress (source files written; Xcode target setup required — see below)  
**Date:** 2026-06-05

---

## Context

WISHLIST item #1 describes three widgets to extend the app onto the Home Screen and Lock Screen:
- **Biomarker Panel** — out-of-range/watch count + flagged marker list
- **Weight Trend** — latest weight + 30-day sparkline
- **Today's Macros** — protein/carbs/fat/kcal from the food diary

Widgets are a top retention lever for a blood-test app that is opened rarely.

### Constraints

- No SwiftData cache yet (every read still hits the network). Widgets have no network
  access. Solution: write a `WidgetSnapshot` JSON blob to a shared App Group container
  after every successful app-side load. This is the standard pre-SwiftData pattern.
- Adding a widget extension is a **separate Xcode target**, which requires xcodeproj
  changes that must be done through Xcode GUI (adding a target via File → New → Target).

---

## Decision

### Shared data: App Group + UserDefaults

- App Group ID: `group.app.empirical.tracker`
- The main app writes `WidgetSnapshot` (Codable JSON) to `UserDefaults(suiteName:)` after
  every `refreshAll()` and food-diary save, then calls `WidgetCenter.shared.reloadAllTimelines()`.
- The widget extension reads the same UserDefaults key (`widget_snapshot_v1`) — no network,
  no framework imports beyond WidgetKit.

### Three widgets

| Widget | Families | Data used |
|---|---|---|
| `BiomarkerPanelWidget` | small, medium | `BiomarkerSummary` (counts + flagged list) |
| `WeightTrendWidget` | small, medium | `WeightSummary` (latest + 30-day series) |
| `MacrosDiaryWidget` | medium | `MacroSummary` (today's kcal/protein/carbs/fat) |

Timeline reload policy: `after(+1 hour)` for all widgets. The app also calls
`reloadAllTimelines()` on every data-load, so the widget refreshes immediately
when the user opens the app.

### Snapshot model

`WidgetSnapshot.swift` is **duplicated** in both `EmpiricalTracker/Features/Widgets/`
and `EmpiricalTrackerWidget/`. Using SPM would require a new Package; duplication is
simpler at this scale. A `// NOTE: keep in sync` comment in both files calls it out.

---

## Implementation files (already written)

```
ios/EmpiricalTracker/Features/Widgets/
  WidgetSnapshot.swift       — shared data model (app-side copy)
  WidgetDataStore.swift      — writes snapshot + reloads timelines

ios/EmpiricalTrackerWidget/
  EmpiricalTrackerWidget.swift  — @main WidgetBundle
  WidgetSnapshot.swift          — shared data model (widget-side copy)
  WidgetDataReader.swift        — reads snapshot + placeholder data
  BiomarkerPanelWidget.swift    — biomarker panel widget
  WeightTrendWidget.swift       — weight trend widget
  MacrosDiaryWidget.swift       — macros diary widget
  EmpiricalTrackerWidget.entitlements

ios/EmpiricalTracker/EmpiricalTracker.entitlements  — App Group added
ios/EmpiricalTracker/App/AppEnvironment.swift       — writeWidgetSnapshot() wired in
```

---

## Xcode setup (required before the widget builds)

### 1 — Add the widget extension target

1. Open `ios/EmpiricalTracker.xcodeproj` in Xcode.
2. **File → New → Target…**
3. Choose **Widget Extension** (iOS).
4. Product Name: `EmpiricalTrackerWidget`
5. Bundle Identifier: `app.empirical.tracker.widget`
6. Uncheck **"Include Live Activity"** and **"Include Configuration App Intent"**
7. When asked whether to activate the scheme, click **Activate**.
8. Xcode will create a default `EmpiricalTrackerWidget.swift` — **delete it** (or replace
   with the file from `ios/EmpiricalTrackerWidget/`).

### 2 — Add the source files to the target

In the Xcode project navigator, select all files in `ios/EmpiricalTrackerWidget/`:

```
EmpiricalTrackerWidget.swift
WidgetSnapshot.swift
WidgetDataReader.swift
BiomarkerPanelWidget.swift
WeightTrendWidget.swift
MacrosDiaryWidget.swift
```

Make sure their **Target Membership** is set to `EmpiricalTrackerWidget` only
(not the main app). `EmpiricalTracker/Features/Widgets/WidgetSnapshot.swift` and
`WidgetDataStore.swift` belong to the **main app** target only.

### 3 — Add App Group capability to both targets

For **EmpiricalTracker** (main app):
1. Select the `EmpiricalTracker` target → Signing & Capabilities
2. `+ Capability` → App Groups
3. Add `group.app.empirical.tracker`
4. The entitlements file is already updated; Xcode will confirm the capability.

For **EmpiricalTrackerWidget**:
1. Select the `EmpiricalTrackerWidget` target → Signing & Capabilities
2. `+ Capability` → App Groups
3. Add the same `group.app.empirical.tracker`
4. Set the **Entitlements file** to `EmpiricalTrackerWidget/EmpiricalTrackerWidget.entitlements`.

### 4 — Register the App Group in the Apple Developer portal

If you haven't already:
1. developer.apple.com → Identifiers → App Groups → +
2. Description: "Empirical Tracker shared container"
3. Identifier: `group.app.empirical.tracker`
4. Enable the group on both `app.empirical.tracker` and `app.empirical.tracker.widget`.
5. Regenerate provisioning profiles for both App IDs.

### 5 — Build & test

1. Build the main app target to confirm `WidgetKit` import in `AppEnvironment` compiles.
2. Build `EmpiricalTrackerWidget` separately to confirm the widget compiles.
3. Run on device, add a widget, verify the placeholder renders correctly.
4. Open the app and let data load — the widget should refresh within seconds.

---

## Consequences

- Widgets show stale data if the user has not opened the app recently (no background
  refresh — this is a pre-SwiftData limitation). The `updatedAt` timestamp on
  `WidgetSnapshot` surfaces how old the data is if needed.
- When SwiftData (#9 in WISHLIST) lands, replace the UserDefaults snapshot with a
  SwiftData model store shared via the App Group container path — the widget views
  stay unchanged.
- `WidgetCenter.shared.reloadAllTimelines()` costs one background wake. Fine for
  our load cadence (~once per session).
