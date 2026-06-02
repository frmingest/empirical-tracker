# Empirical Tracker — iOS / Xcode Migration Sprint Plan

> **Goal:** Replicate the full Empirical Tracker web app as a native iOS application
> (Swift / SwiftUI / Xcode), and add **Withings** health-data capture (weight, body
> composition, blood pressure, heart rate, activity, sleep) via Apple HealthKit and
> the Withings Cloud API.
>
> **Audience:** Engineering team executing the migration. Each sprint below is a
> ~2-week increment with concrete deliverables, acceptance criteria, and risks.

---

## 1. Strategic decisions (read first)

### 1.1 Reuse the backend — do **not** rewrite it

The existing **FastAPI + Supabase** backend is platform-agnostic and already does the
hard, clinical, well-tested work: Excel parsing, biomarker categorization, multi-source
food search proxy (Open Food Facts / Matvaretabellen / USDA), clinical-target & trend
logic, GDPR export/erasure, and RLS-enforced data isolation. The iOS app becomes a
**native REST/Supabase client** of that same backend.

| Concern | Web today | iOS approach |
|---|---|---|
| Auth | Supabase JWT (email/password) | `supabase-swift` SDK → same JWT, stored in Keychain |
| Data access | REST calls in `web/src/lib/api.ts` (28 endpoints) | Swift `APIClient` mirroring the same 28 endpoints |
| Row-level security | Supabase RLS on `user_id` | Identical — RLS is enforced in Postgres, client-agnostic |
| Excel import | Server-side parser (`api/app/biomarkers/parser.py`) | iOS uploads the `.xlsx` to the **same** endpoint — no client parser needed |
| Food search | Authenticated backend proxy | Same proxy — never call OFF/USDA directly from device |

**Net effect:** ~70% of business logic is reused unchanged. iOS scope is primarily the
**presentation layer, navigation, charts, native device features, and Withings ingestion.**
Backend changes are limited to: (a) a small number of new endpoints for Withings, and
(b) minor additions to support push/sync.

> ⚠️ One reusable-logic gap to port: a few pieces currently live **client-side** in
> `web/src/lib/` (biomarker categorization, diet profiles, clinical targets, marker
> signal/assessment, diet-event chart projection). These must be re-implemented in Swift
> **or** lifted into the backend as new endpoints so both clients share them. The plan
> recommends **lifting shared clinical logic into the backend** (Sprint 3/8) so the iOS and
> web clients stay consistent and we never maintain the rules twice. See §4.

### 1.2 Withings integration — two complementary paths

| Path | How it works | Pros | Cons | When |
|---|---|---|---|---|
| **A. Apple HealthKit bridge** (recommended first) | User's **Withings Health Mate** app writes to Apple Health; our app **reads from HealthKit**. | Native, no Withings partner contract, works offline, covers weight/body-comp/BP/HR/SpO2/sleep/activity, fastest to ship. | Requires the user to own a device + install Health Mate; data only as fresh as Health Mate's last Apple Health sync; iOS-only. | **Sprint 9** |
| **B. Withings Cloud API** (server-to-server OAuth2 + webhooks) | Backend does OAuth2 with Withings, pulls historical + live data via `getmeas`/`v2/measure`, subscribes to `Notify` webhooks. | Full history on connect, server-pushed updates, works without Health Mate, future Android/web parity. | Requires Withings developer/partner approval, backend OAuth + webhook infra, token refresh. | **Sprint 10** |

Both write into the existing **`body_metrics`** table (weight, BP) and a small set of new
tables for richer Withings signals (body composition, resting HR, etc.). HealthKit-first
de-risks the schedule; the Cloud API adds depth and history.

### 1.3 Target platform & tooling

