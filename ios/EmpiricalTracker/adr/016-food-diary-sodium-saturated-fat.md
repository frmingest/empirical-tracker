# ADR-016: Food-diary depth — sodium & saturated fat + kJ→kcal fallback

**Status:** Accepted  
**Date:** 2026-06-01  
**Author:** Faiz (solo developer)  
**Sprint:** 9 (high-priority slice)

---

## Context

The clinical review (see "Clinical-feedback roadmap" in `docs/SOLUTION.md`) found
that the food diary's four macros (energy, carbohydrate, protein, fat) omit the
two nutrients the **biomarker** side of the app cares about most for these diets:

- **Sodium** — the labs emphasise electrolyte management, and sodium ties
  directly to the blood-pressure tracking that lands in Sprint 10.
- **Saturated fat** — the dietary driver of the LDL response the lipid panel
  (and the Sprint 7 clinical targets) tracks.

A second, smaller finding: energy frequently showed "—" unnecessarily, because
the Open Food Facts (OFF) client only read `energy-kcal_100g` and many OFF
products carry only the kilojoule field.

Sprint 9 is large, so it is split. **This slice ships the "High"-severity item
(sodium + saturated fat) and the "Low" quick win (kJ→kcal fallback).** The
"Medium" items — a whole-foods reference source (USDA FoodData Central /
Norwegian *Matvaretabellen*) alongside OFF, and daily targets / needs context
(including protein in g/kg body weight) — are deferred to a follow-up. The g/kg
target in particular depends on body weight, which arrives in Sprint 10.

---

## Decision

### 1. Two new nutrient columns, stored as consumed amounts

Following the existing macro pattern (ADR-011), we add `sodium_mg` and
`saturated_fat_g` to **`food_entries`** and store the **amount actually
consumed** (per-100 g source value × grams / 100, computed at entry time), not a
reference to the product — so the diary stays correct even if the upstream OFF
data later changes.

- **Sodium in milligrams** — the conventional nutrition-label unit, and a more
  legible scale than grams for typical intakes.
- **Saturated fat in grams** — matches the other macro columns.

The same two columns are added to **`planned_meals`** (migration `007`), because
planned meals mirror food entries and the Sprint 5 "Log to diary" action copies a
planned meal into the diary — without the columns there, those values would be
silently dropped on the way across.

### 2. OFF field mapping — prefer measured, derive only when necessary

In `openfoodfacts._normalise`:

- **Saturated fat:** `saturated-fat_100g`, taken as published.
- **Sodium:** prefer OFF's measured `sodium_100g` (grams → mg). When only
  `salt_100g` is published, derive sodium using the standard EU conversion
  **salt = sodium × 2.5** (so `sodium_g = salt_g / 2.5`), then convert to mg.
  When neither is present, store `None` and the UI shows "—" — we never invent a
  value, consistent with the existing as-published policy.
- **Energy:** prefer `energy-kcal_100g`; fall back to `energy_100g` (kJ) ÷ 4.184
  only when the kcal field is absent.

Each derived value is rounded to one decimal place, like the macros.

### 3. No schema change to the GDPR export/erasure contract

`api/app/account/repository.py` gathers and erases user data with `select("*")`
and a per-user delete, and the CSV export derives its columns dynamically from
the rows. New **columns** on an already-listed table therefore flow into both the
export and the deletion automatically — so the ADR-013 maintenance contract is
satisfied without touching `USER_TABLES` / `DELETE_ORDER`. (That contract still
applies to new **tables**, e.g. Sprint 10's `body_metrics`.)

---

## Consequences

- The diary and meal-plan calendar now surface sodium and saturated-fat totals,
  closing the loop with the electrolyte and lipid emphasis on the labs side.
- Energy is populated for OFF products that carry only kJ, reducing spurious "—".
- The derived-sodium and kJ-conversion factors are fixed constants; OFF data
  quality still varies (the as-published caveats in `docs/NUTRITION_DATA.md`
  continue to apply).
- Still **decision-support, not medical advice**: the diary logs and totals
  intake; it does not interpret it or set targets (targets are the deferred
  Medium follow-up).

---

## Alternatives considered

- **Store sodium in grams.** Rejected — mg is the conventional label unit and
  avoids tiny fractional values for typical foods.
- **Always derive sodium from salt.** Rejected — OFF sometimes carries a measured
  `sodium_100g`; preferring it avoids a needless round-trip through the 2.5 factor.
- **Add the columns to `food_entries` only.** Rejected — it would break "Log to
  diary" fidelity for planned meals; the cost of mirroring the two columns is
  trivial.
- **Bring in the whole-foods source now.** Deferred — a new external integration
  (USDA / Matvaretabellen) is a self-contained Medium item better shipped on its
  own, and unbranded whole-food coverage is independent of these two fields.
