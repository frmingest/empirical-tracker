-- Sprint 11 contract fix: body_metrics provenance
--
-- The iOS model has always carried a `source` field (manual | healthkit | withings)
-- to track whether a reading was hand-entered or synced from Apple Health / Withings.
-- The column was omitted from the original Sprint 10 migration; this adds it so
-- the backend can persist and return it, and the iOS Codable decode no longer fails.
--
-- Default is 'manual' so all historical rows decode correctly with no data loss.

alter table public.body_metrics
    add column if not exists source text not null default 'manual'
        check (source in ('manual', 'healthkit', 'withings'));
