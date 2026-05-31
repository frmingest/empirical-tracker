# Nutrition Data — Sources, Accuracy & Caveats

> How the food diary gets its numbers, and the limits of what they mean.
> Written so a non-clinical reader can trust the app without over-trusting it.

---

## Where the numbers come from

All food nutrition in the diary comes from **[Open Food Facts](https://world.openfoodfacts.org)**
(OFF), a free, collaborative, open database of food products published under the
**Open Database License (ODbL)**. We query it for two things:

- **Search** — full-text lookup of products by name (e.g. "cheddar").
- **Barcode** — direct lookup of a single product by its barcode (EAN/UPC).

OFF requires no API key. The only requirement for read access is a descriptive
`User-Agent`, which our backend sends on every request.

---

## What we store, and how it's calculated

OFF publishes nutrient values **per 100 g** of product. When you log a food we:

1. Take the per-100 g values exactly as OFF publishes them — **we never invent,
   estimate, or "fill in" missing values.**
2. Scale them to the amount you actually ate:

   ```
   consumed = published_per_100g × grams_eaten / 100
   ```

3. Store the **consumed** amounts (energy in kcal; carbohydrate, protein, and fat
   in grams) on the diary entry.

We store the computed result — not just a link to the product — so your diary
stays accurate even if the product's data on OFF later changes or is removed.

If OFF doesn't have a value for a field, we store nothing for it and the UI shows
**"—"** rather than a guess.

---

## Accuracy caveats (please read)

- **Crowd-sourced data.** OFF is community-maintained. Coverage and quality vary:
  some products are complete and verified, others are sparse or may contain
  entry errors. Treat the numbers as a good estimate, not a lab measurement.
- **Linear scaling only.** We scale strictly by mass. We do not adjust for
  cooking losses, water uptake, or preparation — log the form you actually ate
  where possible (e.g. "cooked").
- **Four macros only.** The diary tracks energy, carbohydrate, protein, and fat.
  It does not track micronutrients, fibre, or sodium at this stage.
- **No medical advice.** The diary is a logging and context tool. It does not
  interpret your intake, set targets, or make clinical recommendations.

---

## Correlation overlay caveat

Diet annotations (Sprint 3) can be drawn on biomarker charts to mark when you
changed your regimen. These are a **visual aid only**:

- Annotations are **snapped to the nearest blood draw**, so their position is
  approximate.
- A marker moving near an annotation **does not prove cause and effect.** Many
  things change at once in real life, and a handful of blood draws can't support
  a statistical claim. Use the overlay to spot things worth discussing with a
  clinician — not as evidence on its own.

---

## Attribution

Food data © Open Food Facts contributors, licensed under the
[Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
The app credits Open Food Facts on the food-diary page.
