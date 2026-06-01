# ADR-018: Whole-foods data sources — Matvaretabellen & USDA FoodData Central

**Status:** Proposed
**Date:** 2026-06-01
**Author:** Architecture proposal (Claude)
**Sprint:** 9 follow-up ("Whole-foods reference source")

---

## TL;DR

Add two **authoritative, lab-analysed whole-food** databases alongside Open Food
Facts (OFF):

- **Matvaretabellen** — the Norwegian Food Composition Table (Mattilsynet /
  Helsedirektoratet / UiO). Fits the app's Norwegian-first framing.
- **USDA FoodData Central (FDC)** — the American equivalent (USDA Agricultural
  Research Service).

OFF stays the source for **branded & barcode** products. The new sources own
**unbranded whole foods** (steak, eggs, mince, butter) — exactly the foods a
carnivore / low-carb eater logs most, and exactly where OFF is weakest. This is
an **additive, multi-source** design, not a replacement, and it directly
reverses the "rejected" note against USDA in ADR-011 now that we are
*complementing* OFF rather than choosing between them.

---

## Context — why this, why now

### What the app does with food today (Sprint 4 / 9, ADR-011 / ADR-016)

- The food diary and meal-plan calendar add foods by searching **Open Food
  Facts** through an auth-gated backend proxy (`app/food_diary/openfoodfacts.py`),
  which normalises OFF's messy nutriment keys into one stable shape
  (`FoodItem`): name, brand, quantity, and six per-100 g values — energy,
  carbs, protein, fat, saturated fat, sodium.
- We **store the consumed amount** (`per-100g × grams / 100`), never a live
  reference, so entries stay durable (ADR-011).
- We **never invent numbers** — missing fields render as "—"
  (`docs/NUTRITION_DATA.md`).

### The gap (flagged by the clinical review, Sprint 9)

OFF is a **branded-product / barcode** database. It is excellent for "Kvikk
Lunsj" or a specific yoghurt tub, but **poor for unbranded whole foods**: search
"ribeye" or "egg" and you get an inconsistent scatter of user-entered branded
packs with patchy, sometimes wrong, macros and almost no micronutrients. Those
whole foods are the *staple* of the diets this app targets (carnivore /
low-carb), so the weakest part of OFF is the most-used part for our user.

Two things make closing this gap high-value here specifically:

1. **The diets are whole-food diets.** "Beef, ribeye, raw" should come from a
   curated, analysed entry — not a crowd-sourced branded guess.
2. **The biomarker side already tracks micronutrients.** The Nutrients category
   covers ferritin, B12, vitamin D, folate, iron, magnesium, phosphate. OFF
   rarely carries those per-food. Whole-food composition tables carry **full
   vitamin/mineral profiles**, which unlocks a future "did my *intake* of iron /
   B12 / magnesium track my *blood* iron / B12 / magnesium?" loop — the app's
   whole reason to exist (diet ⇄ biomarker correlation).

---

## What each source provides that OFF does not

| Dimension | Open Food Facts (have) | Matvaretabellen (add) | USDA FoodData Central (add) |
|-----------|------------------------|------------------------|------------------------------|
| **Primary content** | Branded packaged products, barcodes | Generic/whole foods (Norwegian) | Generic/whole foods + branded (US) |
| **Provenance** | Crowd-sourced (community) | Government, lab-analysed + curated | Government, lab-analysed (Foundation/SR Legacy) |
| **Coverage of whole foods** | Weak, inconsistent | **Strong** (~1 600–2 000 foods) | **Strong** (Foundation + SR Legacy) |
| **Micronutrients** | Sparse | **Full** vitamins, minerals, fatty-acid breakdown | **Full** (often dozens of nutrients/food) |
| **Barcodes** | **Yes** | No | Branded subset only |
| **Language / fit** | Mixed; global | **Norwegian** food names — matches the NO-first UI & panel | English |
| **API key** | None | None (open data dump + API) | **Free key** (api.data.gov), ~1 000 req/h |
| **Licence** | ODbL (share-alike, attribution) | NLOD / CC BY (open gov data) | **Public domain (CC0)** for USDA-produced data |
| **Stability** | Live community DB, changes | Versioned dataset release | Versioned dataset release |

**Net:** OFF answers "what's in this *package*?"; Matvaretabellen and FDC answer
"what's in this *food*?" — with trustworthy macros **and** the micronutrients the
biomarker panel cares about.

### Why both, not one

