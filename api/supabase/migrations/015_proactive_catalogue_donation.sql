-- ADR-029: donate to the anonymous catalogues proactively (on create/update),
-- not only on delete.
--
-- ADR-027/028 copied a *public* custom food / recipe into its anonymous catalogue
-- (food_catalogue / recipe_catalogue) at the moment of deletion. This migration
-- adds the small piece of state that lets the same anonymising copy happen when
-- the item is first registered and stay in step when it is edited, so the curated
-- catalogue value is captured up front and survives deletion no matter how the
-- user-owned row goes away (per-item delete, account delete, or a cascade).
--
-- `catalogue_id` is a *forward-only*, de-identified pointer from the user-owned
-- row to its anonymous twin. The link lives ONLY on the user's row, so it is
-- erased with the user; the twin carries no reverse link and no user_id, so the
-- anonymisation (GDPR Recital 26) is unchanged — once the source row is deleted
-- there is no path from the catalogue back to the individual. It is used to
--   (1) update the twin in place on edit instead of piling up duplicates, and
--   (2) dedupe reads so a live public item is not shown twice (once from the
--       user table, once from its twin).
--
-- Deliberately NOT a foreign key: a real FK would impose a delete-ordering
-- constraint between the user table and the anonymous catalogue and tie the two
-- together at the schema level, which is exactly the coupling we are avoiding.
-- A dangling pointer is harmless — it is only ever read from the user's side.

ALTER TABLE custom_foods ADD COLUMN catalogue_id uuid;
ALTER TABLE recipes      ADD COLUMN catalogue_id uuid;

COMMENT ON COLUMN custom_foods.catalogue_id IS
    'ADR-029: de-identified pointer to this row''s anonymous food_catalogue twin '
    '(NULL until donated; barcoded items dedupe on barcode instead). Erased with '
    'the user; the twin has no reverse link.';
COMMENT ON COLUMN recipes.catalogue_id IS
    'ADR-029: de-identified pointer to this row''s anonymous recipe_catalogue twin '
    '(NULL until donated). Erased with the user; the twin has no reverse link.';
