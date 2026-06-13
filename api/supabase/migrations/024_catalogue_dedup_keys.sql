-- ADR-034: deterministic de-duplication keys for the anonymous food_catalogue.
--
-- The catalogue's only dedup was a UNIQUE on the raw `barcode`, so the same
-- product was donated as a fresh row whenever it had no barcode (whole foods,
-- deli/restaurant items, label-scans without a code) or whenever two users'
-- barcodes for one product differed only by format (UPC-A vs EAN-13 vs a
-- leading-zero encoding). This migration gives every donated row a generated,
-- normalised key so the same product converges on one row regardless of who
-- donates it or how their barcode was encoded.
--
-- Run manually in the Supabase SQL editor (numbered-migration convention), and
-- deploy together with the matching app change (app/food_sources/custom.py),
-- which upserts on these keys instead of the raw barcode.

-- ── 1. Generated, normalised dedup keys ─────────────────────────────────────────
-- Generated + STORED so the database is the single source of truth: the key can
-- never drift from the facts it derives from, and there is no second writer to
-- keep in step. A row has exactly one non-null key — barcoded rows key on
-- `barcode_norm`, barcodeless rows on `dedup_key`.

ALTER TABLE food_catalogue
    ADD COLUMN barcode_norm text GENERATED ALWAYS AS (
        lpad(NULLIF(regexp_replace(coalesce(barcode, ''), '\D', '', 'g'), ''), 14, '0')
    ) STORED;

ALTER TABLE food_catalogue
    ADD COLUMN dedup_key text GENERATED ALWAYS AS (
        CASE
            WHEN NULLIF(regexp_replace(coalesce(barcode, ''), '\D', '', 'g'), '') IS NULL
            THEN lower(btrim(coalesce(food_name, ''))) || '|'
              || lower(btrim(coalesce(brand, ''))) || '|'
              || coalesce(round(serving_g)::text, '')
            ELSE NULL
        END
    ) STORED;

COMMENT ON COLUMN food_catalogue.barcode_norm IS
    'ADR-034: barcode digits left-padded to GTIN-14 so UPC-A/EAN-13/leading-zero '
    'variants of one product share a key; NULL for barcodeless rows. Generated — '
    'never written directly; the donation upsert targets it via ON CONFLICT.';
COMMENT ON COLUMN food_catalogue.dedup_key IS
    'ADR-034: lower(name)|lower(brand)|round(serving_g) natural key for barcodeless '
    'rows so the same product from different users merges; NULL when a barcode '
    'exists (barcode_norm governs those). Generated.';

-- ── 2. Collapse the duplicates already in the table ─────────────────────────────
-- A unique index can't be created over data that already contains duplicates, so
-- merge first: per key keep the most complete row (fewest NULL facts; oldest
-- donation breaks ties), repoint the user-owned forward pointers from losers to
-- the survivor (ADR-029), then delete the losers. Conservative by design — the
-- survivor's own facts are kept as-is (no cross-row coalescing) and exact-key
-- only (no fuzzy near-duplicate matching); both are deferred to the
-- master-record follow-up ADR.

CREATE TEMP TABLE _cat_dupe_map AS
WITH ranked AS (
    SELECT
        id,
        first_value(id) OVER (
            PARTITION BY coalesce(barcode_norm, dedup_key)
            ORDER BY
                ( (energy_kcal     IS NOT NULL)::int
                + (carbs_g         IS NOT NULL)::int
                + (protein_g       IS NOT NULL)::int
                + (fat_g           IS NOT NULL)::int
                + (saturated_fat_g IS NOT NULL)::int
                + (sodium_mg       IS NOT NULL)::int
                + (serving_g       IS NOT NULL)::int
                + (ingredients     IS NOT NULL)::int
                + (brand           IS NOT NULL)::int ) DESC,
                donated_at ASC,
                id ASC
        ) AS survivor_id
    FROM food_catalogue
)
SELECT id, survivor_id
FROM ranked
WHERE id <> survivor_id;

-- Keep the ADR-029 back-pointers valid: losers' twins are about to disappear, so
-- point the user rows that referenced them at the survivor that remains.
UPDATE custom_foods cf
SET    catalogue_id = m.survivor_id
FROM   _cat_dupe_map m
WHERE  cf.catalogue_id = m.id;

DELETE FROM food_catalogue
WHERE  id IN (SELECT id FROM _cat_dupe_map);

DROP TABLE _cat_dupe_map;

-- ── 3. Swap raw-barcode uniqueness for the normalised keys ──────────────────────
-- Full (non-partial) unique indexes on nullable columns: Postgres treats NULLs as
-- distinct, so barcodeless rows (NULL barcode_norm) and barcoded rows (NULL
-- dedup_key) never collide on the index that doesn't apply to them. Full (not
-- partial) is required so the donation upserts' ON CONFLICT can infer the index —
-- PostgREST's on_conflict names columns only, not a WHERE predicate.

ALTER TABLE food_catalogue DROP CONSTRAINT IF EXISTS food_catalogue_barcode_key;
DROP INDEX IF EXISTS food_catalogue_barcode_idx;

CREATE UNIQUE INDEX food_catalogue_barcode_norm_key
    ON food_catalogue (barcode_norm);
CREATE UNIQUE INDEX food_catalogue_dedup_key_key
    ON food_catalogue (dedup_key);