- **Matvaretabellen** fits the Norwegian user and UI (Norwegian food names, the
  app already speaks NO), is fully open with a downloadable dataset, and is the
  natural default for our primary user.
- **USDA FDC** is the largest, most permissively licensed (CC0) composition
  database, with both whole foods *and* a large US branded set — the right
  default for any non-Norwegian user and the broadest fallback.

They are complementary in language/region; offering both lets the app pick a
sensible regional default and fall back to the other.

---

## Decision (proposed)

### 1. Generalise to a multi-source food provider

Introduce a small **source abstraction** in the backend so the diary/meal-plan
code is source-agnostic:

```
app/food_sources/
  base.py            # FoodItem shape + FoodSource protocol
  openfoodfacts.py   # moved from app/food_diary/ (unchanged behaviour)
  matvaretabellen.py # new
  usda.py            # new
  registry.py        # name -> client, plus regional default
```

A `FoodSource` exposes:

```python
async def search(query: str, page_size: int) -> list[FoodItem]
async def lookup_barcode(code: str) -> FoodItem | None   # OFF / USDA-branded only
```

The normalised `FoodItem` gains one required field — **`source`** (`"off"` |
`"mvt"` | `"usda"`) — and an **optional `micronutrients` map** (additive; ignored
by today's UI, consumed by a later phase). All existing fields stay identical, so
the contract is backward-compatible.

### 2. Endpoint changes (no breaking change)

`GET /food-diary/search?q=…&source=…`

- `source` is optional. Allowed: `off` (default if omitted, preserving current
  behaviour), `mvt`, `usda`, or `all`.
- `all` queries the enabled sources concurrently (`asyncio.gather`), tags each
  result with its `source`, and returns a merged, source-labelled list.
- `GET /food-diary/barcode/{code}` is unchanged (barcodes route to OFF, with an
  optional USDA-branded fallback). Whole-food sources have no barcodes.

### 3. Matvaretabellen — ship the dataset, don't call it live

Matvaretabellen publishes the **full table as a downloadable open dataset**
(JSON/CSV) plus an API. Because it's only ~2 000 foods, the cleanest design is to
**vendor the dataset** as a build-time asset and search it **in-process**:

- A small ingest script (`scripts/ingest_matvaretabellen.py`) downloads the
  release, maps it to our `FoodItem` shape (+ micronutrients), and writes a
  versioned `data/matvaretabellen.<version>.json`.
- `matvaretabellen.py` loads it once and does substring/lite-rank search.
- **Pros:** zero runtime third-party dependency, no rate limit, instant search,
  works offline, fully reproducible, trivial to test. Refreshed only when a new
  table version is released (a deliberate, reviewable bump).

### 4. USDA FDC — proxied + cached, with a key

FDC requires a free `api.data.gov` key and rate-limits ~1 000 req/h **per key**
(shared across all our users), so:

- Add `USDA_FDC_API_KEY` as a server-only env var (same pattern as Supabase
  keys; never exposed to the browser). The proxy degrades gracefully to "USDA
  unavailable" if it's unset, exactly like an OFF outage today.
- `usda.py` calls FDC `POST /v1/foods/search`, restricted by default to
  `Foundation` + `SR Legacy` (the analysed whole-food sets), with `Branded` as
  an opt-in. Normalise FDC's `foodNutrients` (per-100 g) into `FoodItem`.
- **Cache** search results and food lookups (in-memory TTL to start; promote to
  a `food_lookup_cache` table if needed) so repeated common queries ("egg",
  "beef") don't burn the shared quota.

### 5. Persist provenance on the entry

Add a nullable `source` column to **`food_entries`** *and* **`planned_meals`**
(migration `009_food_source.sql`), defaulting to `'off'` for existing rows.

- This keeps the app's honesty contract: the diary can **show where each number
  came from** (a small source badge), and a clinician reading an export can tell
  a lab-analysed USDA entry from a crowd-sourced OFF one.
- Storing consumed amounts is unchanged — the new column is metadata, not a live
  link, so durability (ADR-011) is preserved.
- The column is a *new column on an already-listed table*, so it flows into the
  GDPR export/erasure automatically (`select("*")`) with **no** `USER_TABLES` /
  `DELETE_ORDER` change — consistent with ADR-016's finding for sodium/sat-fat.

### 6. Frontend (additive)

- `FoodItem` gains `source` (and optional `micronutrients`).
- `useFoodSearch` gains a `source` argument; `FoodSearch` and
  `PlannedMealPicker` get a small **source selector** — e.g. *Whole foods (NO)* /
  *Whole foods (US)* / *Branded (OFF)* / *All* — defaulting to the user's region
  (Norwegian user → Matvaretabellen). Each result row shows a **source badge**.
- Barcode entry stays OFF-only (greyed for whole-food sources).
- **Attribution:** the food-diary page already credits OFF/ODbL; add credits for
  **Matvaretabellen (NLOD/CC BY)** and **USDA FDC (public domain)**, and update
  `docs/NUTRITION_DATA.md` to describe the three sources and their provenance.

---

## Phasing (keeps each PR small, the codebase's house style)

- **Phase 1 — Matvaretabellen, macros only.** Source abstraction + vendored
  dataset + `source` selector/badge + `source` column. No new key, no live
  dependency, immediate whole-food quality for the Norwegian user. *Lowest risk,
  highest fit — do this first.*
- **Phase 2 — USDA FDC, macros only.** Add the keyed, cached proxy and the
  English whole-food/branded coverage.
- **Phase 3 — Micronutrients (separate ADR).** Carry the `micronutrients` map
  through to storage, daily intake totals, and (with Sprint 9's deferred daily
  **targets**) an intake-vs-need view — then wire selected micronutrients to
  their **biomarker** counterparts (iron→ferritin, B12, vitamin D, magnesium).
  This is the real prize but is its own sprint.

---

## Why we need it (summary of the case)

1. **Right data for the right diet.** Carnivore/low-carb is whole-food eating;
   OFF is a branded/barcode DB. We are currently strongest exactly where the user
   needs us least, and weakest where they need us most.
2. **Trust.** Government, lab-analysed composition tables vs. crowd-sourced
   entries — fewer wrong macros, with provenance the user (and their clinician)
   can see.
3. **Closes the app's core loop.** Micronutrient profiles let intake meet the
   Nutrients biomarker panel — the diet ⇄ biomarker correlation the whole app is
   built to support.
4. **Regional fit.** Matvaretabellen matches the Norwegian-first UI and panel
   format; USDA serves everyone else and is the most permissively licensed
   option available.

---

## Pros / Cons

**Pros**

- High-quality, lab-analysed whole-food macros + micronutrients.
- Norwegian-language foods (Matvaretabellen) aligned with the existing UI.
- Matvaretabellen needs no key and no live dependency (vendored dataset).
- USDA is CC0 (public domain) — the cleanest licence of the three.
- Fully additive: existing OFF flow, contract, and stored entries unchanged.
- Provenance recorded per entry → reinforces the app's intellectual-honesty stance.

**Cons / trade-offs**

- **More sources to maintain.** Mitigated by the thin `FoodSource` protocol and a
  vendored MVT dataset (refreshed only on a version bump).
- **USDA needs a key + shared rate limit.** Mitigated by caching, restricting to
  whole-food datasets by default, and graceful degradation when the key is
  absent/limited.
- **Multiple attributions & licences (ODbL vs NLOD/CC-BY vs CC0).** Each must be
  credited; the `source` field makes per-entry attribution exact.
- **No barcodes from whole-food DBs.** Expected — OFF keeps the barcode path.
- **UI complexity** of a source selector. Mitigated by a sensible regional
  default and a simple "All" merge.
- **Micronutrients are tempting but large.** Deliberately deferred to Phase 3 /
  its own ADR so Phases 1–2 stay shippable.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Keep OFF only | Leaves the most-used (whole-food) case poorly served; no micronutrients |
| Replace OFF with USDA/MVT | Loses branded/barcode coverage OFF is genuinely good at |
| USDA only (skip Matvaretabellen) | Abandons the Norwegian-first fit and a fully-open, key-less dataset |
| Call Matvaretabellen API live | Adds a runtime dependency/rate limit for a tiny dataset better vendored |
| Micronutrients in this slice | Much larger scope (storage, targets, biomarker links) — own sprint |

---

## Open questions

1. **Default source per user** — infer from UI language (NO → Matvaretabellen),
   or add an explicit preference in `user_settings`?
2. **USDA Branded** — include it (overlaps OFF) or keep USDA whole-food-only and
   let OFF own branded?
3. **Matvaretabellen refresh cadence** — pin a dataset version and bump
   deliberately (proposed), or schedule periodic re-ingest?
4. **Cache substrate for USDA** — start in-memory (simplest) and only promote to a
   DB-backed cache if quota pressure shows up?
