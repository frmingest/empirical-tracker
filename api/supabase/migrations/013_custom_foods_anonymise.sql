-- ADR-027: retain the custom-food catalogue by anonymising on delete.
--
-- When a user deletes a *public* custom food (or their whole account), we keep
-- the factual catalogue value by copying it here and then hard-deleting the
-- user-owned `custom_foods` row. `food_catalogue` is a donated-facts table: it
-- has NO `user_id`, so it is intentionally NOT a USER_TABLES member and never
-- appears in any individual's GDPR export — the rows are anonymous product data
-- (GDPR Recital 26), not personal data.
--
-- What is dropped on donation (see app/food_sources/custom.py):
--   * user_id    — the link to the individual is severed (anonymisation, not
--                  pseudonymisation; keeping user_id would not be enough).
--   * created_at — replaced by a coarse `donated_at` date with no tie to the
--                  user's activity timeline.
--   * ocr_raw    — unbounded free text scraped off a photographed label; it can
--                  contain anything and cannot be guaranteed non-identifying, so
--                  it is never donated. It lives only on the user-owned row and
--                  dies with it.
-- Only the factual product columns survive.

CREATE TABLE food_catalogue (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    food_name       text        NOT NULL,
    brand           text,
    barcode         text        UNIQUE,
    energy_kcal     numeric,
    carbs_g         numeric,
    protein_g       numeric,
    fat_g           numeric,
    saturated_fat_g numeric,
    sodium_mg       numeric,
    serving_g       numeric,
    ingredients     text,
    -- Coarse donation date only (no time-of-day, no user link).
    donated_at      date        NOT NULL DEFAULT current_date
);

-- Fast barcode lookup / upsert target (sparse — many donated items have no
-- barcode). The UNIQUE on `barcode` lets re-donating the same product update its
-- facts rather than piling up duplicates; NULL barcodes stay distinct in
-- Postgres, so barcodeless items are simply appended.
CREATE INDEX food_catalogue_barcode_idx ON food_catalogue (barcode)
    WHERE barcode IS NOT NULL;

-- Efficient name search (mirrors the user-scoped index on custom_foods).
CREATE INDEX food_catalogue_name_idx ON food_catalogue (food_name);

ALTER TABLE food_catalogue ENABLE ROW LEVEL SECURITY;

-- Readable by any authenticated user — the donated facts are a shared catalogue,
-- exactly like the read-only external sources. Writes happen only on the
-- service-role client (the sanctioned donation path, ADR-026), which bypasses
-- RLS, so there is deliberately no INSERT/UPDATE/DELETE policy here.
CREATE POLICY "food_catalogue_select"
    ON food_catalogue FOR SELECT
    TO authenticated
    USING (true);
