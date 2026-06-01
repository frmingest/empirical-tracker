-- Sprint 9 follow-up: whole-foods data sources — provenance column
--
-- The food diary now reads nutrition from more than one database (ADR-018):
--   * Open Food Facts ('off') — branded / barcode products (the existing source)
--   * Matvaretabellen  ('mvt') — lab-analysed Norwegian whole foods
--   * USDA FoodData Central ('usda') — lab-analysed American whole foods
--
-- We record which source each entry came from so the diary can show a small
-- provenance badge and a clinician reading an export can tell a lab-analysed
-- whole-food entry from a crowd-sourced branded one. This is metadata only —
-- we still store the *consumed amounts* on the row (never a live link), so
-- entry durability (ADR-011) is unchanged.
--
-- Existing rows predate multi-source and were logged from Open Food Facts, so
-- they default to 'off'. The column is nullable for forward flexibility (a
-- free-text planned meal carries no source).
--
-- No RLS changes: both tables already enable RLS and scope rows to their owner.
-- The GDPR export/erasure (ADR-013) selects `*`, so this column flows into both
-- the export and the deletion automatically — no repository/USER_TABLES change
-- required, consistent with ADR-016's finding for sodium/saturated fat.

alter table public.food_entries
    add column if not exists source text default 'off';

alter table public.planned_meals
    add column if not exists source text default 'off';
