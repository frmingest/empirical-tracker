# ADR-020: iOS meal plans & calendar

**Status:** Accepted
**Date:** 2026-06-02
**Author:** iOS team
**Sprint:** 7 (iOS)

---

## Context

The backend already exposes a complete meal-plans surface (ADR-012): named,
reusable plans plus a `planned_meals` calendar, all RLS self-scoped, with a
"log to diary" promotion that reuses `POST /food-diary`. Until this sprint the
iOS app had a **placeholder Plan tab** and no client for any of it.

iOS Sprint 7 (see [`../IOS_MIGRATION_PLAN.md`](../IOS_MIGRATION_PLAN.md)) brings the Plan tab to
feature parity with the web client: a week-at-a-glance calendar, multi-week
navigation, per-day energy totals, named-plan CRUD + filtering, done toggles, and
the planned-meal → diary promotion. As with the food diary (ADR-019) this is a
**pure presentation sprint** — no backend changes, consistent with the migration
plan's "reuse the backend" principle (§1.1).

> Numbering note: ADR-012 carries the **web** sprint number (its Sprint 5) because
> it was authored against the web app. This ADR uses the **iOS** sprint numbering
> from the migration plan, where meal plans are Sprint 7.

---

## Decision

### 1. New `Core` DTOs + a new `MealPlans` package

Following the per-domain module structure (migration plan §1.3, mirroring
`FoodDiary` / `DietEvents`):

- **`Core` models** (`MealPlanModels.swift`): `MealPlan`, `PlannedMeal`,
  `MealPlanPayload`, `PlannedMealPayload`, `PlannedMealDonePayload`, and a
  `PlanWeek` grid helper. `PlannedMeal` decodes `done` **defaulting to `false`**
  for older payloads (the same defensive posture as `FoodItem.source`, ADR-019).
- **`MealPlans` package**: `MealPlansRepository` mirrors every route under
  `/meal-plans` — `GET/POST /meal-plans`, `DELETE /meal-plans/{id}`,
  `GET/POST /meal-plans/calendar`, `PATCH`/`DELETE /meal-plans/calendar/{id}` —
  and reuses the food-diary search/barcode proxy for the picker.

Nutrient fields on a `PlannedMeal` are **consumed-amount totals** (already scaled
by `quantityG`), matching the diary's durability rule (ADR-011): we store the
numbers, not a live link.

### 2. Monday-anchored, locale-independent week grid

`PlanWeek` computes a fixed **Monday→Sunday** week regardless of
`Calendar.firstWeekday`, so the grid matches the web client's week boundary on
every device locale. The calendar is fetched **one week at a time** via
`GET /meal-plans/calendar?start=&end=` (inclusive window), and week navigation
re-fetches.

### 3. Reuse the Sprint 6 food pipeline for the picker

The planned-meal picker is the **same** flow as the diary's add-food sheet — source
selector, debounced multi-source search (ADR-018), native barcode scanning
(ADR-019), and a free-text fallback — feeding a quantity step
(`ScheduleMealSheet`, mirroring `LogFoodSheet`). It reuses the diary's
`BarcodeScannerView`, `FoodSourceBadge`, and `NutritionFormat` directly (same app
target). The picker writes a `PlannedMeal` instead of a `FoodEntry`; the meal slot
is chosen in the picker header rather than per-row.

### 4. Plan grouping, filtering, and SET NULL

A plan filter (All / a named plan) scopes the visible calendar; scheduling while a
plan is selected attaches the new meal to it. **Deleting a plan deletes only the
label** — its meals stay on the calendar, un-grouped. The repository reflects this
`ON DELETE SET NULL` locally (rewriting `planId` to `nil`) so the UI doesn't show a
dangling group before the next refresh.

### 5. Done toggle and "Log to diary" promotion

`done` is advisory (a leading checkmark toggling `PATCH …/{id}`). The explicit
**"Log to diary"** swipe action promotes a planned meal into the food diary via
`POST /food-diary` (reusing `PlannedMeal.diaryPayload`) and marks it `done` — the
deliberate, auditable step from ADR-012. The promotion **preserves the barcode**
via a raw `FoodEntryPayload` initialiser so a promoted branded product keeps its
provenance rather than degrading to a free-text row.

### 6. UX & parity details

- Per-day sections show the weekday, date, and a **day energy total** (present
  values only, never estimated); each day has a "+" to schedule onto it.
- Full EN/NO localisation via the String Catalog; demo/preview mock plans + meals.
- The footer carries the ADR-012 honesty caveat: planned totals sum only the
  nutrients a source provided, and logging to the diary is a separate step.

---

## Consequences

- **Good:** Full web parity for plans + calendar, sharing the Sprint 6 search and
  scanning so the picker needs no new networking and feels identical to the diary.
- **Good:** No backend work — the `/meal-plans` routes, schema, and GDPR
  export/erasure are unchanged.
- **Trade-off:** `planned_meals` predates ADR-016, so it stores no **sodium /
  saturated fat**. A meal promoted to the diary carries those as `nil` → "—" rather
  than re-deriving them; honest, and re-searching to backfill is out of scope.
- **Trade-off:** The picker UI is **re-skinned, not extracted** into one shared
  component (contrast the web's `useFoodSearch` hook). Two small, near-identical
  pickers is cheaper today than refactoring the shipped Sprint 6 sheets; if a third
  consumer appears, extract then.
- **Carried from ADR-012:** plans are groupings, **not** copyable templates;
  `done` does not auto-log; free-text meals contribute nothing to totals.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Extract a shared `FoodSearch` component now | Would refactor working Sprint 6 sheets for a single new consumer; re-skin is lower-risk and the duplication is small. |
| Fetch the whole visible range (multi-week) at once | The endpoint and web both page by week; one-week fetch keeps payloads small and matches the navigation model. |
| Use `Calendar.firstWeekday` for the week start | Norwegian locale is Monday-first anyway, but pinning Monday in code guarantees parity with the web week boundary on any locale. |
| Auto-log on `done` | Surprising and hard to undo (ADR-012); the explicit "Log to diary" action keeps the diary a deliberate record. |
