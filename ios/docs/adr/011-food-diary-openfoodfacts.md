# ADR-011: Food Diary with Open Food Facts Integration

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)  
**Sprint:** 4

---

## Context

To correlate diet with biomarkers, the user first needs to record what they eat.
Sprint 4 adds a **food diary**: a per-day log of foods with their nutrition. To
avoid forcing the user to type nutrition facts by hand (error-prone and tedious),
we integrate a food database for search-and-add.

We need a source that is:
- **Free** (no per-call billing, no API-key gatekeeping),
- **Branded + barcode** coverage (the user logs real supermarket products),
- **Reusable** under a clear licence.

[Open Food Facts](https://world.openfoodfacts.org) (OFF) fits: it's a
collaborative, open database of food products under the **Open Database License
(ODbL)**, free to query, requiring only a descriptive `User-Agent` (no API key).

---

## Decision

- **New `food_entries` table** (migration `005_food_entries.sql`), RLS
  self-scoped. One row per logged food: `logged_on`, `meal`
  (`breakfast`/`lunch`/`dinner`/`snack`/`other`), `food_name`, `brand`,
  `barcode` (the OFF code), `quantity_g`, and the **consumed** nutrient amounts
  `energy_kcal`/`carbs_g`/`protein_g`/`fat_g`, plus `note`.

- **Store consumed amounts, not a product reference.** When a food is logged we
  compute `per-100g × grams / 100` on the client and persist the result. The
  diary therefore stays correct even if the upstream OFF product later changes or
  is deleted, and it survives without a live OFF round-trip on every page view.

- **Backend proxy for OFF**, not direct browser calls (`app/food_diary/`):
  - `GET /food-diary/search?q=` → OFF full-text search (`/cgi/search.pl`)
  - `GET /food-diary/barcode/{code}` → OFF product lookup (`/api/v2/product`)
  - Both **normalise** OFF's messy nutriment field names into a small stable
    shape and attach the required `User-Agent`. Both require auth so the proxy
    can't be used as an open relay.

- **CRUD endpoints** `GET/POST/DELETE /food-diary` follow the existing
  router/repository pattern.

- **New `/food-diary` page** with a date navigator, daily macro totals, an OFF
  search/barcode add box (`FoodSearch`), and entries grouped by meal. A nav link
  is added to the dashboard header. Signed-out visitors see sample entries
  (`MOCK_FOOD_ENTRIES`).

---

## Rationale

### Why proxy OFF through our backend?
Three reasons: (1) OFF asks every caller to send an identifying `User-Agent`,
which is set once server-side; (2) OFF's product JSON has dozens of inconsistent
nutriment keys (`energy-kcal_100g`, `carbohydrates_100g`, …) that are cleaner to
normalise in one place; (3) it avoids CORS issues and keeps the user's food
browsing from going directly to a third party.

### Why store grams + computed macros instead of just the barcode?
The log is a *historical record*. Pinning the consumed values at log time makes
the diary immutable and independent of OFF's evolving, sometimes-incomplete data.

### Why debounce search?
OFF rate-limits search to ~10 requests/minute. The client waits ~450 ms after the
user stops typing and ignores stale responses, keeping us well under the limit.

### Why `httpx`?
Already present in the repo and used by `supabase`; a synchronous `httpx.Client`
inside the request handler is simple and sufficient for two low-volume endpoints.

---

## Medical / nutrient-accuracy considerations

- **No invented numbers.** Nutrition is taken **as published by OFF** and scaled
  linearly by mass only. We never estimate missing values; absent fields render
  as "—". This is documented in `docs/NUTRITION_DATA.md`.
- **Attribution.** The page credits Open Food Facts and the ODbL licence, and
  notes values may be incomplete.
- Macros shown (energy, carbohydrate, protein, fat) are the standard four; we do
  not derive clinical advice from them.

---

## Consequences

- **Good:** Real branded/barcode foods can be logged in seconds; macros fill in
  automatically.
- **Good:** Diary entries are durable and self-contained.
- **Good:** OFF is free and key-less; no secret to manage, no billing risk.
- **Trade-off:** OFF coverage/quality is crowd-sourced and uneven — some products
  lack macros. Mitigated by showing "—" and allowing manual quantity.
- **Trade-off:** A backend round-trip per search (vs. calling OFF directly), in
  exchange for a consistent `User-Agent`, normalisation, and no CORS.
- **Trade-off:** OFF outages surface as a `502` and an inline "try again"; the
  diary itself keeps working since entries are stored locally in our DB.

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| USDA FoodData Central | Requires an API key; weaker on non-US branded/barcode items |
| Nutritionix / Edamam | Paid tiers / API-key gatekeeping; not free-as-in-OFF |
| Call OFF directly from the browser | Can't set a shared `User-Agent`; CORS; leaks browsing to third party |
| Store only the barcode, fetch macros on render | Breaks if OFF data changes/disappears; needs OFF up on every view |
| Free-text food entry only | Defeats the purpose; error-prone, no macros |
