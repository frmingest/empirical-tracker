# ADR-022: iOS Withings capture via Apple HealthKit

**Status:** Accepted — **scope since widened** (see update note below)
**Date:** 2026-06-02
**Author:** iOS team
**Sprint:** 9 (iOS)

---

> **Update note (2026-06):** the §1 scope line ("weight + blood pressure now;
> body composition deferred") has since moved on. The three **heart metrics** —
> resting HR, HRV, and daily-average HR — shipped via `016_heart_metrics.sql` /
> `017_heart_metrics_constraint.sql`, so `HealthMetricType` now enumerates five
> types (all default-enabled), and **iPhone activity** (steps, active energy,
> exercise minutes) shipped in its own `activity_metrics` table via
> [ADR-033](033-ios-healthkit-activity-metrics.md). The
> `NSHealthShareUsageDescription` has been rewritten to name all of these. Only
> **body-fat % / lean mass** remain deferred (they still await the
> `withings_measures` table, §4.3). This ADR is preserved as the point-in-time
> record of where the line was first drawn.

## Context

The migration plan (`IOS_MIGRATION_PLAN.md` §1.2) chooses a **two-path** Withings
strategy and sequences the **Apple HealthKit bridge first** (Sprint 9) because it
needs no Withings partner contract and ships value independently of the Cloud-API
approval lead time (§7). The user's **Health Mate** app already writes Withings
device data into Apple Health; our job is to read it back out and fold it into the
body-metrics surface built in Sprint 8 (ADR-021), which already carries the
`source` provenance column (`manual | healthkit | withings`) and a synced-row badge
laid down as groundwork.

Sprint 8 left a **stub `HealthSyncManager`** exposing the intended interface. This
ADR records how that interface is realised and, importantly, **where the scope line
is drawn** given the backend has not yet changed.

### The constraint that shapes scope

The existing `body_metrics` table has columns for **weight**, waist, and **blood
pressure** only. The richer Withings signals the plan also lists — body-fat %, lean
mass, resting heart rate, SpO2 — have **nowhere to land server-side** until the
`withings_measures` table from migration plan §4.3 exists. That table is backend
work scheduled alongside the Cloud API (Sprint 10).

Per the "reuse the backend / no premature backend changes" principle, **iOS Sprint 9
ships only the metrics that map onto existing columns**, and we request HealthKit
read authorization for exactly those — keeping the App Review usage strings honest
(we don't ask for body-fat data we can't yet store).

---

## Decision

### 1. Scope: weight + blood pressure now; body composition deferred to §4.3

`HealthMetricType` enumerates just `.weight` and `.bloodPressure`. These map cleanly:

- body mass → `weight_kg`;
- the `bloodPressure` **correlation** (systolic + diastolic quantity samples) →
  `systolic` / `diastolic`.

Body-fat %, lean mass, and resting HR are explicitly **out of scope this sprint** and
called out in the Settings "About" copy as "coming once supported by the backend."
They unblock when §4.3 lands (Sprint 10).

### 2. `HealthSyncManager` is an actor that reads, maps, dedupes, delegates

The manager (in the `HealthSync` package) owns the HealthKit work off the main actor:
`requestAuthorization`, a historical/manual `sync`, and `startObserving` for
background delivery. It is **backend-agnostic** — it maps samples to
`BodyMetricPayload`s tagged `source: .healthkit` and hands them to an injected
**`BodyMetricSyncSink`**. The app provides `RepositoryBodyMetricSyncSink`, which
POSTs through the Sprint 8 `BodyMetricsRepository`, so a synced reading travels the
exact same `POST /body-metrics` path as a manual one — only the provenance differs.
This keeps the package free of networking and unit-testable with an in-memory sink.

All HealthKit access sits behind `#if canImport(HealthKit)`; on platforms without
the framework the public methods report `.unavailable`, so the package still builds
and `HealthSyncManager.isHealthDataAvailable` gates the whole feature in the UI.

### 3. Deduplication is client-side, by sample UUID

`SyncedSampleStore` (a `UserDefaults`-backed actor) records the HealthKit sample
UUIDs already uploaded, so re-syncs and background deliveries never insert the same
reading twice. This is the **client** half of dedupe. The **server** half — an
`external_id` column on `body_metrics` that also rejects a reading arriving a second
time via the Withings Cloud path — is migration plan §4.2 backend work for Sprint 10.
Until then, the local set is sufficient for the HealthKit-only path; we therefore
**keep the synced-UUID record on disconnect** so reconnecting does not re-upload rows
already on the backend.

### 4. Connection model works *with* HealthKit's privacy design

HealthKit deliberately never reveals **read**-authorization status. So "connected"
cannot be read back from the system; instead `HealthSyncState` treats a non-throwing
permission request as "the user has chosen" and persists a local connected flag, plus
the last-sync timestamp and per-type toggles. A single `HealthSyncState` lives on
`AppEnvironment` so the Body tab card and the Settings detail show one shared state.

### 5. Background delivery is best-effort; "Sync now" is the contract

`startObserving` registers `HKObserverQuery` + `enableBackgroundDelivery(…, .hourly)`
(requiring the new `com.apple.developer.healthkit.background-delivery` entitlement).
Apple documents background delivery as best-effort, so the UI always offers a manual
**Sync now**, and the Body tab tops up on appear. New Withings readings therefore
arrive automatically when iOS schedules delivery, and on demand otherwise.

### 6. Privacy posture, stated in-app and in the usage string

Imported rows are saved to the user's account (Supabase Frankfurt, EU) so they appear
on every device — but the footer and `NSHealthShareUsageDescription` make clear that
Apple Health data is read-only, only the enabled types are touched, and data is
uploaded **only when the user syncs**. This satisfies the migration plan's privacy
rule (§2) while still giving cross-device persistence, which the read-from-backend
charts require.

---

## Consequences

- **Good:** Withings weight + BP flow into the same charts, overlays, and history as
  manual entries, tagged and badged as `healthkit` — Sprint 9's core acceptance, with
  zero backend changes.
- **Good:** The package boundary (manager reads HealthKit; sink uploads) keeps clinical
  and networking concerns out of `HealthSync` and makes the logic testable without a
  device.
- **Good:** Honest authorization scope and a specific usage string de-risk App Review.
- **Trade-off / deferred:** Body composition (fat %, lean mass, resting HR) waits on
  the §4.3 `withings_measures` table; the UI and `HealthMetricType` have an obvious
  extension point for it.
- **Trade-off:** Client-only dedupe means a future device that *also* connects the
  Withings Cloud path (Sprint 10) could double-count until the §4.2 server `external_id`
  column exists. Acceptable while HealthKit is the only ingestion path.
- **Limitation:** HealthKit can't be tested in the Simulator with real data; the
  acceptance flow is a manual on-device test (seed Apple Health / install Health Mate),
  tracked for the Sprint 12 QA matrix.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Request authorization for body-fat / lean mass / resting HR now | Nowhere to store them until §4.3; asking for health data we can't use weakens the App Review usage-string justification. |
| Give `HealthSyncManager` the `APIClient` directly | Couples the package to networking and to `@MainActor` repository state; the `BodyMetricSyncSink` seam keeps it backend-agnostic and testable. |
| Server-side dedupe only (external_id) | That column is Sprint-10 backend work; a client-side UUID set ships the HealthKit path now without waiting. |
| A local-only (SwiftData) store for HealthKit rows, never uploaded | The body-metrics charts read from the backend; keeping synced rows device-local would split the timeline and break cross-device parity. Upload-on-sync with a clear consent string is the chosen posture. |
| Poll on a timer instead of `HKObserverQuery` | Wastes energy and still misses backgrounded updates; observer queries + background delivery are the platform-native mechanism, with "Sync now" as the documented fallback. |

---

> Numbering note: ADR-022 uses **iOS** sprint numbering (Sprint 9), continuing from
> ADR-021. It realises migration plan §1.2 Path A and depends on the body-metrics
> surface from ADR-017 / ADR-021. The Withings **Cloud API** path (Path B) and its
> backend tables/dedupe (§4.2–§4.4) are recorded separately in [ADR-023](023-ios-withings-cloud-connection.md) (Sprint 10).
