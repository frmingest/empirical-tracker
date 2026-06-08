-- Carry the product's ingredients list onto the logged diary entry.
-- custom_foods already stores `ingredients` (from the OCR label scan), but a
-- food_entries row is a denormalised snapshot of what was consumed and never
-- captured it — so the Edit Entry screen had nothing to show. Store it here so
-- the ingredients survive on the entry independently of the source food.

ALTER TABLE food_entries ADD COLUMN IF NOT EXISTS ingredients text;
