-- Clarify custom_foods nutrient semantics: values are PER 100 g, not per
-- serving. The iOS entry form labels the section "Nutrition per 100 g"
-- (food.custom.nutrients.footer), and app/food_sources/custom.py maps the
-- columns 1:1 onto the per-100g FoodItem shape. serving_g is only a display
-- hint ("1 serving = N g"); it is NOT a divisor for the nutrient columns.
-- The bare column names (energy_kcal next to serving_g) have already misled
-- one code review into reporting a normalisation bug — make the contract
-- explicit in the schema.

COMMENT ON COLUMN custom_foods.energy_kcal     IS 'kcal per 100 g (not per serving)';
COMMENT ON COLUMN custom_foods.carbs_g         IS 'g per 100 g';
COMMENT ON COLUMN custom_foods.protein_g       IS 'g per 100 g';
COMMENT ON COLUMN custom_foods.fat_g           IS 'g per 100 g';
COMMENT ON COLUMN custom_foods.saturated_fat_g IS 'g per 100 g';
COMMENT ON COLUMN custom_foods.sodium_mg       IS 'mg per 100 g';
COMMENT ON COLUMN custom_foods.serving_g       IS 'Typical serving size in g — display hint only; nutrient columns stay per-100g';

-- The donated twin catalogue (ADR-027) copies these fields verbatim, so the
-- same contract applies there.
COMMENT ON COLUMN food_catalogue.energy_kcal     IS 'kcal per 100 g (not per serving)';
COMMENT ON COLUMN food_catalogue.carbs_g         IS 'g per 100 g';
COMMENT ON COLUMN food_catalogue.protein_g       IS 'g per 100 g';
COMMENT ON COLUMN food_catalogue.fat_g           IS 'g per 100 g';
COMMENT ON COLUMN food_catalogue.saturated_fat_g IS 'g per 100 g';
COMMENT ON COLUMN food_catalogue.sodium_mg       IS 'mg per 100 g';
COMMENT ON COLUMN food_catalogue.serving_g       IS 'Typical serving size in g — display hint only; nutrient columns stay per-100g';
