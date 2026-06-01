# Empirical Tracker — Solution Documentation

> Plain-language explanation of what this app is, how it works, and why it's built the way it is.

---

## What is this app?

Empirical Tracker is your personal health dashboard. You upload your blood test results from the
lab, and the app shows you how your biomarkers have changed over time — with reference range
highlighting so you can see at a glance what's in range and what isn't.

The long-term goal is to correlate your blood test results with your diet (specifically a
carnivore/low-carb elimination diet), so you can see whether what you eat is actually moving
your numbers in the right direction.

---

## The problem it solves

When you get a blood panel back from the lab, you get a PDF or Excel file with a column of
numbers. To understand trends, you have to manually compare last month's file to last year's.
There's no single view that shows "here is your LDL over the last 3 years."

Empirical Tracker imports those files and builds that view automatically.

---

## What the system is made of

The app has two main parts:

### The API (the "backend")
This is a Python program that lives on a server. It:
- Receives your blood test Excel files
- Parses them (handling Norwegian number formats, reference ranges, etc.)
- Saves the results to a database
- Answers questions from the frontend (like "give me all my HDL readings")

**Technology:** Python + FastAPI. FastAPI is a modern, fast web framework — it handles HTTP
requests and automatically validates data types.

### The Web App (the "frontend")
This is the website you see in your browser. It:
- Shows a dashboard of all your biomarkers grouped by category (Lipids, Thyroid, CBC, etc.)
- Draws sparkline trend charts on each biomarker card
- Shows a full chart when you click on a biomarker, with optional diet-event
  annotations overlaid for visual correlation
- Lets you keep a food diary, searching the Open Food Facts database to add items
- Has an upload screen for importing new Excel files
- Lets you focus the view on the biomarkers relevant to your diet (carnivore, low-carb,
  fasting, or a custom hand-picked set)
- Can switch between English and Norwegian, and shows plain-language tooltips explaining
  each biomarker group

**Technology:** Next.js (React). React is the most popular way to build interactive websites.
Next.js adds server-side rendering on top of React, which makes pages load faster.

### The Database
All your data is stored in a Postgres database (a standard relational database).

**Technology:** Supabase. Supabase is a managed service that hosts the database, handles
user login, and enforces that you can only see your own data.

### Where it runs
Both the API and the web app are deployed to Railway, a hosting platform. Railway watches
the GitHub repository — when you push new code, it automatically redeploys.

---

## How your blood test data flows through the system

1. **You get a blood panel** from the lab as an Excel file (`.xlsx`)
2. **You upload it** via the import screen in the web app
3. **The API receives it**, reads each row with Python's openpyxl library, and:
   - Parses Norwegian decimal commas (`4,3` → `4.3`)
   - Parses the reference range (`4,5 - 5,8` → low: 4.5, high: 5.8, type: bounded)
   - Computes whether each value is in range or out of range
4. **The data is saved** to three database tables:
   - `biomarkers` — the catalog of what each test measures (name, reference range)
   - `panels` — one row per test date (a "panel" = one blood draw session)
   - `results` — one row per (biomarker × panel), with the measured value and in-range flag
5. **When you view the dashboard**, the web app fetches your results from the API and draws the charts

---

## The database structure

Four tables work together:

```
biomarkers:    What is being measured
               "P-HDL-kolesterol | ref: 0.9 - 2.0 | type: bounded"

panels:        When a blood draw happened
               "tested_at: 2026-05-22 | source: xlsx_import"

results:       The actual measurement
               "biomarker: HDL | panel: May 2026 | value: 1.3 | in_range: true"

user_settings: Your dashboard preferences
               "diet: carnivore | custom_markers: [...]"
```

The first three tables hold your blood-test data. `user_settings` holds one row per user with
your dashboard preferences (which diet focus is active, and any custom marker selection).

Two more tables were added in Sprints 3 and 4:

```
diet_events:   When you changed your regimen (correlation overlay annotations)
               "label: Started carnivore | kind: diet | started_on: 2024-05-31"

food_entries:  What you ate each day (food diary, sourced from Open Food Facts)
               "logged_on: 2026-05-31 | meal: dinner | food: Ribeye | 728 kcal"
```

