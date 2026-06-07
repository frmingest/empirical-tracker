-- Sprint 12 fix: enforce one row per (user_id, measured_on) and provide a
-- COALESCE-merge upsert function for the HealthKit batch endpoint.
--
-- Problem: the HealthKit sync uploaded one row per metric type per day
-- (weight, BP, resting HR, HRV, avg HR = up to 5 rows per day). With 7 years
-- of Apple Health history that inflates to ~12 000+ rows, silently truncating
-- the most recent data under the 10 000-row list cap.
--
-- Fix:
--   1. Collapse existing multi-row days into one row per (user_id, measured_on),
--      keeping the most populated row and merging any fields it lacks from
--      sibling rows on the same day.
--   2. Add a UNIQUE constraint so future writes can use ON CONFLICT COALESCE.
--   3. Add a helper function `upsert_body_metric` called by the batch endpoint.

-- ── 1. Deduplicate existing rows ───────────────────────────────────────────
-- For each (user_id, measured_on) group, create one merged row then delete the rest.

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT user_id, measured_on
    FROM body_metrics
    GROUP BY user_id, measured_on
    HAVING count(*) > 1
  LOOP
    -- Insert (or update the oldest row) with COALESCE-merged values from all
    -- sibling rows, then delete the extras.
    WITH ranked AS (
      SELECT id,
             row_number() OVER (PARTITION BY user_id, measured_on ORDER BY created_at) AS rn
      FROM body_metrics
      WHERE user_id = r.user_id AND measured_on = r.measured_on
    ),
    merged AS (
      SELECT
        min(id)                              AS keep_id,
        max(weight_kg)                       AS weight_kg,
        max(waist_cm)                        AS waist_cm,
        max(systolic)                        AS systolic,
        max(diastolic)                       AS diastolic,
        max(heart_rate_bpm)                  AS heart_rate_bpm,
        max(resting_heart_rate_bpm)          AS resting_heart_rate_bpm,
        max(hrv_ms)                          AS hrv_ms,
        max(note)                            AS note,
        -- prefer healthkit source if any sibling has it
        CASE WHEN bool_or(source = 'healthkit') THEN 'healthkit'
             WHEN bool_or(source = 'withings')  THEN 'withings'
             ELSE 'manual' END               AS source
      FROM body_metrics
      WHERE user_id = r.user_id AND measured_on = r.measured_on
    )
    UPDATE body_metrics bm
    SET weight_kg            = m.weight_kg,
        waist_cm             = m.waist_cm,
        systolic             = m.systolic,
        diastolic            = m.diastolic,
        heart_rate_bpm       = m.heart_rate_bpm,
        resting_heart_rate_bpm = m.resting_heart_rate_bpm,
        hrv_ms               = m.hrv_ms,
        note                 = m.note,
        source               = m.source
    FROM merged m
    WHERE bm.id = m.keep_id;

    DELETE FROM body_metrics
    WHERE user_id = r.user_id
      AND measured_on = r.measured_on
      AND id <> (
        SELECT min(id) FROM body_metrics
        WHERE user_id = r.user_id AND measured_on = r.measured_on
      );
  END LOOP;
END $$;

-- ── 2. Unique constraint ───────────────────────────────────────────────────
ALTER TABLE body_metrics
  ADD CONSTRAINT body_metrics_user_day_unique UNIQUE (user_id, measured_on);

-- ── 3. Batch COALESCE-merge upsert function ───────────────────────────────
-- Called by the FastAPI batch endpoint via db.rpc("upsert_body_metrics_batch", {rows: [...]}).
-- Accepts a JSONB array of metric objects, inserts each as a new row or merges
-- non-NULL incoming fields into the existing row for that (user_id, measured_on),
-- never overwriting an existing value with NULL.
--
-- Single RPC call for an entire batch → no N+1 round-trips.

CREATE OR REPLACE FUNCTION upsert_body_metrics_batch(
  p_user_id uuid,
  p_rows    jsonb   -- array of metric objects
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r jsonb;
BEGIN
  FOR r IN SELECT jsonb_array_elements(p_rows)
  LOOP
    INSERT INTO body_metrics (
      user_id, measured_on,
      weight_kg, waist_cm, systolic, diastolic,
      heart_rate_bpm, resting_heart_rate_bpm, hrv_ms,
      note, source
    ) VALUES (
      p_user_id,
      (r->>'measured_on')::date,
      (r->>'weight_kg')::double precision,
      (r->>'waist_cm')::double precision,
      (r->>'systolic')::integer,
      (r->>'diastolic')::integer,
      (r->>'heart_rate_bpm')::integer,
      (r->>'resting_heart_rate_bpm')::integer,
      (r->>'hrv_ms')::double precision,
      r->>'note',
      COALESCE(r->>'source', 'manual')
    )
    ON CONFLICT (user_id, measured_on) DO UPDATE SET
      weight_kg              = COALESCE((r->>'weight_kg')::double precision,    body_metrics.weight_kg),
      waist_cm               = COALESCE((r->>'waist_cm')::double precision,     body_metrics.waist_cm),
      systolic               = COALESCE((r->>'systolic')::integer,              body_metrics.systolic),
      diastolic              = COALESCE((r->>'diastolic')::integer,             body_metrics.diastolic),
      heart_rate_bpm         = COALESCE((r->>'heart_rate_bpm')::integer,        body_metrics.heart_rate_bpm),
      resting_heart_rate_bpm = COALESCE((r->>'resting_heart_rate_bpm')::integer, body_metrics.resting_heart_rate_bpm),
      hrv_ms                 = COALESCE((r->>'hrv_ms')::double precision,       body_metrics.hrv_ms),
      note                   = COALESCE(r->>'note',                             body_metrics.note),
      -- Keep 'manual' source if an explicit user entry already exists;
      -- otherwise use the incoming source tag.
      source                 = CASE
                                 WHEN body_metrics.source = 'manual' THEN 'manual'
                                 ELSE COALESCE(r->>'source', 'manual')
                               END;
  END LOOP;
END;
$$;

-- Grant execute to the authenticated role used by PostgREST / Supabase functions.
GRANT EXECUTE ON FUNCTION upsert_body_metrics_batch TO authenticated;
GRANT EXECUTE ON FUNCTION upsert_body_metrics_batch TO service_role;
