-- Sprint 3: diet events (correlation overlay annotations)
-- A diet event marks a date — or a date range — when the user changed something
-- about their regimen (started a diet, a fast, a supplement, a medication, …).
-- These are rendered as annotations on top of the biomarker trend charts so the
-- user can eyeball whether a change lines up with a shift in their numbers.
--
-- NOTE: these annotations support *visual* correlation only. Correlation is not
-- causation; nothing here implies a clinical cause-and-effect relationship.
--
-- RLS keeps every row strictly self-scoped, like the rest of the schema.

create table public.diet_events (
    id          uuid        primary key default uuid_generate_v4(),
    user_id     uuid        not null references auth.users(id) on delete cascade,
    -- Short human label shown on the chart, e.g. "Started carnivore".
    label       text        not null,
    -- What kind of change this is — drives the annotation's default colour.
    kind        text        not null default 'diet'
                            check (kind in ('diet', 'fast', 'supplement', 'medication', 'lifestyle', 'other')),
    -- When the change took effect. ended_on is optional: if set, the annotation
    -- is drawn as a shaded period; if null, it is a single dated marker line.
    started_on  date        not null,
    ended_on    date,
    note        text,
    created_at  timestamptz not null default now(),
    -- A period must not end before it starts.
    check (ended_on is null or ended_on >= started_on)
);

create index on public.diet_events (user_id, started_on);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.diet_events enable row level security;

create policy "users_own_diet_events" on public.diet_events
    for all using (auth.uid() = user_id);
