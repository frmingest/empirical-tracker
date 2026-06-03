# Empirical Tracker — Web → iOS Migration (status summary)

> **Historical record, trimmed.** This plan drove the rewrite of the Empirical
> Tracker web app into a native iOS application (Swift / SwiftUI) over a backend
> that was reused unchanged. Most of it has shipped — the detailed sprint-by-sprint
> develop/acceptance breakdown has been retired. What remains here is the strategy
> that still explains *why* the app is shaped the way it is, the **status table**,
> and the **outstanding backend work** (Withings Cloud) the iOS client is waiting on.
>
> For the current product picture see [`SOLUTION.md`](SOLUTION.md); for individual
> decisions see [`adr/`](adr/).

---

## 1. The strategy (why it's built this way)

### Reuse the backend — do **not** rewrite it

The existing **FastAPI + Supabase** backend is platform-agnostic and already does the
hard, clinical, well-tested work: Excel parsing, biomarker categorization, the
multi-source food-search proxy (Open Food Facts / Matvaretabellen / USDA),
clinical-target & trend logic, GDPR export/erasure, and RLS-enforced data isolation.
The iOS app became a **native REST/Supabase client** of that same backend.

| Concern | Approach |
|---|---|
| Auth | `supabase-swift` → same Supabase JWT, stored in Keychain |
| Data access | Swift `APIClient` mirroring the existing REST endpoints |
| Row-level security | Identical — RLS is enforced in Postgres, client-agnostic |
| Excel import | iOS uploads the `.xlsx` to the **same** endpoint — no client parser |
| Food search | Same authenticated backend proxy — never call OFF/USDA from the device |
| Shared clinical logic | **Ported to Swift** (`MarkerSignals`, `DietProfiles`, `BiomarkerCategories`) so both stay consistent |

### Withings integration — two complementary paths

| Path | How it works | When |
|---|---|---|
| **A. Apple HealthKit bridge** | Withings **Health Mate** writes to Apple Health; the app **reads from HealthKit**. Native, no Withings partner contract, works offline. | **Shipped** (ADR-022) |
| **B. Withings Cloud API** | Backend does OAuth2 with Withings, pulls history via `getmeas`, subscribes to `Notify` webhooks. Full history + server push, no Health Mate required. | **In progress** (ADR-023) — iOS connect flow shipped; backend pending |

Both write into the existing **`body_metrics`** table (with a `source` provenance
column) and a planned `withings_measures` table for richer signals.

### Web route → iOS screen map

| Web route | iOS screen | Tab |
|---|---|---|
| `/` Dashboard | `DashboardView` | **Home** |
| `/biomarkers/[id]` | `BiomarkerDetailView` | push from Home |
| `/panels` | `PanelTimelineView` | push from Home |
| `/import` | `ImportSheet` (document picker → upload) | modal |
| `/food-diary` | `FoodDiaryView` (+ barcode scan) | **Diary** |
| `/meal-plans` | `MealPlanCalendarView` | **Plan** |
| `/body-metrics` | `BodyMetricsView` + Withings sync | **Body** |
| `/account` | `AccountView` (export, delete, settings) | **Settings** |
| `/login` | `AuthView` | pre-auth |

---

## 2. Status

| Phase | Surface | Status |
|---|---|---|
| Foundations | Xcode project, SPM modules, `APIClient`, design system, auth shell | ✅ Shipped |
| Core parity | Dashboard, biomarker detail + clinical signals, Excel import + panels, diet events | ✅ Shipped |
| Food & planning | Food diary, multi-source search, **native barcode scanning** (ADR-019), meal plans & calendar (ADR-020) | ✅ Shipped |
| Body metrics | Log + 3 trend charts + diet-event overlay (ADR-021) | ✅ Shipped |
| Withings — HealthKit (Path A) | Weight + BP via Apple Health, UUID dedupe, background delivery (ADR-022) | ✅ Shipped |
| Withings — Cloud (Path B) | iOS connect/disconnect/"Sync now" flow (ADR-023) | ◐ Client shipped; **backend pending** |
| Doctor PDF report | Client-side selectable A4 report (Sprint 6 follow-up) | ✅ Shipped |
| Account / GDPR / settings | Export + delete UI, settings polish | ☐ Outstanding (Sprint 11) |
| Hardening & release | Offline cache, accessibility, perf, App Store submission | ☐ Outstanding (Sprint 12) |

The submission-blocker detail (including wiring the Account/GDPR UI) is tracked in
[`IOS_APP_STORE_READINESS.md`](IOS_APP_STORE_READINESS.md).

---

## 3. Outstanding backend work (Withings Cloud + extras)

These are the only backend changes the migration still owes. They are what the
shipped iOS Withings-connect flow (§1, Path B) is waiting on:

1. **Body-metric provenance** — `source` (`manual|healthkit|withings`) + external-id
   dedupe on `body_metrics`. ✅ **Done** (`010_body_metrics_source.sql`, ADR-022).
2. **Withings OAuth + webhooks** — `GET /withings/authorize`, `GET /withings/callback`
   (code→token exchange, encrypted per-user token storage, refresh scheduler),
   `POST /withings/notify` (subscription + delta pull), disconnect/revoke. The iOS
   client self-gates until these exist. ☐ **Outstanding** (ADR-023).
3. **Richer Withings metrics** — a `withings_measures` table (RLS on `user_id`) for
   body-fat %, lean mass, resting HR, SpO2, activity/sleep, deduped by Withings
   `grpid`. ☐ **Outstanding**.
4. **(Optional) APNs** — device-token registration + push for sync/reminders. ☐ Stretch.

All new tables follow the existing RLS-on-`user_id` pattern; migrations are numbered
sequentially in `api/supabase/migrations/` and run manually per project convention.

---

## 4. Key risks (still live)

| Risk | Mitigation |
|---|---|
| Withings partner/app approval delay | HealthKit (Path A) already delivers value independently; apply for Withings approval before building Path B. |
| HealthKit background delivery is best-effort | Provide manual "Sync now"; Cloud API webhooks give server-push reliability once shipped. |
| Duplicate readings via HealthKit **and** Withings Cloud | Dedupe on external UUID/`grpid` + timestamp/type/value tolerance; provenance column. |
| HealthKit can't be tested in the Simulator | Mandate device testing; seed Apple Health with sample data. |
| App Review scrutiny on HealthKit + nutrition health claims | Clear usage strings; "visual correlation, not causation" disclaimers retained; no medical-advice claims. |
| EU data residency for Withings cloud data | Keep all persistence in Supabase Frankfurt; document the Withings→backend flow for compliance. |

---

*Cross-cutting rule, unchanged across every sprint: keep the review's intellectual
honesty. Every new number is **decision-support, not medical advice**; with only a
handful of blood draws the app declines to imply causation or statistical significance.*
