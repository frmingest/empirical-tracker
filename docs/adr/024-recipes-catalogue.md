# ADR-024: Recipes catalogue and authoring module

**Status:** Accepted
**Date:** 2026-06-04
**Author:** iOS team
**Sprint:** — (feature add)

---

## Context

The app helps people run a carnivore / low-carb protocol and watch the biomarker
response. It already covers *measuring* (biomarkers, body metrics), *logging* (food
diary), and *planning* (the meal-plan calendar). What it lacked was **inspiration**:
a browsable set of recipes that fit the diet, and a way for the user to capture their
own and grow that set.

This ADR records the addition of a **Recipes** surface: a categorised, image-led
catalogue (a new bottom-tab section) plus an **authoring module** to create a recipe
and save it to the database.

## Decision

### 1. Data model — two tables (`012_recipes.sql`)

- **`recipes`** — `title`, `category`, `image_url`, `serving_size`, author-estimated
  per-serving macros (`calories_kcal` / `protein_g` / `fat_g` / `carbs_g`), ordered
  `ingredients` / `instructions` (`jsonb` arrays of free text), an optional `fact`
  blurb (the orange "Recipe Fact" card), and the `is_public` / `is_premium` flags.
- **`recipe_favorites`** — the per-user star (`(user_id, recipe_id)` primary key).

Ingredients and instructions are free text presented as a checklist / numbered steps;
they are never parsed for nutrients, so a structured per-ingredient schema would add
cost without value. **"New!" is derived** (created within the last 14 days), not
stored, so a recipe ages out on its own with no background job.

### 2. Sharing model mirrors `custom_foods` (ADR-011)

RLS scopes authoring strictly to the owner while letting a recipe be shared into a
common catalogue: `recipes_select` is `user_id = auth.uid() OR is_public = true`;
insert / update / delete are owner-only. The service-role API repeats the
`own OR public` filter explicitly (it bypasses RLS), exactly like the food sources.

### 3. API — `/recipes` (`app/recipes/`)

`GET /recipes` (with `category` / `only_free` filters), `GET /recipes/categories`,
`GET /recipes/{id}`, `POST /recipes`, `PUT /recipes/{id}`, `DELETE /recipes/{id}`,
and `PUT /recipes/{id}/favorite`. List/detail responses carry derived `is_favorite`
and `is_new` flags so the cards need no extra round-trip.

### 4. iOS — a `Recipes` SwiftPM package + a new tab

A `RecipesRepository` (in a new local package, mirroring `MealPlans`) owns the
catalogue and the optimistic favourite/create/update/delete mutations. The app target
adds a **Recipes tab** with three screens: the category-grouped catalogue
(`RecipesView`), the recipe detail (`RecipeDetailView` — hero image, estimated-nutrition
card, tappable ingredient checklist, the "Recipe Fact" card, numbered steps), and the
authoring form (`RecipeFormView`), which doubles as the editor for a recipe you own.
Models (`Recipe`, `RecipePayload`) live in `Core` alongside the other DTOs.

## Consequences

- The migration (`012_recipes.sql`) must be run in the Supabase SQL editor before the
  endpoints work, per the project's manual-migration convention.
- Adding a sixth tab means iOS folds the overflow into a system "More" tab on compact
  widths — acceptable for now.
- Favourites and the ingredient/step checkmarks are intentionally separate concerns:
  the star persists (per user), the cooking-mode checkmarks are ephemeral view state.
- The micronutrient / structured-ingredient direction is explicitly **out of scope**;
  recipes stay free-text and author-estimated.