- **Language / UI:** Swift 6 (strict concurrency) + **SwiftUI**, minimum **iOS 17** (Swift Charts, Observation framework, modern HealthKit APIs). Drop to iOS 16 only if analytics demand it.
- **Charts:** **Swift Charts** (replaces Recharts) — covers sparklines, trend lines, reference bands, target lines, and diet-event overlays.
- **Architecture:** MVVM + lightweight feature modules (one Swift Package per domain mirroring the backend: `Biomarkers`, `DietEvents`, `FoodDiary`, `MealPlans`, `BodyMetrics`, `Account`, `HealthSync`).
- **Networking:** `async/await` `URLSession`, a typed `APIClient`, `Codable` DTOs generated from the backend's response shapes.
- **Auth/session:** `supabase-swift`; tokens in **Keychain**; auto-refresh.
- **Local cache:** SwiftData (or GRDB) for offline-first read cache of biomarkers/results, with background refresh. Optional in early sprints, hardened in Sprint 11.
- **Device features:** `VisionKit`/`AVFoundation` for **barcode scanning** (replaces web barcode input); `UniformTypeIdentifiers` document picker for **`.xlsx` import**; HealthKit for Withings bridge.
- **Localization:** **String Catalogs** (`.xcstrings`) for EN/NO — port `web/src/lib/i18n.ts` (~300 keys).
- **Theming:** SwiftUI semantic colors / asset catalog with light & dark variants (mirror the CSS custom properties).
- **CI/CD:** **Xcode Cloud** (or Fastlane + GitHub Actions) → TestFlight. Unit tests with **Swift Testing**/XCTest, UI tests with XCUITest.
- **Min device support:** iPhone (primary); iPad as a "free" universal target validated in Sprint 12.

### 1.4 Mapping web routes → iOS screens

| Web route | iOS screen | Tab |
|---|---|---|
| `/` Dashboard | `DashboardView` (biomarker grid, category sections, diet filter, flagged toggle) | **Home** |
| `/biomarkers/[id]` | `BiomarkerDetailView` (trend chart, signals, notes, diet events) | push from Home |
| `/panels` | `PanelTimelineView` | push from Home |
| `/import` | `ImportSheet` (document picker → upload) | modal |
| `/food-diary` | `FoodDiaryView` (date nav, meals, totals, search/scan) | **Diary** |
| `/meal-plans` | `MealPlanCalendarView` | **Plan** |
| `/body-metrics` | `BodyMetricsView` (log + 3 charts) + **Withings sync** | **Body** |
| `/account` | `AccountView` (export, delete, settings, language, theme) | **Settings** |
| `/login` | `AuthView` | pre-auth |

Proposed bottom **TabView**: Home · Diary · Plan · Body · Settings.

---

## 2. Cross-cutting requirements (every sprint)

- **TypeScript-strict parity:** Swift is strongly typed; no force-unwraps in shipping code, no `Any` in DTOs.
- **Theme-aware colors only:** no hardcoded hex; use named asset colors mirroring `--bg-card`, `--text-primary`, etc.
- **Accessibility:** Dynamic Type, VoiceOver labels on every interactive element and chart summary, 44pt tap targets, color-blind-safe in/out-of-range cues (icon + color, not color alone).
- **Privacy & compliance:** EU data residency unchanged (Supabase Frankfurt). HealthKit data **never leaves the device** unless the user explicitly enables cloud sync; document this for App Store review. App Privacy "Nutrition Label" + `NSHealthShareUsageDescription` strings required.
- **Security:** Keychain for tokens, ATS enforced (HTTPS only), no secrets in the binary, certificate handling per Apple guidance.
- **Testing gate per sprint:** unit tests for view models + any ported logic must pass; key flows covered by XCUITest; `swiftlint` clean.
- **Definition of Done:** builds in CI, passes tests + lint, runs on a physical device, screens reviewed against the web equivalent, strings localized EN/NO.

---

## 3. Sprint plan

> Each sprint ≈ 2 weeks. Sprints 0–2 are foundational and sequential; 3–8 (feature parity)
> can overlap once the shell exists; 9–10 (Withings) depend on Body Metrics (8); 11–12 are
> hardening/release.

### Sprint 0 — Foundations & project scaffolding
**Objective:** A buildable, CI-wired, signable Xcode project with the module skeleton.

Develop:
- Create the Xcode workspace; Swift Package per feature domain; shared `Core` package (networking, design system, models).
- Bundle ID, App Group, signing, provisioning; register App ID with **HealthKit** capability reserved (used later).
- `APIClient` skeleton: base URL config (dev/staging/prod), async request layer, auth header injection, error model, retry/backoff for transient failures.
- `Codable` DTOs for the first domains (biomarkers/results) generated from the live API responses; a contract snapshot test against the running backend.
- Design system: color assets (light/dark) mirroring CSS custom properties; typography scale; reusable components (`Card`, `StatusBadge`, `SegmentedControl`, `EmptyState`, `LoadingState`).
- CI/CD: Xcode Cloud (or Fastlane+Actions) building on push; TestFlight internal lane; SwiftLint + test gate.
- Localization plumbing: String Catalog with EN/NO, language-override setting stub.

