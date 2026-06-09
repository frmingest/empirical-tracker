-- ADR-033: activity_metrics table for HealthKit daily sums (steps, active energy, exercise minutes).
-- One row per user per day; re-syncing a day UPSERTs it (mutable daily aggregates).

create extension if not exists "uuid-ossp";

create table public.activity_metrics (
    id                   uuid        primary key default uuid_generate_v4(),
    user_id              uuid        not null references auth.users(id) on delete cascade,
    measured_on          date        not null,
    steps                integer     check (steps is null or steps >= 0),
    active_energy_kcal   numeric     check (active_energy_kcal is null or active_energy_kcal >= 0),
    exercise_minutes     integer     check (exercise_minutes is null or exercise_minutes >= 0),
    source               text        not null default 'healthkit'
                                     check (source in ('healthkit', 'manual')),
    created_at           timestamptz not null default now(),
    updated_at           timestamptz not null default now(),
    constraint activity_metrics_user_day unique (user_id, measured_on),
    constraint at_least_one_activity check (
        steps is not null or active_energy_kcal is not null or exercise_minutes is not null
    )
);

create index on public.activity_metrics (user_id, measured_on);

alter table public.activity_metrics enable row level security;

create policy "users_own_activity_metrics" on public.activity_metrics
    for all using (auth.uid() = user_id);

-- Trigger to keep updated_at current on any update.
create or replace function public.set_activity_metrics_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger trg_activity_metrics_updated_at
    before update on public.activity_metrics
    for each row execute procedure public.set_activity_metrics_updated_at();
