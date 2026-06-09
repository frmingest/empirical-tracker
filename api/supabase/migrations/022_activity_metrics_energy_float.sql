-- Fix: change active_energy_kcal from numeric to double precision.
-- Postgres `numeric` is returned as a quoted string by the Supabase REST API,
-- which caused the iOS JSONDecoder to fail silently and show "–" on the cards.
-- `double precision` (float8) serialises as a JSON number, matching the Swift
-- model's `Double?` field and the existing Pydantic `float | None` field.

alter table public.activity_metrics
    alter column active_energy_kcal type double precision
    using active_energy_kcal::double precision;