Acceptance:
- App launches to a placeholder TabView on device & simulator; CI green; lint clean; one DTO contract test passing.

Risks: signing/provisioning friction → resolve Apple Developer team access on day 1.

---

### Sprint 1 — Authentication, session & app shell
**Objective:** Real login against Supabase and the navigational skeleton.

Develop:
- Integrate `supabase-swift`; email/password sign-in mirroring `/login`; session restore; sign-out.
- **Keychain** token storage; silent refresh; 401 → re-auth flow; "demo / signed-out" mode using mock data (port `mockData.ts`) so the app is explorable without an account.
- `AuthContext` equivalent (`@Observable AuthStore`) injected app-wide; route gating (authed TabView vs `AuthView`).
- Bottom **TabView** (Home · Diary · Plan · Body · Settings) with empty destination screens.
- Global Settings scaffold: **language toggle (EN/NO)** and **light/dark/system theme** wired to real providers and persisted (UserDefaults).
- Networking hardened: inject `Authorization: Bearer` on every call; map backend error envelopes to user-facing messages.

Acceptance:
- User signs in, session persists across launches, signs out; theme + language toggles work app-wide; demo mode renders mock dashboard.

---

### Sprint 2 — Dashboard & biomarker grid (read path)
**Objective:** Faithful replica of the home dashboard — the app's centerpiece.

Develop:
- `GET /biomarkers/results` integration → time-series per marker.
- **Biomarker categorization** (Lipids, CBC, Metabolic, Thyroid, Renal, Liver, Nutrients, Electrolytes, Other). Port `biomarkerCategories.ts` rules to Swift **or** consume a new backend `/biomarkers/categorized` endpoint (decide in §4; recommend backend).
- `CategorySection` + `BiomarkerCard`: latest value, unit, **in-range/out-of-range/Watch** `StatusBadge`, and a **Swift Charts sparkline** (recent points).
- **Diet-focus filter** (All / Carnivore / Low-carb / Fasting / Custom) — port `dietProfiles.ts` marker visibility; "Custom" opens a marker-picker sheet (`CustomMarkerModal` equivalent).
- **"Flagged only"** toggle (out-of-range or Watch).
- Header actions: Import (Sprint 4 sheet), Settings.
- Pull-to-refresh; skeleton loading; empty state ("Import your first blood test").
- Persist diet focus via `GET/PUT /settings` (and localStorage-equivalent in demo mode).

Acceptance:
- Dashboard matches web grouping, filtering, and status logic on real data; diet filter + flagged toggle behave identically; VoiceOver reads each card's value/status/trend.

---

### Sprint 3 — Biomarker detail, trend charts & clinical signals
**Objective:** The marker detail experience with full charting and assessment.

Develop:
- `BiomarkerDetailView`: full **Swift Charts** trend (date × value) with **reference-range band**, **clinical target line** (LDL/non-HDL/total-chol/TG/HbA1c), and point markers.
- **Diet-event overlay** on the chart: shaded periods + dashed single-date markers; port `chartAnnotations.ts` axis projection.
- **Trend signals & assessment** (large step ≥50%, notable ≥25%, trending-toward-bound, "Watch" status): port `markerSignals.ts` → `MarkerSignals` panel.
- **Confounder notes** (eGFR, HbA1c, ferritin) EN/NO: port `markerNotes.ts` → `MarkerNote` panel.
- **Manual result entry** sheet → `POST /biomarkers/results/manual`.
- Inline **diet-event manager** entry point (full CRUD in Sprint 5).
- **Recommended backend lift:** expose clinical targets, signal assessment, and category mapping as endpoints/fields so iOS + web share one source of truth (see §4). If lifted, this sprint consumes them instead of porting.

Acceptance:
- Detail chart visually matches web (band, target, overlays); signals/notes/targets identical to web for the same data; manual entry persists and refreshes the chart.

---

