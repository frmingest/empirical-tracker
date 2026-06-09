# ADR-033: Apple Health activity metrics (steps, active energy, exercise minutes)

**Status:** Accepted — **data foundation shipped** (table, sync, GDPR); the on-chart
activity-context band (§5) remains a UI follow-up.
**Date:** 2026-06-09
**Author:** iOS team
**Sprint:** HealthKit expansion

---

## Context

Every Apple Health signal the app reads today lands in `body_metrics`: weight,
waist (column exists, see note), blood pressure, and — since migration
`016_heart_metrics.sql` — resting HR, HRV, and daily-average HR. The integration
(`HealthSyncManager`, `ios/Packages/HealthSync/`) was scoped as a **Withings
bridge** (ADR-022): Health Mate writes Withings *measurements* into Apple Health,
and we read those back. That framing is why the data model only knows
**measurements** — discrete readings of the body — and has no concept of
**activity**.

The result is a conspicuous gap: the app collects **zero activity data**. No
steps, no active energy, no exercise minutes, no workouts. This is the single
largest *category* of Apple Health data we ignore — not a missing metric, a
missing axis.

Two things make activity worth collecting specifically for *this* app:

1. **It is the honesty check on every chart we already draw.** The product's
   whole claim is diet → outcome correlation: a diet-event marker laid over a
   weight / BP / HRV trend (ADR-010). Today, if a user's resting HR falls or
   weight drops near a diet change, the chart *implies* the diet did it. Without
   activity data we cannot distinguish diet from a user who simply started
   walking 10k steps a day. Activity is the dominant **confounder** of the
   outcomes we chart, and we currently have no way to see it, let alone control
   for it.

2. **It is the broadest, cheapest daily signal we can get.** Steps and active
   energy are written all day by the **iPhone alone** — no Apple Watch, no
   Withings device required. Unlike weight/BP (which depend on the user owning
   and using a scale/cuff), activity is data we would receive from ~100% of
   users, continuously. That is exactly the glanceable daily signal the roadmap
   keeps asking for (widgets, retention — `WISHLIST.md` Tier 1).

The blocker has never been HealthKit; it is **storage**. Activity is
high-frequency time-series (`stepCount` can be hundreds of thousands of raw
samples per user) and is *daily-aggregate context*, not a one-off measurement.
It is a poor fit for the one-row-per-day, "at least one body metric"
`body_metrics` shape (constraint `at_least_one_metric`, migration
`008_body_metrics.sql`). It wants its own table — the same kind of deliberate
decision deferred for `withings_measures` (ADR-022/023). This ADR makes that
decision.

> **Doc-drift note:** ADR-022 and `NSHealthShareUsageDescription` still describe
> the scope as "weight and blood pressure," but the three heart metrics already
> shipped. Any sprint that touches HealthKit authorization should correct both
> the usage string and ADR-022's scope statement as part of the same change.

---

## Decision

### 1. A new `activity_metrics` table — not new `body_metrics` columns

Activity gets its own daily-grain table rather than riding on `body_metrics`,
because it plays a **different role** (context/confounder, not a measured
outcome) and has **different mutation semantics** (see §4). Keeping it separate
keeps `body_metrics` honest — a row there still means "the user took a
measurement that day" — and avoids relaxing the `at_least_one_metric` constraint
to accommodate auto-collected activity.

```sql
-- migration NNN_activity_metrics.sql
create table public.activity_metrics (
    id            uuid        primary key default uuid_generate_v4(),
    user_id       uuid        not null references auth.users(id) on delete cascade,
    measured_on   date        not null,
    steps                integer  check (steps is null or steps >= 0),
    active_energy_kcal   numeric  check (active_energy_kcal is null or active_energy_kcal >= 0),
    exercise_minutes     integer  check (exercise_minutes is null or exercise_minutes >= 0),
    source        text        not null default 'healthkit'
                              check (source in ('healthkit', 'manual')),
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    -- One activity row per user per day; re-syncing a day UPSERTs it (see §4).
    constraint activity_metrics_user_day unique (user_id, measured_on),
    constraint at_least_one_activity check (
        steps is not null or active_energy_kcal is not null or exercise_minutes is not null
    )
);

create index on public.activity_metrics (user_id, measured_on);

alter table public.activity_metrics enable row level security;
create policy "users_own_activity_metrics" on public.activity_metrics
    for all using (auth.uid() = user_id);
```

