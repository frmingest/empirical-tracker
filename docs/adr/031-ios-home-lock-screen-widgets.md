# ADR-031: Home Screen & Lock Screen widgets (WidgetKit)

**Status:** Proposed
**Date:** 2026-06-05
**Author:** Faiz (solo developer)
**Sprint:** Tier 1 native engagement (WISHLIST #1 — builds on ADR-014 clinical
signals, ADR-021 body metrics, ADR-025 design system)

---

## Context

A blood-test app is opened **rarely** — typically only when a new panel arrives.
That is the central engagement problem the native iOS rewrite exists to solve, and
`WISHLIST.md` calls Home/Lock-screen widgets the *"biggest single retention lever"*
(#1). Widgets keep the app's headline signals present between the infrequent imports
without requiring the user to open the app at all.

The data the widgets need already exists as `Codable, Sendable` models in `Core`:

- `BiomarkerWithSeries` → `latestResult`, `trend`, and the ported `MarkerSignals`
  assessment (in-range / **Watch** / out-of-range).
- `BodyMetric` → `weightKg`, `waistCm`, `systolic/diastolic`.
- `FoodEntry` → daily macro totals (computed client-side).

### What's missing in the codebase today

Two concrete blockers were confirmed:

1. **No App Group / shared storage.** `EmpiricalTracker.entitlements` carries only the
   HealthKit keys. There is no offline cache — *every read hits the network*
   (`WISHLIST.md` #9). A widget extension cannot stand up the full `AppEnvironment` +
   `APIClient` + auth stack on every timeline refresh (memory/time budget, and no UI to
   re-auth).
2. **The Keychain session is not shareable.** `KeychainService` (`Auth` package) uses
   service `com.empirical.tracker` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
   and **no `kSecAttrAccessGroup`**, so a widget process cannot read the JWT.

### Requirements driving this decision

1. **Glanceable headline state** on the Home Screen — latest marker + trend + the count
   of markers in **Watch** — and a body-metric trend, without opening the app.
2. **No network or auth inside the widget extension** — the widget must render from
   local data, instantly, every refresh.
3. **Privacy for special-category health data.** Widgets render where onlookers can see
   them (especially the Lock Screen). The default must not leak raw values.
4. **Design-system consistency** — reuse the existing semantic colour tokens and the
   clinical-status colours, not one-off styling.
5. **Ship independently of the larger SwiftData offline-cache effort** (#9), without
   precluding it later.

---

## Decision

**Add a WidgetKit extension that renders exclusively from a small write-through
"widget snapshot" file in a shared App Group container. The main app owns all
networking/auth and writes the snapshot; the widget only reads it.**

### 1. Shared storage: App Group snapshot (not full SwiftData, not shared Keychain)

- Add App Group `group.app.empirical.tracker` to the app target and a new widget
  extension entitlements file.
- A new **`WidgetShared` Swift package** (depended on by both the app and the extension)
  owns:
  - `WidgetSnapshot` — a tiny `Codable` value type: the headline marker (name, value,
    unit, trend, status), the Watch-marker count, a short weight series, a
    `generatedAt` timestamp, and an `isSignedIn` flag.
  - `SnapshotStore` — read/write the snapshot as JSON in
    `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`.
  - Shared formatting + status→colour helpers (lifted from the design system; see §5).
- **Write-through:** at the end of `AppEnvironment.refreshAll()` (and after a biomarker
  import, a body-metric log, and a food log), the app builds a `WidgetSnapshot` from the
  data it already has in memory and calls `SnapshotStore.write(_:)` then
  `WidgetCenter.shared.reloadAllTimelines()`.

This deliberately **avoids sharing the Keychain JWT** with the extension — the widget
never makes an authenticated call, so the token never needs to leave the app. It also
**decouples widgets from SwiftData (#9):** when the offline cache lands, the widget can
read from it instead of the JSON file with no change to the widget UI.

### 2. The widget extension target

A new `EmpiricalTrackerWidgets` app-extension target (added to `project.pbxproj` — see
*Consequences*), member of the App Group, depending only on `WidgetShared`. It does **not**
link `Core`/`APIClient`/`Auth`, keeping the extension's memory footprint small.

Each widget uses a `TimelineProvider` that:
- returns a `placeholder` and `snapshot` from `WidgetSnapshot.placeholder` (redacted
  sample data, for the gallery),
- builds its timeline from `SnapshotStore.read()`, with refresh policy `.after` ≈ 6 h
  (biomarker data changes rarely; the app also force-reloads on every write, so the
  timer is only a backstop).

### 3. Widgets shipped (phase 1)

| Widget | Families | Content |
|--------|----------|---------|
| **Latest panel** | `.systemSmall`, `.systemMedium`, `.accessoryRectangular`, `.accessoryCircular` | Headline marker (LDL or HbA1c) latest value + trend arrow + **Watch-marker count** |
| **Weight trend** | `.systemSmall`, `.accessoryRectangular` | Latest weight + a small Swift Charts sparkline |

`Today's intake` (kcal / protein-vs-target) is deferred to a later phase, paired with the
daily-targets feature (WISHLIST #6) which is not yet shipped.

Each widget sets a `widgetURL` deep link (e.g. `empirical://biomarker/<id>`,
`empirical://body`) so a tap opens the relevant screen.

### 4. Privacy: status-only on the Lock Screen, opt-in values

Health values are GDPR special-category data, so the **default never renders a raw number
where an onlooker sees it**:

- **Lock Screen accessories** and any `.privacySensitive()` / redacted render show
  **label + status only** — e.g. `LDL · Watch`, `2 markers to watch` — not `4.1 mmol/L`.
- **Home Screen** widgets show values by default (the Home Screen is behind device
  unlock).
- A new Settings toggle **"Show values in widgets"** (default **off** for Lock-screen
  families) lets the user opt into raw values on the Lock Screen.
- Widgets respect `widgetRenderingMode` (`.accented` / `.vibrant`) for Lock-screen
  tinting; colour is **never the only signal** — status is always paired with an SF
  Symbol + text, per the design-system rule.

### 5. Design-system reuse

The widget reuses the existing **semantic clinical-status colours** (`Color.inRange`
green, `.orange` Watch, `Color.outRange` red, `Color.textMuted` no-data) and a compact
typographic scale. Because the extension does not link `Core`, the few tokens and the
status→colour/SF-symbol mapping the widgets need are lifted into `WidgetShared` (with
`#Preview`s) as the single source of truth shared by app and extension, and documented in
`DESIGN_SYSTEM.md`. No hardcoded hex, no inline `Font.system(size:)`.

---

## Rationale

- **Snapshot over full SwiftData.** A ~1 KB JSON write the app already has the data for
  is far less work than the deferred offline-cache effort, removes the keychain-sharing
  problem entirely, and writes health data to one extra place *only if the feature is
  built* — with a clean upgrade path to SwiftData later.
- **No auth in the extension.** The widget never authenticates, so the JWT stays in the
  app's device-only Keychain exactly as ADR-026 requires; no shared access group, no new
  attack surface for the token.
- **Privacy-by-default.** Status-only on the Lock Screen keeps special-category values
  off a surface visible without unlocking, while still being useful ("2 to watch").
- **Reuses existing models + clinical logic.** `BiomarkerWithSeries`, `MarkerSignals`,
  and `BodyMetric` already produce everything the widgets show — no new clinical code.
- **Consistent with the app.** Same status colours + icon/text pairing as the body-map
  dashboard (ADR-030), so the widget reads as part of the same product.

---

## Consequences

- **One manual `project.pbxproj` edit.** This project uses Xcode-16
  `PBXFileSystemSynchronizedRootGroup` folder sync, which auto-adds *files* to existing
  targets but does **not** create new targets. The widget-extension target, its App Group
  entitlement, and the `WidgetShared` dependency must be added to the pbxproj by hand and
  verified to build. This is the only fragile step.
- **Snapshot freshness depends on the app running.** The widget shows data as of the last
  app foreground/refresh/import. This is acceptable — biomarker data changes only on
  import, and the app reloads timelines on every relevant write. A `.after` ≈ 6 h backstop
  covers the timer case.
- **Health data now also lives in the App Group container.** It is inside the app's
  sandbox group (not iCloud, not a backup that leaves the device), and is wiped on sign-out
  and account deletion alongside the Keychain session — the GDPR-erasure path must clear
  the snapshot file too.
- **No personalisation/verdicts.** The widget surfaces the same Watch/in-range/out-of-range
  assessment the app already computes; it adds no new interpretation and carries the
  app's "decision-support, not medical advice" framing implicitly (it only mirrors
  in-app status).
- **Today's-intake widget deferred** until daily targets (WISHLIST #6) ship, so the
  intake widget has a meaningful denominator.

---

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Build the SwiftData offline cache (#9) first, widget reads from it | Larger scope; blocks the highest-leverage retention feature on an unrelated effort. The snapshot is a strict subset and upgrades to SwiftData cleanly. |
| Share the Keychain JWT (access group) and let the widget fetch from the API | Adds a network + auth + re-auth-UI problem to a process with no UI and a tight budget; widens the token's exposure; slow/flaky timeline refreshes. |
| Render values on the Lock Screen by default | Exposes special-category health data to anyone glancing at the phone; conflicts with the app's privacy posture. Made opt-in instead. |
| Put widget code directly in the app target | App extensions require a separate target; shared code goes in `WidgetShared` so both consume one source of truth. |
| Link `Core` into the extension for the design tokens | `Core` pulls in networking/auth/resources the extension shouldn't carry; lifting only the needed tokens into `WidgetShared` keeps the extension lean. |

---

## Implementation phases

- **Phase 0 — Foundations:** App Group entitlement on the app; `WidgetShared` package
  (`WidgetSnapshot`, `SnapshotStore`, status helpers); write-through from
  `AppEnvironment.refreshAll()` + import/log paths; clear the snapshot on sign-out and in
  the GDPR-erasure path.
- **Phase 1 — Extension + Latest panel:** add the widget-extension target to the pbxproj;
  `TimelineProvider`; small/medium/Lock views; placeholder/redacted/no-data/sign-in
  states; `widgetURL` deep link + `onOpenURL` routing in `RootView`.
- **Phase 2 — Weight trend + polish:** weight widget; the "Show values in widgets"
  Settings toggle.
- **Phase 3 — Tests & docs:** unit tests for snapshot encode/decode + the "what to show"
  selection logic (all in `WidgetShared`, testable without WidgetKit); update
  `DESIGN_SYSTEM.md`, `WISHLIST.md` #1, and `SOLUTION.md`.
