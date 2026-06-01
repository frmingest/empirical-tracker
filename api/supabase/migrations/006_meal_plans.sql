-- Sprint 5: meal plans and calendar
-- The food diary (Sprint 4) records what you *did* eat. This sprint adds the
-- forward-looking half: planning what you *intend* to eat, laid out on a
-- calendar so you can prep a carnivore/low-carb week ahead of time.
--
-- Two tables:
--
--   meal_plans      A named, reusable plan ("Carnivore week", "Low-carb reset").
--                   Acts as a label/grouping for planned meals.
--
--   planned_meals   A single meal scheduled on a given date + slot. It mirrors
--                   the food_entries nutrient shape (per-100g × grams / 100,
--                   sourced from Open Food Facts) so a planned meal can be
--                   "logged to the diary" as-is once eaten. `done` records that
--                   it was cooked/eaten; plan_id optionally ties it to a plan.
--
-- Deleting a plan keeps its scheduled meals on the calendar (ON DELETE SET NULL)
-- — removing the label shouldn't wipe the week you already planned.
--
-- RLS keeps every row strictly self-scoped, like the rest of the schema.

-- ── Named plans ─────────────────────────────────────────────────────────────────
create table public.meal_plans (
    id           uuid        primary key default uuid_generate_v4(),
    user_id      uuid        not null references auth.users(id) on delete cascade,
    name         text        not null,
    description  text,
    created_at   timestamptz not null default now()
);

create index on public.meal_plans (user_id);

-- ── Scheduled meals (the calendar) ──────────────────────────────────────────────
create table public.planned_meals (
    id            uuid        primary key default uuid_generate_v4(),
    user_id       uuid        not null references auth.users(id) on delete cascade,
    -- Optional grouping; cleared (not deleted) if its plan is removed.
    plan_id       uuid        references public.meal_plans(id) on delete set null,
    scheduled_on  date        not null,
    meal          text        not null default 'other'
                              check (meal in ('breakfast', 'lunch', 'dinner', 'snack', 'other')),
    food_name     text        not null,
    brand         text,
    -- Open Food Facts product code, when the item was added from OFF.
    barcode       text,
    -- Planned grams; nutrient columns below are computed for this amount.
    quantity_g    numeric,
    energy_kcal   numeric,
    carbs_g       numeric,
    protein_g     numeric,
    fat_g         numeric,
    note          text,
    -- Whether this planned meal has been cooked/eaten.
    done          boolean     not null default false,
    created_at    timestamptz not null default now()
);

create index on public.planned_meals (user_id, scheduled_on);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.meal_plans enable row level security;
alter table public.planned_meals enable row level security;

create policy "users_own_meal_plans" on public.meal_plans
    for all using (auth.uid() = user_id);

create policy "users_own_planned_meals" on public.planned_meals
    for all using (auth.uid() = user_id);
