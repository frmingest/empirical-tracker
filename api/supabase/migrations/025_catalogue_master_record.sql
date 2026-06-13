-- ADR-035: master-record lifecycle for the anonymous food_catalogue.
--
-- ADR-034 made "one product, one row" true by construction (a generated dedup
-- key + a unique index) but left the row's *lifecycle* to this follow-up:
--   1. a corroboration count,
--   2. a derived `verified` master flag, and
--   3. a conflict policy replacing last-writer-wins (a single later donation must
--      not silently overwrite a corroborated record, nor null out a known fact).
--
-- All three are done atomically inside one donation function (`donate_catalogue`)
-- so there is no read-modify-write race. The app change (app/food_sources/
-- custom.py) calls that function via .rpc(); run this migration FIRST.
--
-- Compliance (ADR-027/029/034): the catalogue stays anonymous. The counter added
-- here is a BARE integer — it stores no contributor identity and no per-user mark.
-- It counts "an independent user row newly linked to this record", deciding that
-- from the donor's OWN forward-only back-pointer (custom_foods.catalogue_id), not
-- from anything stored on the catalogue. It is a corroboration proxy, NOT a
-- verified distinct-user count (see ADR-035 Consequences).

-- ── 1. Corroboration count + derived master flag ────────────────────────────────

ALTER TABLE food_catalogue
    ADD COLUMN contributor_count integer NOT NULL DEFAULT 1;

ALTER TABLE food_catalogue
    ADD COLUMN verified boolean GENERATED ALWAYS AS (contributor_count >= 2) STORED;

COMMENT ON COLUMN food_catalogue.contributor_count IS
    'ADR-035: bare corroboration counter — how many times an independent user row '
    'newly linked to this record. Stores NO contributor identity (GDPR Recital 26). '
    'A corroboration proxy, not a distinct-user count; written only by '
    'donate_catalogue().';
COMMENT ON COLUMN food_catalogue.verified IS
    'ADR-035: master flag, generated as contributor_count >= 2 so it cannot drift '
    'from the count. Two independent agreements = the trusted record; its facts are '
    'then frozen against single-donor overwrite.';

