# ADR-015: Panel Expansion (high-yield markers, refeeding electrolytes) + Confounder Notes

**Status:** Accepted  
**Date:** 2026-06-01  
**Author:** Faiz (solo developer)  
**Sprint:** 8 (high-priority slice)

---

## Context

The clinical review (see "Clinical-feedback roadmap" in `docs/SOLUTION.md`) found
that, for the carnivore / low-carb / fasting users the app targets, several of the
*most* informative markers are simply absent, two diet profiles describe markers
they don't actually carry, and a handful of markers we already track are
confounded by the diet itself yet presented without that caveat.

Sprint 8 is large, so it is split. **This slice ships the "High"-severity items;**
the "Medium" items — further markers (fasting insulin / C-peptide, fasting
glucose, hs-CRP, AST/ASAT) and the **derived ratios** (TG/HDL, AST:ALT) — are
deferred to a follow-up PR, where the derived ratios will get a dedicated
"Derived" section that marks them as *calculated, not measured*.

---

## Decision

### 1. New markers ride the existing data-driven catalog — no schema change

The app has **no seeded biomarker catalog**: a marker exists only when it appears
in an imported XLSX (or in the demo's mock data). So "adding a marker" is purely a
matter of teaching the **client** to recognise and place it. For each new marker
we extend, in lock-step:

- **`web/src/lib/biomarkerCategories.ts`** — keyword → category, so it lands in the
  right dashboard group.
- **`web/src/lib/dietProfiles.ts`** — a new `MarkerKey`, a `markerKey()` keyword
  rule (the canonical id reused by diet focus *and* clinical targets), and
  membership in the relevant diet-focus lists.
- **`web/src/lib/mockData.ts`** — a representative entry so the signed-out demo
  shows it.

Markers added this slice:

| Marker | Category | Diet focus | Why (High severity) |
|--------|----------|-----------|---------------------|
| **Triglycerides** | Lipids | all lipid views | The signature low-carb lipid response; the Lipids tooltip already promised it. Also seeded a **clinical target** (≤ 1.7 mmol/L). |
| **ApoB** | Lipids | all lipid views | Gold-standard atherogenic-particle count — the marker for the lean-mass hyper-responder pattern. |
| **Lp(a)** | Lipids | all lipid views | Genetic atherogenic risk modifier; one-off but high-impact. |
| **Uric acid** | Metabolic | carnivore, fasting | Raised by high-purine meat intake and by fasting (gout / renal-load risk). |
| **Magnesium** | Electrolytes | fasting | Refeeding-syndrome electrolyte. |
| **Phosphate** | Electrolytes | fasting | Refeeding-syndrome electrolyte. |

**Refeeding fix.** The Fasting profile claimed to watch "refeeding-syndrome risk"
but carried only potassium. Refeeding syndrome is defined by falling
**phosphate / magnesium / potassium**, so adding Mg + phosphate makes the stated
purpose and the markers match.

### 2. Clinical target for triglycerides reuses the Sprint 7 layer

`clinicalTargets.ts` gains a triglycerides entry (≤ 1.7 mmol/L, ESC/EAS desirable
fasting). It flows through `assessMarker()`, the amber chart line, and the badge
with **zero new code** — Sprint 7 (ADR-014) built that to extend by data alone.
We deliberately did **not** seed an ApoB target this slice: the documented Sprint 7
target set is lipids-by-cholesterol + HbA1c + triglycerides, and a defensible ApoB
target is risk-stratified — adding it is a later, deliberate call, not a freebie.

### 3. Confounder notes are a new static, per-marker, bilingual map

Three markers are routinely *misread* on these diets: **eGFR** (creatinine-based,
depressed by meat/muscle), **HbA1c** (paradoxically high from longer red-cell
lifespan on keto), **ferritin** (an acute-phase reactant, not only an iron store).

These are **universal, marker-level facts, not per-user data**, so — exactly like
diet focus and clinical targets — they live as a static map keyed by `markerKey()`
in **`web/src/lib/markerNotes.ts`** (EN/NO), with **no DB table and no migration**.
A small **`MarkerNote`** component renders the note for the active language on the
biomarker detail page, under the same "decision-support, not medical advice"
framing as `MarkerSignals`. Markers without a note render nothing.

### 4. Tooltip honesty pass

`CATEGORY_DESCRIPTIONS` (EN + NO) is corrected so the app never describes a marker
it can't show:

- **Metabolic** — dropped the promise of *glucose* (a deferred Medium marker); now
  describes HbA1c + uric acid.
- **Electrolytes** — dropped *calcium* (not in panel); now lists sodium, potassium,
  magnesium, phosphate and the refeeding angle.
- **Liver** — dropped *ASAT* (deferred Medium marker); now ALAT + GGT only.
- **Lipids** — *triglycerides* is now fulfilled; added ApoB / Lp(a) particle markers.

Diet-focus descriptions (`dietProfiles.ts` + the `i18n.ts` mirror) are updated to
match the new lists.

---

## Rationale

- **No backend, no migration, no new dependency.** Every change is client-side
  static data plus one small presentational component, consistent with ADR-008
  (diet focus) and ADR-014 (clinical targets). Markers are universal reference
  facts; health-data tables stay strictly per-user.
- **Single source of truth.** `markerKey()` already underpins category-independent
  marker identity for diet focus and targets; reusing it for confounder notes and
  the new markers avoids a parallel naming scheme.
- **Honesty first.** Tooltips now match the panel exactly; confounder notes are
  framed as context, not diagnosis; the deferred items are named so the roadmap
  stays truthful about what shipped.

---

## Consequences

- **Good:** The signature low-carb marker (triglycerides, with its target line),
  the atherogenic-particle markers (ApoB/Lp(a)), the gout/renal-load marker (uric
  acid), and the refeeding electrolytes (Mg/phosphate) are now first-class.
- **Good:** eGFR / HbA1c / ferritin can no longer be silently misread on these
  diets.
- **Trade-off / follow-up:** Medium-tier markers and the TG/HDL & AST:ALT derived
  ratios are **not** in this slice. The derived ratios need a small compute layer
  (matching the two source series by date) and a dedicated "Derived — calculated,
  not measured" UI section; that is the next PR.
- **Maintenance contract (carried from ADR-013):** the new markers are *measured*
  values that flow through the existing `results` table, so `USER_TABLES` /
  `DELETE_ORDER` in `api/app/account/repository.py` need **no** change. That
  contract still bites in **Sprint 9** (new nutrient *columns*) and **Sprint 10**
  (`body_metrics` table).

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| A seeded `biomarkers` catalog / reference table for the new markers | The app is data-driven — markers appear from imports; a catalog would duplicate that and add a migration for no per-user value |
| Putting confounder notes in `i18n.ts` category tooltips | They are *per marker*, not per category, and only apply to three of many markers in their groups |
| Seeding an ApoB clinical target now | A defensible ApoB target is risk-stratified; out of the documented Sprint 7 target set — a deliberate later decision |
| Shipping derived ratios in this PR | They are Medium severity and need their own compute + "calculated, not measured" UI; bundling would bloat an already-large slice |
| Filing uric acid under Renal | It's a metabolite, not a kidney-function test; Metabolic (purine/protein metabolism) is the honest grouping, and the tooltip now says so |
