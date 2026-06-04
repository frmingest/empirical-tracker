# Empirical Tracker — Solution Documentation

> Plain-language explanation of what this app is, how it works, and why it's built
> the way it is. For the engineering execution history see
> [`IOS_MIGRATION_PLAN.md`](IOS_MIGRATION_PLAN.md); for individual decisions see
> [`adr/`](adr/) (the canonical Architectural Decision Records).

---

## What the app is

Empirical Tracker is a **decision-support** tool for people running deliberate
dietary regimens — carnivore, low-carb, fasting — who want to see how those
regimens move their **blood biomarkers** and their **body's headline signals**
over time. It is explicitly **not** medical advice: every marker, correlation,
and diet note carries a clinician-review disclaimer, and the app never interprets
a value or sets a clinical recommendation on the user's behalf.

When you get a blood panel back from the lab you get a PDF or Excel file with a
column of numbers; to understand trends you have to manually compare this month's
file to last year's. Empirical Tracker imports those files and builds the
"here is your LDL over the last three years" view automatically — then correlates
it with what you eat and how your body responds.

The product has three data surfaces, all correlated on a shared timeline:

1. **Biomarkers** — imported from lab `.xlsx` files, categorized, and charted with
   reference bands, clinical-target lines, and within-range trend signals.
2. **Food diary** — daily logging from three nutrition databases, with macros,
   sodium, and saturated fat; barcode scanning on device.
3. **Body metrics** — weight, waist, and blood pressure, plus Withings data via
   Apple HealthKit and (in progress) the Withings Cloud API.

**Diet events** annotate every chart so the user can see *visual correlation*
(never claimed causation) between a regimen change and a marker's movement.

---

## What the system is made of

### The backend (the "API")

A platform-agnostic **Python + FastAPI** service that owns all the hard, clinical,
well-tested work: Excel parsing (Norwegian number formats, reference ranges),
biomarker categorization, the multi-source food-search proxy, clinical-target and
trend logic, and GDPR export/erasure. It receives blood-test files, saves results,
and answers questions from the client (like "give me all my HDL readings").

### The iOS app (the "client")

A native **Swift / SwiftUI** app (Xcode 15+) that is the **only** client of the
backend. It re-implements the presentation layer, navigation, and charts, and adds
native-device features the backend can't provide: barcode scanning, on-device
`.xlsx` import, and Apple HealthKit / Withings capture.

- **Architecture:** MVVM with one **Swift Package per domain** behind a thin app
  target — `Core` (networking, design system, models), `Auth`, `Biomarkers`,
  `DietEvents`, `FoodDiary`, `MealPlans`, `BodyMetrics`, `HealthSync`, `Account`.
- **Networking:** a typed actor-based `APIClient` (`async/await` `URLSession`) with
  retry/backoff, `Codable` DTOs, and `Authorization: Bearer` injection on every call.
- **Auth/session:** `supabase-swift` → the same Supabase JWT, stored in the
  **Keychain**, with silent refresh.
- **Charts:** **Swift Charts** throughout (sparklines, trend lines, reference bands,
  target lines, diet-event overlays).
- **Shared clinical logic** is **ported to Swift** (`MarkerSignals`, `DietProfiles`,
  `BiomarkerCategories`) so the app renders identical Watch / in-range / out-of-range
  assessments without a network round-trip.

> **Retired:** the original client was a **Next.js / React web app**. It has been
> removed from the repository (`chore: retire Next.js web app — iOS + Railway/
> Supabase only`). Decision records authored against it (ADR-008 through ADR-018)
> remain as historical records and carry "iOS note" banners where the native client
> re-sequences or re-implements that surface; ADR-019 onward are iOS-native.

### The database

All data is stored in a **Supabase** (managed Postgres) database with row-level
security, hosted in the **EU (Frankfurt)** region.

### Where it runs

The API deploys to **Railway**, which watches the GitHub repository and
auto-redeploys on push to `main`. The iOS app ships through **Xcode → TestFlight →
App Store**. See [`SETUP.md`](SETUP.md) for one-time backend account setup and
[`CONFIGURATION.md`](CONFIGURATION.md) for verifying the app is wired to the right
backend.

---

## How your blood-test data flows through the system

1. **You get a blood panel** from the lab as an Excel file (`.xlsx`).
2. **You import it** in the app via a `UIDocumentPicker` (or the Files / share
   sheet), which uploads the file to `POST /biomarkers/import` — there is **no
   client-side parser**; the proven server parser does the work.
