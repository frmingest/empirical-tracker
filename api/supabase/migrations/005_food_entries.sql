-- Sprint 4: food diary
-- One row per food logged on a given day. Nutrient values are the amounts the
-- user actually consumed (per-100g values from the source × quantity / 100),
-- computed when the entry is created. Branded/barcode items are sourced from
-- Open Food Facts (ODbL, https://world.openfoodfacts.org); `barcode` holds the
-- Open Food Facts product code so an entry can be traced back to its source.
--
-- We store the consumed amounts (not just a reference to the product) so the
-- diary stays correct even if the upstream product data changes or disappears.
--
-- RLS keeps every row strictly self-scoped, like the rest of the schema.

create table public.food_entries (
    id           uuid        primary key default uuid_generate_v4(),
    user_id      uuid        not null references auth.users(id) on delete cascade,
    logged_on    date        not null,
    meal         text        not null default 'other'
                             check (meal in ('breakfast', 'lunch', 'dinner', 'snack', 'other')),
    food_name    text        not null,
    brand        text,
    -- Open Food Facts product code, when the item was added from OFF.
    barcode      text,
    -- Grams consumed; nutrient columns below are computed for this amount.
    quantity_g   numeric,
    energy_kcal  numeric,
    carbs_g      numeric,
    protein_g    numeric,
    fat_g        numeric,
    note         text,
    created_at   timestamptz not null default now()
);

create index on public.food_entries (user_id, logged_on);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.food_entries enable row level security;

create policy "users_own_food_entries" on public.food_entries
    for all using (auth.uid() = user_id);