### Sprint 4 — Excel import, panels timeline & manual data
**Objective:** Get real data into the app on-device.

Develop:
- **Import sheet:** `UIDocumentPicker` (UTType `.xlsx`) → multipart upload to **`POST /biomarkers/import`** (reuse server parser — no client parsing). Progress + result summary (panels created / results inserted). Errors surfaced clearly (wrong format, etc.).
- Optional Files/AirDrop/share-sheet entry point so a `.xlsx` emailed to the phone can be imported.
- **Panel timeline** (`GET` panels): chronological draws with per-panel summary (total / in-range / out-of-range, names of flagged markers).
- Delete a panel / delete-all (`DELETE /biomarkers/import/{panel_id}` and `/import`) with confirmation.
- Wire import success → dashboard refresh.

Acceptance:
- A real Norwegian `.xlsx` imports end-to-end on device (decimal commas, dates handled server-side); panel timeline matches web; deletes work with undo-safe confirmation.

---

### Sprint 5 — Diet events / correlation overlay (full CRUD)
**Objective:** Account-wide regimen annotations that overlay every chart.

Develop:
- `DietEventManager` screen + sheet: list / add / delete (`GET/POST/DELETE /diet-events`) with label, **kind** (diet/fast/supplement/medication/lifestyle/other), `started_on`, optional `ended_on`, note.
- Date validation (`ended_on ≥ started_on`); point vs period semantics.
- Shared overlay model consumed by biomarker **and** body-metric charts (Sprint 8).
- "Visual correlation only, not causation" disclaimer, matching web copy.

Acceptance:
- Creating/editing/deleting an event updates overlays across all charts; matches web behavior and disclaimers.

---

### Sprint 6 — Food diary + multi-source search + barcode scanning
**Objective:** Daily food logging with native scanning.

Develop:
- `FoodDiaryView`: date navigator, meals grouped (breakfast/lunch/dinner/snack/other), per-entry **source badge** (OFF/MVT/USDA), delete.
- **Daily totals:** energy, carbs, protein, fat, **sodium (mg)**, **saturated fat (g)** — compute from entries.
- **Multi-source search** via `GET /food-diary/search?source=off|mvt|usda|all` with a `FoodSourceSelect`; results list; quantity entry; per-100g × grams scaling (mirror server/web rules).
- **Native barcode scanning** (`VisionKit`/`AVFoundation`) → `GET /food-diary/barcode/{barcode}` (OFF) → prefill entry. **Replaces** the web's manual barcode field — a headline native upgrade.
- Free-text entry when no match; `POST /food-diary`; missing nutrients shown as "—" (never estimated).
- Camera permission flow + graceful fallback to manual search.

Acceptance:
- Log via search, scan, and free-text; totals match web math incl. sodium/sat-fat; source selection + badges correct; scanning works on device.

---

### Sprint 7 — Meal plans & calendar
**Objective:** Weekly meal-prep planning.

Develop:
- `MealPlanCalendarView`: Monday→Sunday week, multi-week navigation, per-day energy total.
- Named **plans** CRUD (`GET/POST/DELETE /meal-plans`); filter calendar by plan.
- Schedule meals (`POST /meal-plans/calendar`) reusing the Sprint 6 search/scan/free-text picker; **mark done/undone** (`PATCH`); delete (`DELETE`).
- **"Log to diary"**: copy a planned meal into the food diary as done.
- Plan-delete keeps meals (SET NULL semantics), meal-delete keeps plan — match web.

Acceptance:
- Full plan + calendar parity with web (week boundaries, totals, done toggles, plan filtering, log-to-diary).

---

### Sprint 8 — Body metrics (foundation for Withings)
**Objective:** Manual weight / waist / blood-pressure tracking with charts.

Develop:
- `BodyMetricsView`: log form with constraints — **at least one** of weight/waist/systolic; **BP both-or-neither**; ranges (systolic 40–300, diastolic 20–200, weight/waist > 0).
- Three **Swift Charts** trend charts (weight kg, waist cm, BP mmHg) sharing the **diet-event overlay**; guideline line at **120/80** (neutral reference, not a verdict).
- CRUD via `GET/POST/DELETE /body-metrics`; delete with confirmation.
- **Source attribution field**: extend the body-metric model to record provenance (`manual` | `healthkit` | `withings`) so Sprints 9–10 can distinguish synced vs manual entries. *(Requires a small backend migration — see §4.)*

