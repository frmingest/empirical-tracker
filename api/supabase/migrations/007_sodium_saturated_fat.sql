-- Sprint 9: food-diary depth — sodium and saturated fat
--
-- The diary tracked four macros (energy, carbs, protein, fat). Sprint 9 adds
-- the two nutrients the biomarker side cares about most for these diets:
--   * sodium       — the labs emphasise electrolyte management (and BP, once
--                    body metrics land in Sprint 10).
--   * saturated fat — the driver of the LDL response the lipid panel tracks.
--
-- Like the existing nutrient columns, these store the amounts actually consumed
-- (per-100 g source value × quantity / 100), computed when the entry is created,
-- so the diary stays correct even if the upstream product data later changes.
--
-- Sodium is stored in milligrams (the conventional label unit); saturated fat in
-- grams, matching the other macro columns. We add the same pair to planned_meals
-- so a planned meal logged to the diary (Sprint 5 "Log to diary") keeps these
-- values rather than dropping them.
--
-- No RLS changes: both tables already enable RLS and scope rows to their owner.
-- The GDPR export/erasure (ADR-013) selects `*`, so these columns flow into both
-- the export and the deletion automatically — no repository change required.

alter table public.food_entries
    add column if not exists sodium_mg        numeric,
    add column if not exists saturated_fat_g  numeric;

alter table public.planned_meals
    add column if not exists sodium_mg        numeric,
    add column if not exists saturated_fat_g  numeric;