3. **The API parses each row**, handling Norwegian decimal commas (`4,3` → `4.3`),
   reference ranges (`4,5 - 5,8` → low 4.5, high 5.8, bounded; `<42` → less-than),
   and computes whether each value is in range.
4. **The data is saved** to the biomarker tables (below).
5. **The dashboard refreshes**, fetching results from the API and drawing the
   categorized grid and charts with Swift Charts.

---

## The database structure

The blood-test core is three tables, with user preferences and the later feature
surfaces added alongside. **Every row in every table has a `user_id` column**, and
row-level security enforces isolation in Postgres itself.

```
biomarkers     What is being measured       "P-HDL-kolesterol | ref 0.9–2.0 | bounded"
panels         When a blood draw happened    "tested_at 2026-05-22 | source xlsx_import"
results        The actual measurement        "HDL | May 2026 | 1.3 | in_range true"
user_settings  Dashboard preferences         "diet carnivore | custom_markers [...]"
```

Added by later sprints / ADRs:

```
diet_events    Regimen-change annotations    "Started carnivore | kind diet | 2024-05-31"   (ADR-010)
food_entries   What you ate each day         "2026-05-31 | dinner | Ribeye | 728 kcal"       (ADR-011)
meal_plans     A named, reusable plan        "Carnivore week | High-protein, zero-carb"      (ADR-012)
planned_meals  A meal scheduled on a day      "2026-06-02 | dinner | Ribeye | done false"    (ADR-012)
body_metrics   A body measurement on a day    "2026-05-22 | 83.1 kg | 90 cm | BP 122/79"     (ADR-017)
```

Schema evolutions worth knowing (all in `api/supabase/migrations/`):

- **`007_sodium_saturated_fat.sql`** — sodium + saturated-fat columns on
  `food_entries` *and* `planned_meals` (ADR-016).
- **`009_food_source.sql`** — a `source` provenance column on food rows (ADR-018).
- **`010_body_metrics_source.sql`** — a `source` provenance column on `body_metrics`
  (`manual | healthkit | withings`) plus an external-id dedupe key, so HealthKit/
  Withings syncs never double-insert (ADR-022).

---

## Security and privacy

Blood-test data is GDPR special-category health data; the app is designed around it:

- **Row-Level Security (RLS):** a database rule that a user can only read/write rows
  where `user_id` matches their own ID. The API enforces it on the live data path by
  querying Postgres **as the user** — each request builds a Supabase client scoped to
  the caller's JWT, so RLS holds even if application code forgot a `user_id` filter
  (ADR-026). The service-role key (which bypasses RLS) is reserved for one audited
  admin operation: account erasure.
- **EU data storage:** the Supabase database runs in Frankfurt; health data never
  leaves the EU. HealthKit data stays **on device** unless the user explicitly enables
  sync to the backend.
- **Server-side keys:** the RLS-bypassing service-role key exists only on the server
  (a Railway env var) and is used only for account erasure. The API also holds the
  public **anon key** (the same one the app ships) to build per-request, JWT-scoped
  clients for all ordinary data access.
- **Keychain + JWT:** the iOS app stores its short-lived Supabase JWT in the Keychain;
  every API request carries it and the API verifies it before touching any data.

---

## The biomarker categories

Imported markers are grouped into eight categories (a marker appears whenever your
import — or the demo data — contains it):

| Category | What it tracks |
|----------|---------------|
| **Lipids** | Cholesterol (HDL, LDL, Total, non-HDL), Triglycerides, and particle markers (ApoB, Lp(a)) |
| **CBC** | Blood cell counts (Hemoglobin, RBC, WBC, Hematocrit, MCV, MCH, MCHC) |
| **Metabolic** | Blood-sugar control (HbA1c) and uric acid |
| **Thyroid** | Thyroid function (TSH, Free T4) |
| **Renal** | Kidney function (Creatinine, eGFR) |
| **Liver** | Liver enzymes (ALT, GGT) |
| **Nutrients** | Vitamins and minerals (Ferritin, B12, Active B12, Vitamin D, Folate, Iron, Transferrin, Homocysteine, MMA) |
| **Electrolytes** | Sodium, Potassium, Magnesium, Phosphate |

The categorization rules live in `ios/Packages/Biomarkers/Sources/Biomarkers/BiomarkerCategories.swift`.

---

## Diet focus

The dashboard's **Diet focus** control hides biomarkers that aren't clinically
informative for the chosen eating pattern, so the user sees a focused view:

