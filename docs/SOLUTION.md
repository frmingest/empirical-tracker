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
- Shows a full chart when you click on a biomarker
- Has an upload screen for importing new Excel files

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

Three tables work together:

```
biomarkers:  What is being measured
             "P-HDL-kolesterol | ref: 0.9 - 2.0 | type: bounded"

panels:      When a blood draw happened
             "tested_at: 2026-05-22 | source: xlsx_import"

results:     The actual measurement
             "biomarker: HDL | panel: May 2026 | value: 1.3 | in_range: true"
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
| 1 🔄 | **Biomarker import** (this sprint), dashboard UI, trend charts |
| 2 | Per-panel timeline, in/out-of-range highlighting, manual entry |
| 3 | Correlation overlay — draw a diet annotation on top of a biomarker chart |
| 4 | Food diary — log what you eat each day |
| 5 | Meal plans and calendar |
| 6 | Doctor sharing, GDPR data export, security audit |

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
pytest -v   # 29 tests, should all pass
```

---

## Key files to know

| File | What it does |
|------|-------------|
| `api/app/main.py` | Entry point — FastAPI app, CORS config, router registration |
| `api/app/biomarkers/parser.py` | Reads your Excel file and extracts the data |
| `api/app/biomarkers/repository.py` | Saves and retrieves data from Supabase |
| `api/app/biomarkers/router.py` | HTTP endpoints: import, delete, list, chart data |
| `api/supabase/migrations/001_biomarkers.sql` | Creates the three database tables |
| `web/src/app/page.tsx` | The main dashboard page |
| `web/src/app/biomarkers/[id]/page.tsx` | The detail page for one biomarker |
| `web/src/app/import/page.tsx` | The file upload page |
| `web/src/lib/api.ts` | All the API calls from the frontend |
| `web/src/lib/mockData.ts` | Realistic test data (all 30+ biomarkers with real values) |
| `docs/adr/` | Architectural Decision Records — why we made the choices we made |
