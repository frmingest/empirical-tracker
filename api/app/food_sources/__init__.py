"""Multi-source food nutrition providers.

The app reads food nutrition from several databases, each strong at a different
thing:

  * **Open Food Facts** (``off``) — branded, packaged products and barcodes.
  * **Matvaretabellen** (``mvt``) — the Norwegian Food Composition Table:
    lab-analysed whole foods, vendored as an in-process dataset.
  * **USDA FoodData Central** (``usda``) — the American equivalent: lab-analysed
    whole foods, reached through a keyed, cached proxy.

Every source normalises to one stable :data:`~app.food_sources.base.FoodItem`
shape so the diary, the meal-plan calendar, and the frontend stay
source-agnostic apart from a small ``source`` tag. See ADR-018.
"""
