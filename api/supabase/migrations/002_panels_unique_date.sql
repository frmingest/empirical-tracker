-- Sprint 2: unique constraint on panels(user_id, tested_at)
-- Required for the manual-entry upsert: ON CONFLICT (user_id, tested_at).
-- The index already exists (from 001) — add the constraint on top of it.

alter table public.panels
    add constraint panels_user_date_unique unique (user_id, tested_at);
