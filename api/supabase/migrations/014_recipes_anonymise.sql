-- Recipe catalogue: donated, de-identified recipes (ADR-028).
--
-- When a user deletes a *public* recipe (or their account), its factual fields
-- are copied here and the user-owned `recipes` row is hard-deleted. This table
-- keeps the curated catalogue value while honouring the right to erasure: it
-- carries NO user_id, no created_at (only a coarse donated_at date with no tie
-- to the user's activity), and never the hero image_url — a user-supplied photo
-- can't be guaranteed non-identifying (EXIF / faces) and its URL may embed a
-- user-scoped storage path, so, like custom_foods.ocr_raw, it is never donated.
--
-- Mirrors the read-only external food sources: writable only by the service
-- role (the donation path), readable by any authenticated user.

create table public.recipe_catalogue (
    id            uuid        primary key default uuid_generate_v4(),
    title         text        not null,
    category      text        not null,
    serving_size  text,
    -- Author-estimated per-serving macros (the "Estimated nutrition" card).
    calories_kcal numeric,
    protein_g     numeric,
    fat_g         numeric,
    carbs_g       numeric,
    -- Ordered lists of free text, presented as-is (checklist / numbered steps).
    ingredients   jsonb       not null default '[]'::jsonb,
    instructions  jsonb       not null default '[]'::jsonb,
    -- The orange "Recipe Fact" blurb shown above the instructions. Optional.
    fact          text,
    -- Premium-only recipe; the "Only free recipes" filter hides these.
    is_premium    boolean     not null default false,
    -- Coarse donation date (no time-of-day) — deliberately not created_at, so
    -- the row carries no signal tying it back to the contributor's activity.
    donated_at    date        not null default current_date
);

-- Catalogue is browsed by category and recency.
create index on public.recipe_catalogue (category);
create index on public.recipe_catalogue (donated_at desc);

alter table public.recipe_catalogue enable row level security;

-- Any authenticated user may read the donated catalogue; nobody may write it
-- through the anon/JWT path. Donation runs on the service role, which bypasses
-- RLS (ADR-026 / ADR-028) — so there is intentionally no INSERT/UPDATE/DELETE
-- policy for ordinary users.
create policy "recipe_catalogue_select" on public.recipe_catalogue
    for select using (auth.role() = 'authenticated');
