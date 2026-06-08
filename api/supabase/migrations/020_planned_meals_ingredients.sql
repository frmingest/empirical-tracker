-- Carry the product's ingredients onto a scheduled (planned) meal too, mirroring
-- migration 019 for food_entries. A planned meal is a denormalised snapshot of
-- what will be eaten; storing ingredients lets the schedule sheet keep them and
-- the "Log to diary" promotion forward them onto the resulting diary entry.

ALTER TABLE planned_meals ADD COLUMN IF NOT EXISTS ingredients text;
