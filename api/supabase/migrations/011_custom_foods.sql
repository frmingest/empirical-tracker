-- Custom food catalogue: user-contributed products not in OFF / MVT / USDA.
-- Populated via the iOS barcode-miss → label-scan flow and the manual entry form.
-- Images are never stored (OCR text only; ADR-TBD).

CREATE TABLE custom_foods (
    id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         uuid        NOT NULL REFERENCES auth.users ON DELETE CASCADE,
    food_name       text        NOT NULL,
    brand           text,
    barcode         text,
    source          text        NOT NULL DEFAULT 'custom',
    energy_kcal     numeric,
    carbs_g         numeric,
    protein_g       numeric,
    fat_g           numeric,
    saturated_fat_g numeric,
    sodium_mg       numeric,
    serving_g       numeric,
    ingredients     text,
    ocr_raw         jsonb,
    is_public       boolean     NOT NULL DEFAULT false,
    verified        boolean     NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Fast barcode lookup (sparse — many items have no barcode).
CREATE INDEX custom_foods_barcode_idx ON custom_foods (barcode)
    WHERE barcode IS NOT NULL;

-- Efficient user-scoped name search.
CREATE INDEX custom_foods_user_name_idx ON custom_foods (user_id, food_name);

ALTER TABLE custom_foods ENABLE ROW LEVEL SECURITY;

-- Users see their own items plus any items marked public by others.
CREATE POLICY "custom_foods_select"
    ON custom_foods FOR SELECT
    USING (user_id = auth.uid() OR is_public = true);

CREATE POLICY "custom_foods_insert"
    ON custom_foods FOR INSERT
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "custom_foods_update"
    ON custom_foods FOR UPDATE
    USING (user_id = auth.uid());

CREATE POLICY "custom_foods_delete"
    ON custom_foods FOR DELETE
    USING (user_id = auth.uid());
