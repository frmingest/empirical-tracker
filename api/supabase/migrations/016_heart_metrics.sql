-- Sprint 13 / ADR-TBD: Apple Watch heart signals via HealthKit.
--
-- Adds three nullable heart-metric columns to `body_metrics` so the iOS
-- HealthSync layer can store resting heart rate, heart rate variability (SDNN),
-- and daily-average heart rate alongside the existing weight / BP fields.
-- All columns are nullable — existing rows are unaffected.

ALTER TABLE body_metrics
    ADD COLUMN IF NOT EXISTS heart_rate_bpm         INTEGER,
    ADD COLUMN IF NOT EXISTS resting_heart_rate_bpm INTEGER,
    ADD COLUMN IF NOT EXISTS hrv_ms                 DOUBLE PRECISION;