| Focus | Shows |
|-------|-------|
| **All** | Every biomarker |
| **Carnivore** | Lipids, iron studies, renal/liver load, electrolytes, B-vitamin/folate status, HbA1c, Hgb/Hct |
| **Low carb** | HbA1c, full lipid panel, liver enzymes, electrolytes, ferritin |
| **Fasting** | Electrolytes (incl. refeeding Mg/phosphate), glucose, kidney/liver, hydration-sensitive blood counts, lipids |
| **Custom** | Any markers hand-picked |

The clinical reasoning is in [`DIET_BIOMARKERS.md`](DIET_BIOMARKERS.md); the rules
live in `ios/Packages/Biomarkers/Sources/Biomarkers/DietProfiles.swift`. The choice
is saved per user (in `user_settings` when signed in, or `UserDefaults` in the demo
view). Custom selections are stored by biomarker **name**, so they survive re-imports.

---

## Feature surfaces

### Biomarker detail, clinical targets & trend signals (ADR-014)

Each marker's detail page draws a full Swift Charts trend with the **reference-range
band**, a distinct amber **clinical-target line** (for LDL, non-HDL, total cholesterol,
triglycerides, HbA1c), and point markers. The lab reference range is a *population
interval, not a verdict of "healthy"* — so a value can sit inside the lab range yet at
or above its clinical target, in which case the marker reads **"Watch"** (amber) rather
than green. The app also surfaces **within-range trend signals**: a large step between
draws (≥ 50%, so any doubling trips it), a notable step (≥ 25%), and values near a
reference bound. A single `assessMarker()` combines the range flag, target check, and
trend signals into one status; the green flag never overrides a flagged trend.

### Confounder notes (ADR-015)

eGFR, HbA1c, and ferritin each carry a plain-language detail-page note explaining why
the diet itself can move the number (creatinine-based eGFR depressed by meat/muscle;
HbA1c read high from longer red-cell lifespan on keto; ferritin an acute-phase reactant).

### Correlation overlay — diet events (ADR-010)

Account-wide **diet events** (the day you started carnivore, a supplement, a
medication, a multi-day fast) are drawn on top of every biomarker **and** body-metric
chart — a dashed marker line for a single date, a shaded period for a range. The
honesty caveat is built in: annotations are *snapped to the nearest blood draw*, so
their position is approximate, and a marker moving near an annotation **does not prove
cause and effect**. Served by `GET/POST/DELETE /diet-events`.

### Food diary + multi-source search + barcode scanning (ADR-011, 016, 018, 019)

Daily food logging from **three** nutrition databases — **Matvaretabellen** (Norwegian
whole foods), **USDA FoodData Central** (US whole + branded), and **Open Food Facts**
(branded/barcode) — chosen via a source selector, each entry carrying a provenance
badge. The diary stores the **amounts actually consumed** (`per-100 g × grams / 100`)
for energy, carbs, protein, fat, **saturated fat (g)**, and **sodium (mg)**, so it stays
correct even if upstream data later changes. Nutrition is taken **as published** — never
invented; missing values show "—". Native **barcode scanning** (`VisionKit`) replaces the
web's manual barcode field. Sourcing and accuracy limits: [`NUTRITION_DATA.md`](NUTRITION_DATA.md).
All third-party data is reached through the authenticated **backend proxy** — never
called directly from the device.

### Meal plans & calendar (ADR-012, 020)

The forward-looking half of the diary: a Monday→Sunday **week calendar** with per-day
energy totals, **named plans** that group scheduled meals, and a **"Log to diary"**
action that copies a planned meal into the diary for its date. Deleting a plan keeps its
meals; deleting a meal keeps the plan.

### Body metrics + Withings (ADR-017, 021, 022, 023)

A Body tab logs **weight (kg)**, **waist (cm)**, and **blood pressure (mmHg)** on any
date (every metric optional; BP is a both-or-neither pair; a row needs at least one
metric). Each gets a Swift Charts trend on the shared timeline, carrying the same
diet-event overlay; the BP chart draws faint **guideline** lines at 120/80 (a neutral
population reference, *not* a clinical-target line or personalised verdict).

- **Apple HealthKit bridge (ADR-022):** with Withings Health Mate writing to Apple
  Health, the app reads **weight and blood pressure**, tags them `source: healthkit`,
  and dedupes by sample UUID via `HKObserverQuery` background delivery.
- **Withings Cloud connect (ADR-023):** "Connect Withings account" opens the OAuth
  consent page in `ASWebAuthenticationSession`. **No Withings tokens touch the device** —
  the backend owns the token exchange and webhooks. The client **self-hides until the
  backend exposes the `/withings/*` endpoints**, activating automatically when that work
  deploys.

### Data export & account deletion (ADR-013)