Sprint 5 added two more tables for forward planning:

```
meal_plans:    A named, reusable plan (a label/grouping for planned meals)
               "name: Carnivore week | description: High-protein, zero-carb"

planned_meals: A meal scheduled on the calendar (optionally filed under a plan)
               "scheduled_on: 2026-06-02 | meal: dinner | Ribeye | done: false"
```

Every row in every table has a `user_id` column. This means your data and someone else's data
are completely separate — the database itself enforces this (not just the application code).

---

## Security and privacy

Your blood test data is health data under GDPR (EU privacy law). The app is designed with this
in mind:

**Row-Level Security (RLS):** A database-level rule that says "a user can only read and write
rows where `user_id` matches their own ID." Even if there were a bug in the application code,
the database would refuse to show you another person's data.

**EU data storage:** The Supabase database runs in Frankfurt, Germany. Your health data never
leaves the EU.

**Server-side API key:** The database has a powerful "service role" key that can bypass RLS.
This key only exists on the server (as an environment variable on Railway). Your browser
never sees it — your browser only gets a limited "anon key" that respects RLS.

**JWT authentication:** Every request to the API includes a short-lived token (JWT) that proves
who you are. The API verifies this token with Supabase before touching any data.

---

## The biomarker categories

The 34 biomarkers from your blood panel are grouped into 8 categories:

| Category | What it tracks |
|----------|---------------|
| **Lipids** | Cholesterol (HDL, LDL, Total, non-HDL) |
| **CBC** | Blood cell counts (Hemoglobin, RBC, WBC, Hematocrit, MCV, MCH, MCHC) |
| **Metabolic** | Blood sugar management (HbA1c) |
| **Thyroid** | Thyroid function (TSH, Free T4) |
| **Renal** | Kidney function (Creatinine, eGFR) |
| **Liver** | Liver enzymes (ALT, GGT) |
| **Nutrients** | Vitamins and minerals (Ferritin, B12, Active B12, Vitamin D, Folate, Iron, Transferrin, Homocysteine, MMA) |
| **Electrolytes** | Sodium, Potassium |

---

## Diet focus

The dashboard has a **Diet focus** control that hides biomarkers which aren't clinically
informative for your chosen eating pattern, so you see a focused view instead of all 34 markers
at once:

| Focus | Shows |
|-------|-------|
| **All** | Every biomarker |
| **Carnivore** | Lipids, iron studies, renal/liver load, electrolytes, B-vitamin/folate status, HbA1c, Hgb/Hct |
| **Low carb** | HbA1c, full lipid panel, liver enzymes, electrolytes, ferritin |
| **Fasting** | Electrolytes, glucose, kidney/liver, hydration-sensitive blood counts, lipids |
| **Custom** | Any markers you hand-pick |

The clinical reasoning behind each list is documented in `docs/DIET_BIOMARKERS.md`. Your choice
is saved per user (in the `user_settings` table when signed in, or `localStorage` for the demo
view). Custom selections are stored by biomarker name, so they survive re-imports and new panels.

---

## Correlation overlay (Sprint 3)

You can mark **diet events** — the day you started carnivore, a supplement, a
medication, or a multi-day fast — and they are drawn on top of every biomarker
trend chart. A single date shows as a dashed marker line; an event with an end
date shows as a shaded period. This lets you see at a glance whether a regimen
change lines up with a shift in your numbers.

You manage these annotations from any biomarker's detail page ("Diet
annotations"). They are account-wide: one set of events annotates all your
charts, because a diet change affects the whole panel, not one marker.

**Important honesty caveat:** annotations are *snapped to the nearest blood
draw* (the chart has one slot per draw), so their position is approximate, and a
marker moving near an annotation **does not prove cause and effect**. The UI says
so. The full reasoning is in `docs/adr/010-correlation-overlay.md`.

Diet events live in a new `diet_events` table (RLS self-scoped) and are served by
`GET/POST/DELETE /diet-events`.

---

