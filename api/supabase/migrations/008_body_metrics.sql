-- Sprint 10: body metrics & longitudinal context
--
-- For diet tracking, weight, waist, and blood pressure respond faster — and
-- often matter more — than most labs, and blood pressure ties directly to the
-- app's sodium emphasis (Sprint 9). Until now the app held no body metrics at
-- all. One row records a measurement session on a given day; every metric is
-- optional, so a user can log just their weight one day and just their blood
-- pressure another. These plot on the same timeline, with the same diet-event
-- correlation overlay, as the biomarker charts.
--
-- Weight is stored in kilograms, waist in centimetres, blood pressure as the two
-- conventional integers (systolic / diastolic, mmHg). Blood pressure is a pair:
-- a reading is meaningless with only one half, so the two are constrained to be
-- both present or both absent.
--
-- A row must carry at least one metric — an empty measurement is never stored.
--
-- RLS keeps every row strictly self-scoped, like the rest of the schema.

create table public.body_metrics (
    id           uuid        primary key default uuid_generate_v4(),
    user_id      uuid        not null references auth.users(id) on delete cascade,
    measured_on  date        not null,
    -- Weight in kilograms; feeds the Sprint 9 protein g/kg target once that
    -- targets UI lands.
    weight_kg    numeric     check (weight_kg is null or weight_kg > 0),
    -- Waist circumference in centimetres.
    waist_cm     numeric     check (waist_cm is null or waist_cm > 0),
    -- Blood pressure, mmHg. Both halves or neither.
    systolic     integer     check (systolic is null or (systolic between 40 and 300)),
    diastolic    integer     check (diastolic is null or (diastolic between 20 and 200)),
    note         text,
    created_at   timestamptz not null default now(),
    -- A blood-pressure reading needs both numbers.
    constraint bp_pair check ((systolic is null) = (diastolic is null)),
    -- Reject an empty measurement (no metric at all).
    constraint at_least_one_metric check (
        weight_kg is not null
        or waist_cm is not null
        or systolic is not null
    )
);

create index on public.body_metrics (user_id, measured_on);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.body_metrics enable row level security;

create policy "users_own_body_metrics" on public.body_metrics
    for all using (auth.uid() = user_id);