Acceptance:
- Manual logging + 3 charts match web; constraints enforced client- and server-side; provenance field present and defaulting to `manual`.

---

### Sprint 9 — Withings via Apple HealthKit (primary integration)
**Objective:** Pull Withings data into the app through Apple Health, zero Withings contract required.

> **Status (shipped — see [ADR-022](../docs/adr/022-ios-healthkit-withings-sync.md)):**
> The HealthKit bridge imports **weight + blood pressure** (the signals that map to the
> existing `body_metrics` columns), tagged `source: healthkit`, with client-side
> sample-UUID dedupe, connect/sync/disconnect UX, per-type toggles, and `HKObserverQuery`
> background delivery. **Deferred to Sprint 10's backend work (§4.3):** body-fat %, lean
> mass, resting HR — they have nowhere to land until the `withings_measures` table exists,
> so we request authorization only for what we can store. On-device acceptance testing is
> folded into the Sprint 12 QA matrix (HealthKit has no Simulator data).

Develop:
- Add **HealthKit** capability; request **read** authorization for: body mass, body fat %, lean body mass, BMI, **blood pressure (systolic/diastolic)**, resting/standard heart rate, height, plus (optional) steps, active energy, sleep, SpO2. `NSHealthShareUsageDescription` copy explaining the carnivore/biomarker use-case.
- `HealthSync` module: query `HKSampleQuery` for historical samples and register **`HKObserverQuery` + background delivery** for new samples while Health Mate syncs Withings data into Apple Health.
- **Mapping & dedupe:** map HealthKit samples → `body_metrics` rows (weight → `weight_kg`, BP pair → `systolic`/`diastolic`), tagging provenance `healthkit` and storing the HealthKit UUID to prevent duplicate inserts on re-sync. Unit conversion (lb→kg if needed) and timezone-correct `measured_on`.
- **Sync UX** in `BodyMetricsView`: "Connect Apple Health" CTA, permission state, last-sync timestamp, manual "Sync now", and clear labeling of HealthKit-sourced rows. Respect the rule that HealthKit data stays on-device unless the user opts into pushing it to the backend.
- Settings: granular toggles per data type; disconnect/revoke guidance.
- Extra body-composition metrics (fat %, lean mass, resting HR) surfaced as additional optional charts (new lightweight table or extend `body_metrics`; see §4).

Acceptance:
- With Withings Health Mate installed and sharing to Apple Health, the app imports historical weight + BP and receives new readings in the background; no duplicates; provenance visible; works with permissions partially granted.

Risks: background delivery scheduling is best-effort (document expectations); users without Health Mate need Path B (Sprint 10). HealthKit cannot run in the Simulator for real data → test on device.

---

### Sprint 10 — Withings Cloud API (server-to-server) + webhooks
**Objective:** Direct Withings account connection for full history and server-pushed updates, independent of HealthKit.

> **Status (iOS slice shipped — see [ADR-023](../docs/adr/023-ios-withings-cloud-connection.md)):**
> The **on-device connection flow** is built: "Connect Withings account" opens the OAuth
> consent page in `ASWebAuthenticationSession` (custom scheme `empiricaltracker://withings`),
> with connection status, last-sync, "Sync now", and disconnect surfaced on the Body tab and
> in Settings ▸ Devices. No Withings tokens touch the device. The client **self-gates on
> `GET /withings/connection`** — it stays hidden until the backend exposes the `/withings/*`
> endpoints, then activates with no further app release. **Outstanding (all backend, §4.2–§4.4):**
> the OAuth token exchange/refresh, the `getmeas` history pull, the `Notify` webhooks, the
> `withings_measures` table for richer signals, and the `external_id` dedupe that reconciles
> the HealthKit and Cloud paths. On-device acceptance is folded into the Sprint 12 QA matrix.

