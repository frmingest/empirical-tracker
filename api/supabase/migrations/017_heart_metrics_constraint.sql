-- Fix at_least_one_metric constraint to cover heart-metric columns (016).
--
-- Migration 008 created the constraint before the three heart-signal columns
-- (heart_rate_bpm, resting_heart_rate_bpm, hrv_ms) existed.  Any HealthKit
-- upload that carries *only* heart data (no weight, waist, or blood pressure)
-- therefore violated the constraint and was silently rejected, so Apple Health
-- heart metrics never appeared in the app.
--
-- Drop the old constraint and re-add it with all six metric columns.

ALTER TABLE body_metrics DROP CONSTRAINT IF EXISTS at_least_one_metric;

ALTER TABLE body_metrics
    ADD CONSTRAINT at_least_one_metric CHECK (
        weight_kg              IS NOT NULL
        OR waist_cm            IS NOT NULL
        OR systolic            IS NOT NULL
        OR heart_rate_bpm      IS NOT NULL
        OR resting_heart_rate_bpm IS NOT NULL
        OR hrv_ms              IS NOT NULL
    );
