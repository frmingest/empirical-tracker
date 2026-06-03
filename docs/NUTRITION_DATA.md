# Nutrition Data — Sources, Accuracy & Caveats

> How the food diary gets its numbers, and the limits of what they mean.
> Written so a non-clinical reader can trust the app without over-trusting it.

---

## Where the numbers come from

Food nutrition in the diary comes from **three** databases, each strong at a
different thing. You choose which to search with the **source selector**; every
result and logged entry carries a small **source badge** so you always know
where its numbers came from (ADR-018).

| Source | Badge | What it covers | Provenance | Licence |
|--------|-------|----------------|------------|---------|
| **[Matvaretabellen](https://www.matvaretabellen.no)** | `NO` | Norwegian **whole foods** (egg, ribeye, butter, salmon) | Government, lab-analysed | NLOD 2.0 / CC BY 4.0 |
| **[USDA FoodData Central](https://fdc.nal.usda.gov)** | `US` | American **whole foods** + **branded** packs | Government (whole foods) / manufacturer (branded) | Public domain (CC0) |
| **[Open Food Facts](https://world.openfoodfacts.org)** | `OFF` | **Branded / packaged** products & barcodes | Crowd-sourced | ODbL |

By default the app searches **all sources at once** and merges the results,
whole-food tables first. That way a "ribeye" or "egg" comes from a curated,
lab-analysed entry, while branded packs still appear — and a search is never
blank. You can narrow to a single source with the filter chip.

Open Food Facts is crowd-sourced, so a large share of its entries carry a name
but **no nutrition numbers at all**. Those would show as an all-"—" row you can't
actually log, so the app **hides Open Food Facts results that have no energy
value** from search (a barcode you deliberately scan is still shown as-is). USDA
now also includes its **manufacturer-declared Branded** dataset, which is
near-complete and public-domain — a more reliable source for the packaged
products where Open Food Facts is often empty. Open Food Facts remains the
**only** source with barcodes.

We query these for:

- **Search** — full-text lookup by name (e.g. "ribeye", "egg"), against the
  selected source or *all* sources merged.
- **Barcode** — direct lookup of a single product by its barcode (EAN/UPC).
  **Open Food Facts only** — the whole-food composition tables have no barcodes.

Neither Open Food Facts nor Matvaretabellen needs an API key. **Matvaretabellen**
is shipped *inside the app* as a vendored, versioned dataset (regenerated from
the upstream open data by `api/scripts/ingest_matvaretabellen.py`), so its search
is instant and works offline. **USDA** is reached through our backend proxy with
a free, server-only `api.data.gov` key; if that key is absent or USDA is
unreachable, the USDA source simply returns no results — it never blocks the
others. Open Food Facts requires only a descriptive `User-Agent`, which our
backend sends on every request.

---

## What we store, and how it's calculated

All three sources publish nutrient values **per 100 g** of food. When you log a
food we:

1. Take the per-100 g values exactly as the source publishes them — **we never
   invent, estimate, or "fill in" missing values.**
2. Scale them to the amount you actually ate:

   ```
   consumed = published_per_100g × grams_eaten / 100
   ```

3. Store the **consumed** amounts (energy in kcal; carbohydrate, protein, fat,
   and saturated fat in grams; sodium in milligrams) on the diary entry.

We store the computed result — and the **source** it came from — not just a link
to the product, so your diary stays accurate even if the source's data later
changes or is removed.

If a source doesn't have a value for a field, we store nothing for it and the UI
shows **"—"** rather than a guess.

**Two derivations (Sprint 9), only when the direct field is missing (Open Food
Facts):**

- **Sodium.** We prefer OFF's measured sodium. When OFF publishes only **salt**,
  we derive sodium from it using the standard conversion `salt = sodium × 2.5`.
  Sodium is stored and shown in **milligrams**. (Matvaretabellen and USDA report
  sodium directly in mg.)
- **Energy.** When OFF has no kcal value but does have **kilojoules**, we convert
  at `1 kcal = 4.184 kJ` instead of storing nothing.

These are fixed unit conversions — not estimates of missing data.

---

## Accuracy caveats (please read)

- **Source quality varies.** Open Food Facts is community-maintained: coverage
  and quality vary, and some branded entries are sparse or may contain entry
  errors — treat them as a good estimate, not a lab measurement. Matvaretabellen
  and USDA are government, lab-analysed composition tables and are more reliable
  for whole foods, but are still reference values for a *typical* food, not the
  exact item on your plate. The source badge tells you which kind each entry is.
- **Linear scaling only.** We scale strictly by mass. We do not adjust for
  cooking losses, water uptake, or preparation — log the form you actually ate
  where possible (e.g. "cooked").
- **Macros plus sodium & saturated fat.** The diary tracks energy, carbohydrate,
  protein, fat, **saturated fat, and sodium** (Sprint 9). It does not track other
  micronutrients or fibre at this stage.
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

The app credits all three sources on the food-diary page:

- **Matvaretabellen** — © Matvaretabellen (Mattilsynet / Helsedirektoratet /
  Universitetet i Oslo), published under
  [NLOD 2.0](https://data.norge.no/nlod/en/2.0) / CC BY 4.0.
- **USDA FoodData Central** — produced by the USDA Agricultural Research Service;
  USDA-authored data is in the **public domain** (CC0).
- **Open Food Facts** — © Open Food Facts contributors, licensed under the
  [Open Database License (ODbL)](https://opendatacommons.org/licenses/odbl/1-0/).