Backend (FastAPI) develop:
- Register a **Withings developer application**; store client ID/secret in backend config (never in the app).
- **OAuth2 flow:** `GET /withings/authorize` (returns Withings consent URL with scopes `user.info,user.metrics,user.activity`) and `GET /withings/callback` (30-second code→token exchange; persist access+refresh tokens per user, encrypted).
- **Token refresh** scheduler; revoke/disconnect endpoint.
- **Data pull:** `getmeas` (weight, fat mass/ratio, lean mass, **BP systolic/diastolic**, heart rate, SpO2, temperature) and `v2/measure getactivity` (steps/energy) and optionally Sleep v2; normalize into `body_metrics` + new `withings_measures` table; provenance `withings`, dedupe by Withings `grpid`.
- **Webhooks:** `POST /withings/notify` subscription (`Notify` API) so Withings pushes new measurements; on receipt, pull deltas via the Last-Update system. Verify webhook authenticity.
- Reconcile with HealthKit data (avoid double-counting the same reading arriving via both paths — dedupe on timestamp+type+value with a tolerance).

iOS develop:
- "Connect Withings account" in Settings/Body → opens the OAuth consent URL in `ASWebAuthenticationSession`; handle the redirect; show connection status + last sync; disconnect.
- Surface the richer Withings metrics (body composition, activity, sleep summaries) as optional charts/cards.

Acceptance:
- A user connects their Withings account, full history imports server-side, and a new device reading appears in-app via webhook without manual refresh; HealthKit + Cloud paths don't duplicate; disconnect revokes tokens.

Risks: Withings partner/app approval lead time → **start the application during Sprint 8**. Webhook URL must be publicly reachable (Railway) and exactly matched.

---

### Sprint 11 — Account, GDPR, settings, i18n & theming polish
**Objective:** Compliance parity and finish the cross-cutting layer.

Develop:
- `AccountView`: **GDPR export** (`GET /account/export?format=json|csv`) → save/share via share sheet; **account deletion** (`DELETE /account`) with a type-to-confirm ("DELETE") danger flow.
- Settings completeness: diet focus, custom markers, **EN/NO** language, **light/dark/system** theme, HealthKit + Withings connection management, units preference if needed.
- Finish localization: full String Catalog audit (all ~300 keys), category tooltips EN/NO, pluralization/number/date formatting via `Locale` (Norwegian decimal display).
- **Offline cache** hardening: SwiftData read-cache for biomarkers/results/body-metrics so the app opens instantly and tolerates flaky networks; background refresh.
- App Privacy details, HealthKit usage strings, data-handling disclosures finalized.
- Optional: **push notifications** (e.g., "new Withings reading synced", "time to log") — requires backend APNs; scope as stretch.

Acceptance:
- Export + delete match web semantics; every screen fully localized EN/NO and theme-correct; app usable offline for reads; privacy disclosures complete.

---

### Sprint 12 — Hardening, accessibility, performance & App Store release
**Objective:** Ship-quality build through TestFlight to the App Store.

Develop:
- **Accessibility pass:** VoiceOver across all flows, chart audio/Accessibility descriptions, Dynamic Type at largest sizes, contrast + color-blind cues.
- **Performance:** large-dataset profiling (many panels/markers), chart rendering, memory, cold-start; image/asset optimization.
- **iPad / universal** layout validation; landscape; Split View sanity.
- **Security review:** Keychain usage, ATS, token lifecycle, HealthKit data-flow audit, dependency scan.
- **QA matrix:** device/OS matrix, permission-denied paths (camera, HealthKit), error/empty/loading states, deep links from share sheet.
- **Release engineering:** App Store Connect metadata, screenshots, privacy nutrition label, **HealthKit App Review** justification, TestFlight beta → external testers → submission.
- Crash/analytics (privacy-respecting) wired; rollback/versioning plan.

Acceptance:
- TestFlight beta passes; App Review submission accepted (incl. HealthKit justification); crash-free sessions > target; full feature parity with web validated screen-by-screen.

---

## 4. Backend work items (small, but required)

These are the only backend changes the migration introduces. Recommend doing 4.1–4.3 as a
"shared-logic lift" so iOS and web never diverge:

1. **(Sprint 3) Clinical-logic endpoints/fields** — expose categorization, clinical targets, and marker signal/assessment results from the API (today they live in `web/src/lib/*`). Lets both clients render identical statuses without duplicated rules. *Alternative:* port to Swift and keep web as-is (faster now, two code paths to maintain later).
2. **(Sprint 8) Body-metric provenance** — migration adding `source` (`manual|healthkit|withings`) and an external-id/dedupe column to `body_metrics`. *Status: `source` shipped (ADR-017/021) and now written by the HealthKit path (ADR-022). The `external_id` server-side dedupe column is still outstanding — Sprint 9 dedupes client-side by HealthKit sample UUID; the server column is needed before the Cloud path (Sprint 10) can also dedupe.*
3. **(Sprint 9/10) Richer Withings metrics** — `withings_measures` (or extended `body_metrics`) for body fat %, lean mass, resting HR, SpO2, activity/sleep summaries, with RLS on `user_id`. *Status: outstanding. Blocks surfacing the extra HealthKit/Withings body-composition signals; iOS Sprints 9 (ADR-022) and 10 (ADR-023) ship weight + BP only for this reason.*
4. **(Sprint 10) Withings OAuth + webhooks** — `/withings/authorize`, `/withings/callback`, `/withings/notify`, `/withings/connection`, `/withings/sync`, token storage (encrypted), refresh scheduler, disconnect. *Status: backend outstanding. The **iOS** client for these endpoints is built and self-gated (ADR-023) — it consumes `/withings/authorize`, `/withings/connection`, `/withings/sync`, and `DELETE /withings/connection`, and lights up automatically once they deploy.*
5. **(Sprint 11, optional) APNs** — device-token registration + push send for sync/reminders.

All new tables follow the existing RLS-on-`user_id` pattern; all migrations are numbered
sequentially in `api/supabase/migrations/` and run manually per project convention.

---

## 5. Dependency & sequencing map

```
0 → 1 → 2 → 3
            ├→ 4  (import/panels)
            ├→ 5  (diet events)        [3 and 5 feed all charts]
            ├→ 6 → 7  (diary → plans)
            └→ 8  (body metrics) → 9  (HealthKit)
                                  → 10 (Withings Cloud)   [start Withings app approval @ Sprint 8]
                                              ↓
                                        11 (GDPR/i18n/offline) → 12 (release)
```

- **Critical path:** 0→1→2→3→8→9/10→11→12.
- **Parallelizable once shell exists (after Sprint 2):** the 4/5 and 6/7 tracks can run on separate devs.
- **Long-lead item:** Withings developer/partner approval — **submit during Sprint 8**.

## 6. Effort & timeline summary

| Phase | Sprints | Calendar (2-wk sprints) |
|---|---|---|
| Foundation (project, auth, shell) | 0–1 | ~1 month |
| Core parity (dashboard, detail, import, events) | 2–5 | ~2 months |
| Food & planning (diary, scanning, calendar) | 6–7 | ~1 month |
| Body & Withings (metrics, HealthKit, Cloud API) | 8–10 | ~1.5 months |
| Compliance & release (GDPR, i18n, hardening, App Store) | 11–12 | ~1 month |
| **Total** | **0–12** | **~6.5 months** (single iOS pod; faster with the parallel tracks above) |

## 7. Key risks & mitigations

| Risk | Mitigation |
|---|---|
| Withings partner approval delay | Apply at Sprint 8; HealthKit (Sprint 9) ships value independently of approval. |
| HealthKit background delivery is best-effort | Provide manual "Sync now"; set user expectations; Cloud API webhooks (Sprint 10) give server-push reliability. |
| Duplicate readings via HealthKit **and** Withings Cloud | Dedupe on external UUID/`grpid` + timestamp/type/value tolerance; provenance column. |
| Shared clinical logic drifting between iOS and web | Lift categorization/targets/signals into backend endpoints (§4.1). |
| HealthKit can't be tested in Simulator | Mandate device testing in Sprints 9/12; seed Apple Health with sample data. |
| App Review scrutiny on HealthKit + nutrition health claims | Clear usage strings, "visual correlation, not causation" disclaimers retained, no medical-advice claims. |
| EU data residency for Withings cloud data | Keep all persistence in Supabase Frankfurt; document the Withings→backend data flow for compliance. |

---

*This plan reuses the existing FastAPI + Supabase backend, replicates 100% of current web
feature surface in native SwiftUI, and adds Withings capture via both Apple HealthKit and
the Withings Cloud API. Adjust sprint boundaries to team size; the dependency map (§5) is
the contract that matters.*
