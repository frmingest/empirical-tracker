# ADR-012: Meal Plans and Calendar

**Status:** Accepted  
**Date:** 2026-06-01  
**Author:** Faiz (solo developer)  
**Sprint:** 5

---

## Context

The food diary (Sprint 4) is **backward-looking**: it records what the user
already ate. The natural complement — and the Sprint 5 deliverable — is the
**forward-looking** half: planning what to eat, laid out on a calendar so a
carnivore/low-carb week can be prepped in advance.

Requirements:

- A **week-at-a-glance calendar** of planned meals, navigable across weeks.
- **Named, reusable plans** ("Carnivore week", "Low-carb reset") to group meals.
- Reuse of the existing nutrition pipeline — a planned meal should carry the same
  macro shape as a diary entry, sourced from Open Food Facts (OFF), so it can be
  **promoted into the diary** once eaten without re-entering anything.
- The same strict per-user RLS isolation as the rest of the health schema.

## Decision

- **Two new tables** (migration `006_meal_plans.sql`), both RLS self-scoped:
  - `meal_plans` — `name`, optional `description`. A label/grouping only.
  - `planned_meals` — one scheduled meal: `scheduled_on`, `meal`
    (`breakfast`/`lunch`/`dinner`/`snack`/`other`, the same slots as
    `food_entries`), `food_name`, `brand`, `barcode`, the consumed-amount
    nutrient columns (`quantity_g`, `energy_kcal`, `carbs_g`, `protein_g`,
    `fat_g`), `note`, a `done` flag (cooked/eaten), and a nullable `plan_id`.

- **`plan_id` is `ON DELETE SET NULL`.** Deleting a plan removes the *label*, not
  the week you already planned — the scheduled meals stay on the calendar,
  un-grouped. (Contrast `user_id`, which is `ON DELETE CASCADE`.)

- **Backend module `app/meal_plans/`** mirrors the diet-events / food-diary
  shape (router + repository, validated with Pydantic, `current_user_id`
  dependency). Endpoints under `/meal-plans`:
  - `GET/POST /meal-plans`, `DELETE /meal-plans/{id}` — manage named plans.
  - `GET /meal-plans/calendar?start=&end=` — planned meals in an inclusive date
    window (the calendar fetches one week at a time).
  - `POST /meal-plans/calendar` — schedule a meal.
  - `PATCH /meal-plans/calendar/{id}` — toggle `done`.
  - `DELETE /meal-plans/calendar/{id}` — remove a scheduled meal.

- **Reuse, not duplication, of OFF search.** The debounced-search + barcode
  state machine was extracted from `FoodSearch` into a shared
  `useFoodSearch` hook (`web/src/lib/useFoodSearch.ts`). The food diary and the
  new `PlannedMealPicker` both consume it; only the *result-picker* UI differs.

- **Planned meal → diary promotion.** A planned meal has a "Log to diary" action
  that creates a `food_entry` (Sprint 4) for its scheduled date and marks the
  planned meal `done`. No new backend surface — it reuses `POST /food-diary`.

- **Free-text fallback.** Not every planned meal is a barcoded product
  ("Ribeye + eggs"), so the picker also accepts a plain name with no macros,
  consistent with the "never invent nutrition" rule (missing values show "—").

## Consequences

- The calendar is a thin week view over `planned_meals`; "applying" a plan
  template across a future week is **not** implemented — plans are groupings, not
  copyable templates. That is a deliberate v1 scope cut (see Alternatives).
- Macro totals on the calendar sum only what OFF provided; free-text meals
  contribute nothing to totals, which is honest but means a planned day can read
  lower than reality.
- `done` is advisory: it does not by itself create a diary entry. Logging to the
  diary is the explicit, auditable step.

## Alternatives considered

- **Plans as copyable templates** (apply "Carnivore week" to any week → clones
  its meals onto those dates). More powerful, but doubles the data model
  (template days vs. scheduled instances) and the UI. Deferred; `plan_id`
  grouping is the foundation it would build on.
- **Auto-logging on `done`.** Rejected: silently writing diary rows on a
  checkbox toggle is surprising and hard to undo. The explicit "Log to diary"
  action keeps the diary a deliberate record.
- **A dedicated `planned_meals` OFF proxy.** Unnecessary — the Sprint 4
  `/food-diary/search` + `/barcode` endpoints already serve normalised OFF data;
  the picker calls them directly via the shared hook.
