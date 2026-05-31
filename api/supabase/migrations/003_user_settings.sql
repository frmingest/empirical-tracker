-- Sprint 2: per-user dashboard preferences (diet focus + custom marker selection)
-- One row per user. RLS keeps it strictly self-scoped like the rest of the schema.

create table public.user_settings (
    user_id        uuid        primary key references auth.users(id) on delete cascade,
    -- Which diet focus is active: 'all' shows everything, the presets hide
    -- markers not relevant to that diet, 'custom' uses custom_markers.
    diet           text        not null default 'all'
                               check (diet in ('all', 'carnivore', 'low_carb', 'fasting', 'custom')),
    -- Biomarker names (name_no) the user hand-picked for the 'custom' view.
    -- Stored by name (not id) so selections survive re-imports and new panels.
    custom_markers text[]      not null default '{}',
    updated_at     timestamptz not null default now()
);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.user_settings enable row level security;

create policy "users_own_settings" on public.user_settings
    for all using (auth.uid() = user_id);
