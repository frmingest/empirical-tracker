-- Sprint 1: biomarker catalog, panels, and results
-- RLS enforces strict per-user isolation of health data (GDPR special-category).

create extension if not exists "uuid-ossp";

-- ── Biomarker catalog ──────────────────────────────────────────────────────────
create table public.biomarkers (
    id            uuid        primary key default uuid_generate_v4(),
    user_id       uuid        not null references auth.users(id) on delete cascade,
    name_no       text        not null,
    name_en       text,
    unit          text,
    ref_range_raw text        not null default '',
    ref_low       numeric,
    ref_high      numeric,
    ref_type      text        not null default 'none'
                              check (ref_type in ('bounded', 'lt', 'gt', 'none')),
    created_at    timestamptz not null default now(),
    unique (user_id, name_no)
);

-- ── Blood test panels (one per test date) ─────────────────────────────────────
create table public.panels (
    id         uuid        primary key default uuid_generate_v4(),
    user_id    uuid        not null references auth.users(id) on delete cascade,
    tested_at  date        not null,
    source     text        not null default 'xlsx_import',
    created_at timestamptz not null default now()
);

-- ── Individual biomarker results ──────────────────────────────────────────────
create table public.results (
    id           uuid        primary key default uuid_generate_v4(),
    user_id      uuid        not null references auth.users(id) on delete cascade,
    panel_id     uuid        not null references public.panels(id) on delete cascade,
    biomarker_id uuid        not null references public.biomarkers(id) on delete cascade,
    value        numeric     not null,
    in_range     boolean,
    created_at   timestamptz not null default now(),
    unique (panel_id, biomarker_id)
);

create index on public.results (user_id);
create index on public.results (panel_id);
create index on public.results (biomarker_id);
create index on public.panels  (user_id, tested_at);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.biomarkers enable row level security;
alter table public.panels     enable row level security;
alter table public.results    enable row level security;

create policy "users_own_biomarkers" on public.biomarkers
    for all using (auth.uid() = user_id);

create policy "users_own_panels" on public.panels
    for all using (auth.uid() = user_id);

create policy "users_own_results" on public.results
    for all using (auth.uid() = user_id);