## Food diary (Sprint 4)

The food diary lets you log what you eat each day. Instead of typing nutrition
facts by hand, you search the **Open Food Facts** branded & barcode database (a
free, open food database under the ODbL licence — no API key needed) or enter a
barcode directly, then pick a quantity and meal.

- The app stores the **amounts you actually consumed** (energy, carbs, protein,
  fat), computed as `per-100g × grams / 100`, so your diary stays correct even if
  the upstream product data later changes.
- Nutrition is taken **as published by Open Food Facts** — never invented or
  estimated. Missing values show as "—".
- The `/food-diary` page has a date navigator, daily macro totals, and entries
  grouped by meal.

How it's sourced and the accuracy limits are documented in
`docs/NUTRITION_DATA.md`; the design rationale is in
`docs/adr/011-food-diary-openfoodfacts.md`.

Food data lives in a new `food_entries` table (RLS self-scoped). Open Food Facts
is reached through a small authenticated **backend proxy** (`GET
/food-diary/search`, `GET /food-diary/barcode/{code}`) that attaches the required
`User-Agent` and normalises OFF's nutriment fields. Diary CRUD is `GET/POST/DELETE
/food-diary`.

---

## Meal plans and calendar (Sprint 5)

Where the food diary records what you *did* eat, **meal plans** are the
forward-looking half: planning what you *intend* to eat, laid out on a weekly
calendar so you can prep a carnivore/low-carb week ahead of time.

- The `/meal-plans` page shows a **week-at-a-glance calendar** (Monday→Sunday),
  navigable across weeks, with per-day energy totals.
- You schedule a meal into any day either by **searching Open Food Facts** for
  real macros (reusing the same search as the food diary) or with a quick
  **free-text** note for things that aren't barcoded products.
- **Named plans** ("Carnivore week", "Low-carb reset") group scheduled meals and
  let you filter the calendar. Deleting a plan keeps its meals on the calendar —
  it only removes the label.
- Each planned meal has a **"Log to diary"** action that copies it into the
  Sprint 4 food diary for its scheduled date and marks it done — so the plan and
  the actual record stay one click apart, with no re-entry.

Meal plans live in two new tables — `meal_plans` and `planned_meals` (both RLS
self-scoped) — served by `GET/POST/DELETE /meal-plans` and
`GET/POST/PATCH/DELETE /meal-plans/calendar`. The design rationale and scope cuts
are in `docs/adr/012-meal-plans-calendar.md`.

---

## Data export and account deletion (Sprint 6)

Your blood test data is GDPR special-category health data, so the app gives you
the two rights that matter most over it, from a single **Account** page (linked in
the header when you're signed in):

- **Export everything** (right to data portability) — download all your data as
  one **JSON** file, or as a **CSV zip** with one spreadsheet per table. The export
  covers every table you own: biomarkers, panels, results, settings, diet events,
  food diary, and meal plans, plus a metadata header with per-table row counts.
- **Delete your account** (right to erasure) — permanently erase all your data and
  your login. The danger-zone action requires typing `DELETE` to confirm, then
  signs you out. Deletion removes rows child-first (so foreign keys never block it)
  and then removes the auth user itself.

Both are served by a new `GET /account/export` and `DELETE /account`. The API also
now sends baseline **security headers** (CSP, `X-Frame-Options`, `nosniff`, HSTS,
`Referrer-Policy`) on every response. The design and the GDPR mapping are in
`docs/adr/013-data-export-account-deletion.md`.

> Sprint 6 also includes **doctor sharing**, scoped as a PDF/printable report — a
> follow-up to this slice, not yet shipped.

---

## Reference range vs. clinical target + trend signals (Sprint 7)

The lab **reference range** is a population interval, not a verdict of "healthy."
Sprint 7 stops the app conflating the two, in two ways:

- **Clinical targets** — for the markers where the gap matters first (LDL,
  non-HDL, total cholesterol, HbA1c), the app knows a guideline *optimal* upper
  bound that is tighter than the lab's reference. A value can sit inside the lab
  range yet **at or above the clinical target** (e.g. LDL 4.1 with lab upper 4.7
  but a low-risk target of 3.0). The chart draws the target as a distinct amber
  dashed line, separate from the green reference band. These are **general
  guideline values, not personalised** — and not per-user data, so they live as a
  static reference map keyed off the same `markerKey()` the diet focus uses (no
  database table).
- **Within-range trend signals** — the app surfaces movement the green flag used
  to hide: a large step between draws (≥ 50%, so any doubling trips it — e.g. ALT
  25 → 55), a notable step (≥ 25%), and a value sitting near a reference bound.

A single `assessMarker()` combines the in/out-of-range flag, the target check,
and the trend signals into one status. An in-range marker with a flagged target
or trend now reads as **"Watch"** (amber) — the green flag never overrides a
flagged trend. The dashboard counts these "in range but worth a look" markers,
and each marker's detail page lists the signals with their reasoning.

Everything here is **decision-support, not medical advice**: targets are general
guideline values, the trend signals are descriptive (no slopes, p-values, or
causation on a handful of draws), and the UI says so. The design and the exact
rules are in `docs/adr/014-clinical-targets-trend-signals.md`.

---

## Where the "Add result" button lives

Manual single-result entry now lives on each **biomarker detail page** (an "Add
result" button in that page's header), pre-selecting the marker you're looking
at, rather than as a global button on the dashboard. Adding a result where you're
already looking at that marker's trend is the natural place for it.

---

## Language and tooltips

The UI can switch between **English and Norwegian** via a toggle in the header (your choice is
remembered). Each biomarker group also has an "i" tooltip with a plain-language explanation of
what those markers measure, in both languages.

---

## The import format

The app understands the standard Norwegian blood panel Excel format:

- **Column A:** Biomarker name (in Norwegian, often with English translation in parentheses)
- **Column B:** Reference range — can be `4,5 - 5,8` (bounded), `<42` (less than), or blank
- **Columns C+:** One column per test date (format: `DD.MM.YYYY`)
- **Cells:** The measured value, using Norwegian decimal commas (`4,3` not `4.3`)
- **Empty cells:** Fine — not every biomarker is tested every time

---

## The sprint roadmap

| Sprint | What gets built |
|--------|----------------|
| 0 ✅ | Server setup, deployment pipeline, Supabase wired |
| 1 ✅ | Biomarker import, dashboard UI, sparkline trend charts, auth wired |
| 2 ✅ | Panel timeline, per-marker trend charts, in/out-of-range highlighting, manual entry |
| 3 ✅ | Correlation overlay — draw a diet annotation on top of a biomarker chart |
| 4 ✅ | Food diary — log what you eat each day, with Open Food Facts search |
| 5 ✅ | Meal plans and calendar — plan the week ahead, log planned meals to the diary |
| 6 | GDPR data export + account deletion ✅ and security headers ✅; doctor sharing (PDF report) — follow-up |
| 7 ✅ | Reference range vs. clinical target + within-range trend signals |
| 8 | **Panel expansion — high-yield markers, derived ratios, confounder tooltips** |
| 9 | **Food diary depth — sodium & saturated fat, better food source, daily targets** |
| 10 | **Body metrics & longitudinal context — weight, waist, blood pressure** |

Additional UX enhancements shipped alongside Sprint 2 (outside the original roadmap): diet-focus
biomarker filtering (ADR-008) and English/Norwegian internationalization with category tooltips
(ADR-009).

Sprints 7–10 come from a clinical review of the app (diet & nutrition lens); the rationale and
priority for each item are captured in **Clinical-feedback roadmap (Sprints 7–10)** below.

---

## Sprint 6 — remaining work (follow-up)

The data-rights half of Sprint 6 has shipped: **GDPR data export, account deletion, and security
headers** (ADR-013). Two items remain before Sprint 6 is closed:

- **Doctor sharing — PDF / printable report** (the headline Sprint 6 item, still open). Rather than
  granting a doctor live access (which would need multi-tenant read RLS and a doctor login), the
  user exports a **formatted, printable report** to hand or email to their clinician. Scope:
  - A read-only report covering the biomarker panel — latest value, reference range, in/out-of-range
    state, and the trend per marker — plus any active diet-event annotations for context.
  - Generated server-side as a new `GET /account/report` endpoint (or printed from a dedicated
    `/account/report` print-CSS page), reusing the existing per-user data access.
  - Must carry the same intellectual-honesty caveats as the rest of the app: "decision-support, not
    medical advice," and no implied causation from the diet-event overlay.
  - Decision to record in its own ADR: server-rendered PDF (new dependency, e.g. a PDF lib) vs. a
    browser print-CSS page (no dependency). Lean toward print-CSS first to avoid a new dependency.

- **Export/erasure coverage is a maintenance contract** (carried from ADR-013). `USER_TABLES` and
  `DELETE_ORDER` in `api/app/account/repository.py` must be extended whenever a new user-owned table
  or nutrient column is added — specifically **Sprint 9** (sodium / saturated-fat columns) and
  **Sprint 10** (`body_metrics`). A table left out would silently drop from both export and erasure,
  so each of those sprints' reviews must check this off.

---

## Clinical-feedback roadmap (Sprints 7–10)

These four sprints translate a clinical review of the app into work. The review's central
finding was that the app is **honest and well-built, but treats the lab "reference range" as if
it meant "healthy,"** and is missing several of the markers (and food fields) that matter most for
the carnivore / low-carb / fasting users it targets. Sprints are ordered by clinical priority and
dependency: ranges first (safety), then the panel, then the diary, then body metrics.

Severity tags below mirror the review: **High** = change a decision a user could get wrong today;
**Medium** = meaningful gap; **Low** = polish / consistency.

### Sprint 7 — Reference range vs. clinical target + within-range trend signals ✅

> **Delivered.** Implemented as a static, client-side clinical-target reference map
> (`web/src/lib/clinicalTargets.ts`, keyed off `markerKey()`) rather than a DB table or
> per-user biomarker columns — the targets are universal guideline values, not per-user PII.
> Trend signals and the combined `assessMarker()` status live in `web/src/lib/markerSignals.ts`.
> Triglycerides are seeded in Sprint 8 when the marker is added. See ADR-014.

> **Why:** "in range" is being conflated with "healthy." A user on a high-saturated-fat diet can
> see LDL 4.1 mmol/L flagged green (lab ref_high 4.7) when guideline targets for an at-risk person
> are far lower; and a doubling of ALT (25 → 55 U/L) stays green because it's still under 70. The
> binary flag actively hides the trends that matter.

- **Clinical-target layer, separate from the lab reference range** (High). Add optional
  `target_low` / `target_high` to the biomarker model (or a seeded `marker_targets` reference
  table — guideline values, not per-user PII). Seed for lipids (LDL, non-HDL, total, and
  triglycerides once added) and HbA1c. The UI distinguishes **"within lab reference"** from
  **"at/above clinical target,"** with a distinct state/colour rather than reusing in/out-of-range.
- **Within-range trend signals** (High). Surface "rising/falling fast," "trending toward a bound,"
  and large relative jumps (e.g. a doubling) even when every point is technically in range. The
  trend charts already make this visible to an attentive user; this makes the app say it.
- Update `in_range` rendering so the green flag never overrides a flagged trend.
- ADR documenting the reference-vs-target distinction and the trend-signal rules.

### Sprint 8 — Panel expansion, derived ratios, confounder tooltips

> **Why:** for these specific diets, several of the *most* informative markers are simply absent,
> and two markers we already track are confounded by the diet itself.

- **High-yield new markers** (High): **triglycerides** (the signature low-carb response; the Lipids
  tooltip already promises it), **ApoB** ± **Lp(a)** (gold-standard atherogenic burden — the marker
  to add for the lean-mass hyper-responder pattern), **uric acid** (raised by both high-purine
  carnivore intake and fasting).
- **Refeeding fix** (High, fasting): add **magnesium** and **phosphate**. The Fasting profile claims
  to watch "refeeding-syndrome risk," which is defined by phosphate/magnesium/potassium — today only
  potassium is present, so the stated purpose and the markers don't match.
- **Further markers** (Medium): **fasting insulin / C-peptide** and **fasting glucose** (HbA1c alone
  misses early insulin resistance), **hs-CRP** (inflammation is a headline claimed benefit),
  **AST/ASAT** (normally paired with ALT).
- **Derived markers** (Medium): compute and chart **TG/HDL ratio** (insulin-resistance surrogate)
  and **AST:ALT ratio**.
- Plumb the above through the parser keyword rules (`biomarkerCategories.ts`), the marker-key rules
  and diet focus lists (`dietProfiles.ts` + `DIET_BIOMARKERS.md`): TG/ApoB into every lipid view;
  uric acid into carnivore + fasting; Mg/phosphate into fasting; insulin/glucose into low-carb.
- **Confounder tooltips** (Low–Medium): eGFR — creatinine-based eGFR is depressed by high meat
  intake/muscle mass, suggest cystatin-C; HbA1c — can read paradoxically high on keto/carnivore from
  altered RBC turnover; ferritin — an acute-phase reactant, rises with inflammation, not just iron.
- Trim or fulfil tooltips that promise markers not in the panel (triglycerides, glucose, calcium,
  ASAT) so the app never describes what it can't show.

### Sprint 9 — Food diary depth & better food data

> **Why:** the diary's four macros omit the two things the biomarker side cares about most
> (sodium and saturated fat), Open Food Facts is a branded-product database ill-suited to whole-food
> carnivore eating, and energy frequently shows "—" unnecessarily.

- **Add sodium and saturated fat** to tracked nutrients (High): schema column, scaling, UI, and OFF
  field mapping (`salt_100g` → sodium, `saturated-fat_100g`). Closes the loop with the labs, which
  emphasise electrolyte management and saturated-fat-driven LDL.
- **kJ → kcal fallback** in the OFF client (Low, quick win): when `energy-kcal_100g` is absent, fall
  back to `energy_100g` (kJ) ÷ 4.184 instead of storing nothing.
- **Whole-foods reference source** (Medium): add USDA FoodData Central and/or the Norwegian
  *Matvaretabellen* alongside OFF, prioritised for unbranded whole foods (steak, eggs, mince), which
  OFF covers poorly. Matvaretabellen also fits the Norwegian-first framing.
- **Daily targets / needs context** (Medium): per-day energy and macro targets, including
  **protein in g/kg body weight** (renal-load concern), with intake-vs-target shown. The g/kg target
  depends on body weight from Sprint 10 — ship the targets UI here and enable the g/kg view once
  weight tracking lands (or capture a single weight value as a prerequisite).

### Sprint 10 — Body metrics & longitudinal context

> **Why:** for diet tracking, weight, waist, and blood pressure respond faster and matter more than
> most labs, and BP ties directly to the app's sodium emphasis — yet there are no body metrics at all.

- New `body_metrics` table (RLS self-scoped): **weight, waist, blood pressure**, with trend charts on
  the same timeline and the same diet-event correlation overlay as biomarkers.
- Feed body weight into the Sprint 9 **protein g/kg** target.
- Optionally overlay body metrics against the biomarker timeline for at-a-glance context.

> **Cross-cutting (all four sprints):** keep the review's intellectual honesty. Every new number is
> "decision-support, not medical advice"; with only a handful of blood draws, the app must keep
> declining to imply causation or statistical significance.

---

## Local development

**Run the API:**
```bash
cd api
python -m venv .venv && .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env   # fill in SUPABASE_URL and SUPABASE_SERVICE_KEY
uvicorn app.main:app --reload --port 8000
```

**Run the web app:**
```bash
cd web
npm install
cp .env.example .env.local   # fill in NEXT_PUBLIC_API_URL and NEXT_PUBLIC_SUPABASE_*
npm run dev   # opens http://localhost:3000
```

**Run the tests:**
```bash
cd api
pytest -v   # 37 tests, should all pass
```

---

## Key files to know

| File | What it does |
|------|-------------|
| `api/app/main.py` | Entry point — FastAPI app, CORS config, router registration |
| `api/app/auth.py` | Shared `current_user_id` dependency — resolves the bearer token |
| `api/app/biomarkers/parser.py` | Reads your Excel file and extracts the data |
| `api/app/biomarkers/repository.py` | Saves and retrieves data from Supabase |
| `api/app/biomarkers/router.py` | HTTP endpoints: import, delete, list, chart data |
| `api/app/settings/router.py` | HTTP endpoints: read/write per-user dashboard settings |
| `api/app/diet_events/` | Diet-event (correlation annotation) router + repository |
| `api/app/food_diary/router.py` | Food-diary CRUD + Open Food Facts proxy endpoints |
| `api/app/food_diary/openfoodfacts.py` | Open Food Facts client (search + barcode, normalised) |
| `api/app/meal_plans/router.py` | Meal-plan + calendar (planned-meal) CRUD endpoints |
| `api/app/meal_plans/repository.py` | Saves/retrieves meal plans and planned meals |
| `api/app/account/router.py` | GDPR data export + account-deletion endpoints |
| `api/app/account/repository.py` | Gathers / erases all of a user's data across tables |
| `api/supabase/migrations/001_biomarkers.sql` | Creates the three blood-test tables |
| `api/supabase/migrations/003_user_settings.sql` | Creates the `user_settings` table |
| `api/supabase/migrations/004_diet_events.sql` | Creates the `diet_events` table |
| `api/supabase/migrations/005_food_entries.sql` | Creates the `food_entries` table |
| `api/supabase/migrations/006_meal_plans.sql` | Creates the `meal_plans` + `planned_meals` tables |
| `web/src/app/page.tsx` | The main dashboard page |
| `web/src/app/biomarkers/[id]/page.tsx` | Biomarker detail — chart, annotations, Add result |
| `web/src/app/food-diary/page.tsx` | The food diary page (Sprint 4) |
| `web/src/app/meal-plans/page.tsx` | The meal-plan weekly calendar page (Sprint 5) |
| `web/src/app/account/page.tsx` | Account page — data export + account deletion (Sprint 6) |
| `web/src/components/PlannedMealPicker.tsx` | Add a planned meal (OFF search or free-text) |
| `web/src/lib/useFoodSearch.ts` | Shared Open Food Facts search hook (diary + meal plans) |
| `web/src/app/import/page.tsx` | The file upload page |
| `web/src/lib/api.ts` | All the API calls from the frontend |
| `web/src/lib/mockData.ts` | Realistic test data (biomarkers, diet events, food entries) |
| `web/src/lib/dietProfiles.ts` | Diet → biomarker focus sets + name classifier |
| `web/src/lib/clinicalTargets.ts` | Guideline clinical-target bounds, keyed by marker (Sprint 7) |
| `web/src/lib/markerSignals.ts` | Trend signals + combined marker assessment (Sprint 7) |
| `web/src/components/MarkerSignals.tsx` | Detail-page target + trend signal panel (Sprint 7) |
| `web/src/lib/chartAnnotations.ts` | Projects diet events onto the chart's x-axis |
| `web/src/lib/i18n.ts` | English/Norwegian string dictionary |
| `web/src/app/panels/page.tsx` | Panel timeline — list of all blood draw sessions |
| `web/src/components/BiomarkerChart.tsx` | Trend chart with reference band + diet overlay |
| `web/src/components/DietEventManager.tsx` | Add/list/delete diet annotations |
| `web/src/components/FoodSearch.tsx` | Open Food Facts search + barcode add box |
| `web/src/components/ManualEntryModal.tsx` | Manual entry form for adding individual results |
| `web/src/components/DietFilter.tsx` | Diet-focus segmented control |
| `web/src/components/LanguageProvider.tsx` | Language context + EN/NO toggle state |
| `docs/DIET_BIOMARKERS.md` | Clinical rationale for each diet's biomarker focus list |
| `docs/NUTRITION_DATA.md` | Food-data sources, accuracy caveats, correlation caveat |
| `docs/adr/` | Architectural Decision Records — why we made the choices we made |
