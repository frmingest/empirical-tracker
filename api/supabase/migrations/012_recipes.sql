-- Recipes: a browsable catalogue of carnivore / low-carb recipes plus a
-- user-facing authoring module ("create a new recipe and add it to the
-- database"). Two tables:
--
--   recipes            A single recipe: title, category, hero image, estimated
--                      per-serving macros, an ordered ingredient list, ordered
--                      instruction steps, and an optional "Recipe Fact" blurb.
--                      Owned by the user who authored it. `is_public` lets a
--                      recipe be shared into everyone's catalogue (mirrors the
--                      custom_foods sharing model from 011).
--
--   recipe_favorites   The per-user star. A recipe can be favourited by many
--                      users; a user favourites a recipe at most once.
--
-- Ingredients and instructions are stored as JSON arrays of free text — they are
-- presented as-is (checklist rows / numbered steps), never parsed for nutrients,
-- so a structured per-ingredient schema would add cost without value here. The
-- per-serving macros the cards show are author-estimated totals.
--
-- "New!" is derived (created within the last 14 days), not stored, so a recipe
-- ages out on its own with no background job.
--
-- RLS keeps authoring strictly self-scoped while still letting the catalogue be
-- shared, exactly like the rest of the schema.

-- ── Recipes ──────────────────────────────────────────────────────────────────────
create table public.recipes (
    id            uuid        primary key default uuid_generate_v4(),
    user_id       uuid        not null references auth.users(id) on delete cascade,
    title         text        not null,
    category      text        not null,
    image_url     text,
    serving_size  text,
    -- Author-estimated per-serving macros (the "Estimated nutrition" card).
    calories_kcal numeric,
    protein_g     numeric,
    fat_g         numeric,
    carbs_g       numeric,
    -- Ordered lists of free text. e.g. ["8 oz pork belly, cut into cubes", …].
    ingredients   jsonb       not null default '[]'::jsonb,
    instructions  jsonb       not null default '[]'::jsonb,
    -- The orange "Recipe Fact" blurb shown above the instructions. Optional.
    fact          text,
    -- Shared into the public catalogue (visible to all users) when true.
    is_public     boolean     not null default false,
    -- Premium-only recipe; the "Only free recipes" filter hides these.
    is_premium    boolean     not null default false,
    created_at    timestamptz not null default now()
);

-- Catalogue is browsed by category and recency.
create index on public.recipes (user_id);
create index on public.recipes (category);
create index on public.recipes (created_at desc);

-- ── Favourites (the star) ────────────────────────────────────────────────────────
create table public.recipe_favorites (
    user_id     uuid        not null references auth.users(id) on delete cascade,
    recipe_id   uuid        not null references public.recipes(id) on delete cascade,
    created_at  timestamptz not null default now(),
    primary key (user_id, recipe_id)
);

create index on public.recipe_favorites (user_id);

-- ── Row-Level Security ────────────────────────────────────────────────────────────
alter table public.recipes enable row level security;
alter table public.recipe_favorites enable row level security;

-- Users see their own recipes plus any recipe shared into the public catalogue.
create policy "recipes_select" on public.recipes
    for select using (user_id = auth.uid() or is_public = true);

create policy "recipes_insert" on public.recipes
    for insert with check (user_id = auth.uid());

create policy "recipes_update" on public.recipes
    for update using (user_id = auth.uid());

create policy "recipes_delete" on public.recipes
    for delete using (user_id = auth.uid());

-- A user fully owns their own favourites.
create policy "recipe_favorites_all" on public.recipe_favorites
    for all using (user_id = auth.uid());