-- ── 2. Atomic donation: upsert + conflict policy + corroboration count ───────────
-- Replaces ADR-034's plain PostgREST upsert. Counting and the conflict policy must
-- read the existing row's state and write back in one step; a PostgREST upsert
-- can't express conditional SETs or an atomic increment, and a Python read-then-
-- write would race concurrent donations. So the whole thing is one
-- INSERT … ON CONFLICT … DO UPDATE inside this function.
--
--   p_facts              jsonb of the donated factual fields (_CATALOGUE_FIELDS)
--                        plus donated_at. Keeps the function agnostic to the field
--                        list at the call boundary (ADR-034's single source).
--   p_prior_catalogue_id the donor row's CURRENT custom_foods.catalogue_id, or NULL.
--                        If it already equals the record we hit, this is a re-sync
--                        of an already-counted link → no increment; otherwise the
--                        row is newly linking → +1. No identity is read to decide.
--
-- Conflict policy (per factual column):
--   verified row  → keep the existing value (single donor can't overwrite it)
--   otherwise     → coalesce(new, existing): newest non-null wins, never nulls out
--                   a known fact (a strict improvement on ADR-034 last-writer-wins).
-- The flip to verified happens on the 2nd contributor: DO UPDATE sees the OLD row
-- (verified=false, count=1), so that donation's facts win AND the count → 2.

CREATE OR REPLACE FUNCTION donate_catalogue(
    p_facts jsonb,
    p_prior_catalogue_id uuid DEFAULT NULL
)
RETURNS food_catalogue
LANGUAGE plpgsql
AS $$
DECLARE
    result food_catalogue;
    has_barcode boolean :=
        NULLIF(regexp_replace(coalesce(p_facts->>'barcode', ''), '\D', '', 'g'), '')
        IS NOT NULL;
BEGIN
    IF has_barcode THEN
        INSERT INTO food_catalogue AS fc (
            food_name, brand, barcode, energy_kcal, carbs_g, protein_g, fat_g,
            saturated_fat_g, sodium_mg, serving_g, ingredients, donated_at
        )
        VALUES (
            p_facts->>'food_name',
            p_facts->>'brand',
            p_facts->>'barcode',
            (p_facts->>'energy_kcal')::numeric,
            (p_facts->>'carbs_g')::numeric,
            (p_facts->>'protein_g')::numeric,
            (p_facts->>'fat_g')::numeric,
            (p_facts->>'saturated_fat_g')::numeric,
            (p_facts->>'sodium_mg')::numeric,
            (p_facts->>'serving_g')::numeric,
            p_facts->>'ingredients',
            (p_facts->>'donated_at')::date
        )
        ON CONFLICT (barcode_norm) DO UPDATE SET
            food_name       = CASE WHEN fc.verified THEN fc.food_name       ELSE coalesce(EXCLUDED.food_name,       fc.food_name)       END,
            brand           = CASE WHEN fc.verified THEN fc.brand           ELSE coalesce(EXCLUDED.brand,           fc.brand)           END,
            energy_kcal     = CASE WHEN fc.verified THEN fc.energy_kcal     ELSE coalesce(EXCLUDED.energy_kcal,     fc.energy_kcal)     END,
            carbs_g         = CASE WHEN fc.verified THEN fc.carbs_g         ELSE coalesce(EXCLUDED.carbs_g,         fc.carbs_g)         END,
            protein_g       = CASE WHEN fc.verified THEN fc.protein_g       ELSE coalesce(EXCLUDED.protein_g,       fc.protein_g)       END,
            fat_g           = CASE WHEN fc.verified THEN fc.fat_g           ELSE coalesce(EXCLUDED.fat_g,           fc.fat_g)           END,
            saturated_fat_g = CASE WHEN fc.verified THEN fc.saturated_fat_g ELSE coalesce(EXCLUDED.saturated_fat_g, fc.saturated_fat_g) END,
            sodium_mg       = CASE WHEN fc.verified THEN fc.sodium_mg       ELSE coalesce(EXCLUDED.sodium_mg,       fc.sodium_mg)       END,
            serving_g       = CASE WHEN fc.verified THEN fc.serving_g       ELSE coalesce(EXCLUDED.serving_g,       fc.serving_g)       END,
            ingredients     = CASE WHEN fc.verified THEN fc.ingredients     ELSE coalesce(EXCLUDED.ingredients,     fc.ingredients)     END,
            donated_at      = EXCLUDED.donated_at,
            contributor_count = fc.contributor_count
                + CASE WHEN fc.id IS DISTINCT FROM p_prior_catalogue_id THEN 1 ELSE 0 END
        RETURNING fc.* INTO result;
    ELSE
        INSERT INTO food_catalogue AS fc (
            food_name, brand, barcode, energy_kcal, carbs_g, protein_g, fat_g,
            saturated_fat_g, sodium_mg, serving_g, ingredients, donated_at
        )
        VALUES (
            p_facts->>'food_name',
            p_facts->>'brand',
            p_facts->>'barcode',
            (p_facts->>'energy_kcal')::numeric,
            (p_facts->>'carbs_g')::numeric,
            (p_facts->>'protein_g')::numeric,
            (p_facts->>'fat_g')::numeric,
            (p_facts->>'saturated_fat_g')::numeric,
            (p_facts->>'sodium_mg')::numeric,
            (p_facts->>'serving_g')::numeric,
            p_facts->>'ingredients',
            (p_facts->>'donated_at')::date
        )
        ON CONFLICT (dedup_key) DO UPDATE SET
            food_name       = CASE WHEN fc.verified THEN fc.food_name       ELSE coalesce(EXCLUDED.food_name,       fc.food_name)       END,
            brand           = CASE WHEN fc.verified THEN fc.brand           ELSE coalesce(EXCLUDED.brand,           fc.brand)           END,
            energy_kcal     = CASE WHEN fc.verified THEN fc.energy_kcal     ELSE coalesce(EXCLUDED.energy_kcal,     fc.energy_kcal)     END,
            carbs_g         = CASE WHEN fc.verified THEN fc.carbs_g         ELSE coalesce(EXCLUDED.carbs_g,         fc.carbs_g)         END,
            protein_g       = CASE WHEN fc.verified THEN fc.protein_g       ELSE coalesce(EXCLUDED.protein_g,       fc.protein_g)       END,
            fat_g           = CASE WHEN fc.verified THEN fc.fat_g           ELSE coalesce(EXCLUDED.fat_g,           fc.fat_g)           END,
            saturated_fat_g = CASE WHEN fc.verified THEN fc.saturated_fat_g ELSE coalesce(EXCLUDED.saturated_fat_g, fc.saturated_fat_g) END,
            sodium_mg       = CASE WHEN fc.verified THEN fc.sodium_mg       ELSE coalesce(EXCLUDED.sodium_mg,       fc.sodium_mg)       END,
            serving_g       = CASE WHEN fc.verified THEN fc.serving_g       ELSE coalesce(EXCLUDED.serving_g,       fc.serving_g)       END,
            ingredients     = CASE WHEN fc.verified THEN fc.ingredients     ELSE coalesce(EXCLUDED.ingredients,     fc.ingredients)     END,
            donated_at      = EXCLUDED.donated_at,
            contributor_count = fc.contributor_count
                + CASE WHEN fc.id IS DISTINCT FROM p_prior_catalogue_id THEN 1 ELSE 0 END
        RETURNING fc.* INTO result;
    END IF;

    RETURN result;
END;
$$;

-- The catalogue is service-role-writable only (ADR-026). This function must not
-- become a way for a signed-in user to mint or tamper with catalogue rows, so
-- only the service role may execute it.
REVOKE ALL ON FUNCTION donate_catalogue(jsonb, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION donate_catalogue(jsonb, uuid) TO service_role;