The two GDPR rights that matter most over health data exist as backend endpoints:
**export everything** (`GET /account/export`, JSON or a CSV-per-table zip) and
**delete your account** (`DELETE /account`, child-first then auth user). The API also
sends baseline **security headers** (CSP, `X-Frame-Options`, `nosniff`, HSTS,
`Referrer-Policy`). Surfacing these in the iOS **Account/Settings** UI is the Sprint 11
slice and is flagged as an App Store submission blocker in
[`IOS_APP_STORE_READINESS.md`](IOS_APP_STORE_READINESS.md).

### Doctor PDF report (Sprint 6 follow-up — shipped on iOS)

A **selectable, printable A4 PDF report** for sharing with a clinician (Mail, AirDrop,
Files via the system share sheet) — no doctor login or multi-tenant RLS required. The
user picks whole categories and/or individual markers and chooses **latest values**,
**trend graphs**, or both. Rendered **client-side** via SwiftUI `ImageRenderer` →
`CGContext` (no new dependency, works offline, reuses the in-app chart). It carries the
same disclaimers: a cover note and a "decision-support, not medical advice" footer on
every page. Lives in `ios/EmpiricalTracker/Features/ReportShare/`.

---

## Clinical-feedback roadmap

A clinical review of the app (diet & nutrition lens) surfaced a cluster of findings: the
product treated the lab **reference range** as if it meant **healthy**, omitted several
of the *most* informative markers and nutrients for its target diets, and tracked some
diet-confounded markers without that caveat. The findings were triaged by severity and
addressed across a sequence of ADRs.

| # | Finding | Severity | Decision record | Status |
|---|---------|----------|-----------------|--------|
| 1 | "In range" hides "above clinical target" (e.g. LDL green at 4.1 mmol/L); "in range" also hides a sharp within-range trend (e.g. ALT 25→55 U/L). | High | [ADR-014](adr/014-clinical-targets-trend-signals.md) — clinical-target layer + trend signals | Shipped |
| 2 | High-yield markers absent (refeeding electrolytes, ApoB, Lp(a), uric acid, triglycerides); two diet profiles list markers they don't carry; some tracked markers are diet-confounded yet shown without a caveat. | High | [ADR-015](adr/015-panel-expansion-confounder-notes.md) — panel expansion + confounder notes | Shipped (High slice); derived ratios deferred |
| 3 | The diary omitted the two nutrients the biomarker side cares about most — **sodium** (electrolytes / blood pressure) and **saturated fat** (LDL response); energy showed "—" when only kJ was published. | High / Low | [ADR-016](adr/016-food-diary-sodium-saturated-fat.md) — sodium & saturated fat + kJ→kcal fallback | Shipped |
| 4 | Open Food Facts is a branded/barcode database and is weakest on the **whole foods** these diets live on. | Medium | [ADR-018](adr/018-whole-foods-data-sources.md) — Matvaretabellen + USDA whole-food sources | Shipped (macros, Phases 1–2); micronutrients deferred |
| 5 | For diet tracking, **weight, waist, and blood pressure** respond faster and often matter more than most labs, yet the app held no body metrics. | Medium | [ADR-017](adr/017-body-metrics.md) — body metrics + longitudinal context | Shipped |

### Deferred follow-ups (tracked, not yet built)

- **Derived ratios** — TG/HDL and AST:ALT in a dedicated "Derived — calculated, not
  measured" section (ADR-015).
- **Further markers** — fasting insulin / C-peptide, fasting glucose, hs-CRP, AST/ASAT
  (ADR-015).
- **Daily intake targets / needs**, including **protein in g/kg body weight** — unblocked
  now that body weight is stored (ADR-016 / ADR-017).
- **Whole-food micronutrients** — carry the `micronutrients` map through to storage and
  intake totals, then wire selected micronutrients to their biomarker counterparts
  (iron→ferritin, B12, vitamin D, magnesium). This closes the diet ⇄ biomarker loop and
  is its own sprint (ADR-018, Phase 3).
- **Richer Withings signals** — body-fat %, lean mass, resting HR via the deferred
  `withings_measures` backend table (ADR-022 / ADR-023, migration plan §4.3–§4.4).

---

## iOS delivery status

The iOS client is built sprint-by-sprint against the migration plan. **Complete:** the
read path / dashboard, biomarker detail with clinical signals, Excel import & panel
timeline, diet events, the **food diary with barcode scanning (ADR-019)**, **meal plans
& calendar (ADR-020)**, **body metrics (ADR-021)**, and the **Apple HealthKit Withings
bridge (ADR-022)** — weight + BP, deduped by sample UUID. The **doctor PDF report** also
shipped.