Endpoints mirror `body_metrics`: `GET /activity-metrics`,
`POST /activity-metrics/batch` (the sync hot path), and
`DELETE /activity-metrics/by-source/{source}` (disconnect cleanup). The batch
endpoint **upserts** on `(user_id, measured_on)` — see §4.

### 2. Scope: steps, active energy, exercise minutes

`ActivityMetricType` enumerates exactly three types, chosen because each is
(a) collected from iPhone-only users, and (b) a clean daily scalar:

| HealthKit type | Aggregation | → `activity_metrics` column |
|---|---|---|
| `HKQuantityType(.stepCount)` | daily **sum** | `steps` |
| `HKQuantityType(.activeEnergyBurned)` (kcal) | daily **sum** | `active_energy_kcal` |
| `HKQuantityType(.appleExerciseTime)` (min) | daily **sum** | `exercise_minutes` |

Deferred (noted as the extension point, exactly as ADR-022 left body
composition): individual **workouts** (`HKWorkoutType` — route/heart-rate
detail, a richer model), **stand hours**, **basal energy**, and
**walking/running distance**. These add storage and UI surface without changing
the core "is the user more active around this diet change?" answer that v1
delivers.

### 3. Reads reuse `HealthSyncManager`; a parallel sink keeps the model clean

`HealthSyncManager` already owns all HealthKit work off the main actor, so the
new reads live there. Activity sums are computed **inside HealthKit** via
`HKStatisticsCollectionQuery` with `.cumulativeSum` and a one-day interval —
the same pattern the existing daily-average HR query uses (`.discreteAverage`),
and essential here because loading raw step samples (potentially 100k+) would be
ruinous.

Because activity does **not** map onto `BodyMetricPayload`, it does not reuse
`BodyMetricSyncSink`. Instead a small parallel seam — `ActivityMetricSyncSink`
with an `uploadBatch([ActivityMetricPayload])` — keeps the package
backend-agnostic and testable, exactly as the body-metric path does. The app
provides a `RepositoryActivityMetricSyncSink` that POSTs through a new
`ActivityMetricsRepository` to `/activity-metrics/batch`. `HealthSyncManager`
gains an `syncActivity(types:since:)` alongside the existing `sync(...)`.

### 4. Dedup is by day-key + UPSERT, not by sample UUID — because today is mutable

This is the key behavioural difference from every metric we sync today. A weight
or BP sample is **immutable**: once recorded, its UUID identifies a value that
never changes, so the `SyncedSampleStore` UUID set is the right dedup. A daily
activity **sum is mutable**: today's step count keeps growing until midnight, and
even past days can gain late-arriving samples. UUID-skip dedup would freeze a
day at its first partial reading.

So activity dedups the way the daily-average HR path already hints at — a
deterministic day-key (`steps-<yyyy-MM-dd>`) — but pairs it with a server
**UPSERT on `(user_id, measured_on)`**: re-uploading a day overwrites it.
Combined with always re-pulling a **trailing window** (default: last 7 days, or
`since` for a full history import) on each sync, partial days settle to their
final totals without ever duplicating a row. The local UUID store is not used
for activity.

### 5. Product role: confounder context, not a charted "outcome"