**In progress:** the **Withings Cloud connection (ADR-023)** — the iOS connect/disconnect/
"Sync now" flow is shipped and self-gates until the backend `/withings/*` endpoints (OAuth
token exchange, history pull, `Notify` webhooks) and the `withings_measures` table ship
(migration plan §4.2–§4.4).

**Outstanding:** the **Account / GDPR surface and settings polish** (Sprint 11) and
**release hardening** (Sprint 12) — see [`IOS_APP_STORE_READINESS.md`](IOS_APP_STORE_READINESS.md)
for the submission-blocker list, and [`WISHLIST.md`](WISHLIST.md) for forward-looking
native features (widgets, notifications, Watch, Siri/App Intents, offline cache).

> **ADR sprint numbering:** ADRs 010–018 were authored against the **web** app and carry
> its sprint numbers; the iOS work re-sequences the same surface per the migration plan
> (e.g. the food diary is iOS Sprint 6). ADR-019 onward use iOS numbering — e.g. ADR-021
> (iOS Sprint 8 body metrics) realises the chart design from the web-numbered ADR-017.

---

## Key files to know

### Backend (`api/`)

| File | What it does |
|------|-------------|
| `api/app/main.py` | FastAPI app — CORS, security headers, router registration |
| `api/app/auth.py` | Shared `current_user_id` dependency (resolves the bearer token) |
| `api/app/biomarkers/parser.py` | Reads the Excel file and extracts the data |
| `api/app/biomarkers/router.py` | Import, delete, list, chart-data endpoints |
| `api/app/diet_events/`, `food_diary/`, `meal_plans/`, `body_metrics/` | Per-domain routers + repositories |
| `api/app/food_sources/` | Multi-source food providers (OFF, Matvaretabellen, USDA) + registry (ADR-018) |
| `api/app/account/repository.py` | Gathers / erases all of a user's data (GDPR) |
| `api/supabase/migrations/` | Numbered SQL migrations (run manually in the Supabase SQL editor) |
| `api/scripts/ingest_matvaretabellen.py` | Regenerates the vendored Matvaretabellen dataset |

### iOS (`ios/`)

| File | What it does |
|------|-------------|
| `ios/Packages/Core/Sources/Core/Networking/APIClient.swift` | Typed actor-based REST client (auth, retry/backoff) |
| `ios/Packages/Core/Sources/Core/Models/` | `Codable` DTOs mirroring the API response shapes |
| `ios/Packages/Biomarkers/Sources/Biomarkers/` | Ported clinical logic: categories, diet profiles, marker signals |
| `ios/Packages/Auth/Sources/AppAuth/` | Supabase auth, Keychain session, mock auth for demo mode |
| `ios/Packages/HealthSync/Sources/HealthSync/` | HealthKit sync + Withings Cloud service |
| `ios/EmpiricalTracker/Features/Dashboard/` | The biomarker grid, diet filter, sparklines |
| `ios/EmpiricalTracker/Features/BiomarkerDetail/` | Trend chart, clinical signals, confounder notes, manual entry |
| `ios/EmpiricalTracker/Features/FoodDiary/` | Diary, multi-source search, barcode scanner |
| `ios/EmpiricalTracker/Features/MealPlans/` | Weekly calendar + plan management |
| `ios/EmpiricalTracker/Features/BodyMetrics/` | Log + charts, HealthSync + WithingsCloud sections |
| `ios/EmpiricalTracker/Features/ReportShare/` | Client-side doctor PDF report |
| `ios/EmpiricalTracker/Features/Consent/` | Health-data consent gate (versioned `ConsentStore`) |

---

## Pointers

- [`IOS_MIGRATION_PLAN.md`](IOS_MIGRATION_PLAN.md) — the web→iOS migration strategy and
  status (now largely historical).
- [`IOS_APP_STORE_READINESS.md`](IOS_APP_STORE_READINESS.md) — submission-blocker
  assessment.
- [`CONFIGURATION.md`](CONFIGURATION.md) — verify the app points at the right backend.
- [`SETUP.md`](SETUP.md) — one-time backend (Supabase + Railway) setup.
- [`DIET_BIOMARKERS.md`](DIET_BIOMARKERS.md) — clinical rationale for each diet focus.
- [`NUTRITION_DATA.md`](NUTRITION_DATA.md) — food-data sources, accuracy, caveats.
- [`WISHLIST.md`](WISHLIST.md) — forward-looking native iOS feature proposals.
- [`adr/`](adr/) — Architectural Decision Records (the why behind each choice).
- [`legal/`](legal/) — privacy policy & terms drafts.