Activity is surfaced as **context for the existing charts**, not as a new health
outcome with its own target lines. Concretely (UI is a follow-up ADR, but the
data decision constrains it): activity renders as a secondary context band under
the diet-event overlay — "how active was the user across this period" — so a
reader can discount an outcome change that coincides with an activity change. We
deliberately do **not** draw clinical target/guideline lines on activity (cf.
the BP chart's neutral 120/80 guideline) — there is no diet-app "target" for
steps, and inventing one would repeat the over-claiming this app exists to
avoid. Future work may let the correlation layer *control for* activity; this
ADR only commits the data foundation for it.

### 6. Authorization, usage string, privacy

The three read types are added to `requestAuthorization` and to the observer set
(background delivery, `.hourly`, as today). `NSHealthShareUsageDescription` is
rewritten to (a) correct the existing heart-metrics drift and (b) state the
activity scope honestly — e.g. "…also reads your steps, active energy, and
exercise minutes so it can show how active you were around diet changes." Same
posture as ADR-022 §6: read-only, only the enabled types, uploaded only on sync,
stored in the EU (Supabase Frankfurt), under existing GDPR export/delete (the
new table is added to the export bundle and the account-deletion cascade —
`on delete cascade` above handles the latter).

---

## Consequences

- **Good:** The app gains a continuous, iPhone-only daily signal from ~100% of
  users — the broadest Health data we collect, and the retention/widget signal
  the roadmap wants.
- **Good:** Diet → outcome charts become defensible: a reader can see when an
  outcome change coincides with an activity change, instead of the chart
  silently implying diet caused it.
- **Good:** `body_metrics` stays semantically clean ("a measurement happened");
  activity's different role and mutation semantics live in a table shaped for
  them.
- **Good:** Reads reuse the existing `HealthSyncManager` + statistics-collection
  pattern; only a thin parallel sink/repository/endpoint is new.
- **Trade-off:** A second sync path and table (vs. one unified Health importer).
  Justified by the immutable-vs-mutable dedup split — forcing both through one
  mechanism would corrupt one of them.
- **Trade-off / deferred:** Workouts, distance, stand hours, basal energy are
  out of scope; the enum and table are the extension point.
- **Limitation:** Like all HealthKit work, the sync can't be exercised in the
  Simulator with real data — on-device QA only (Sprint 12 matrix).

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Add `steps` / `active_energy` columns to `body_metrics` | Different role (auto-collected context vs. user measurement) and different mutation semantics (mutable daily sum vs. immutable sample); would force relaxing `at_least_one_metric` and pollute "a measurement happened" rows with auto data. |
| Reuse `BodyMetricSyncSink` / UUID dedup for activity | UUID-skip dedup freezes a still-growing day at its first partial reading. Day-key + UPSERT + trailing re-pull is required for mutable aggregates. |
| Import raw step/energy samples | Hundreds of thousands of samples per user; `HKStatisticsCollectionQuery` computes daily sums inside HealthKit, the only viable approach. |
| Sync individual workouts now | Richer model (routes, per-workout HR, types) and UI surface; v1's "how active around this change" question is answered by daily sums. Deferred as the extension point. |
| Chart activity as a primary outcome with targets | No legitimate diet-app "target" for steps; target lines would repeat the over-claiming the app exists to avoid. Activity is context, not a verdict. |
| Keep ignoring activity (status quo) | Leaves the core correlation claim unguarded against the dominant confounder and forgoes the broadest available daily signal. |

---

## Implementation notes (shipped)

- **Migration** `api/supabase/migrations/021_activity_metrics.sql` adds the
  `activity_metrics` table exactly as specified (daily grain, `at_least_one_activity`
  check, `unique (user_id, measured_on)`, RLS, `on delete cascade`). It is registered in
  `api/app/account/repository.py` `USER_TABLES` + `DELETE_ORDER`, so it flows into the
  GDPR Art. 20 export and Art. 17 erasure (the schema-drift guard in
  `tests/test_account.py` enforces this).
- **Backend.** `api/app/activity_metrics/` mirrors the body-metrics domain:
  `GET /activity-metrics`, `POST /activity-metrics/batch` (UPSERT on
  `(user_id, measured_on)`), and `DELETE /activity-metrics/by-source/{source}`.
- **iOS.** `HealthSync` gains `ActivityMetricType` (the three types,
  `defaultEnabled`), `ActivityMetricPayload`, and an `ActivityMetricSyncSink`;
  `HealthSyncManager.syncActivity(types:since:)` computes daily sums via
  `HKStatisticsCollectionQuery(.cumulativeSum)`. The app wires
  `RepositoryActivityMetricSyncSink` → `ActivityMetricsRepository` →
  `/activity-metrics/batch`, and `HealthSyncState` always re-pulls a trailing 7-day
  window (mutable daily totals); the local UUID store is deliberately **not** used for
  activity.

**Not yet wired:** the §5 product surface — activity is synced and stored but not yet
drawn as a context band under the diet-event overlay; the correlation layer does not
yet *control for* it.

> Numbering note: ADR-033 continues the iOS HealthKit thread from ADR-022
> (Withings bridge) and ADR-023 (Withings Cloud). It is independent of the
> deferred `withings_measures` table — activity is iPhone-sourced and needs its
> own daily-grain table regardless of whether body-composition signals ever
> arrive via Withings.
