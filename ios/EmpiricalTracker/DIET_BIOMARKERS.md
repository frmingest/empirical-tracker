# Diet-specific biomarker focus lists

> Clinical reference for the **Diet focus** toggle on the dashboard. For each
> supported eating pattern, this document lists which of the panel's biomarkers
> are worth following and *why*. The dashboard uses these lists to hide markers
> that aren't clinically informative for the chosen diet, so the user sees a
> focused view instead of all 34 markers at once.
>
> **This is decision-support, not medical advice.** It encodes "which numbers
> tend to move on this diet, and which ones flag a known risk of it" — it does
> not tell anyone what their results mean. Always read it alongside a clinician.

The canonical machine-readable version lives in
`Packages/Biomarkers/Sources/Biomarkers/DietProfiles.swift` (`markerRules` /
`dietKeyMap`, consumed by `DashboardViewModel` via `filterByDiet`). Keep the two
in sync.

---

## A note on "in range" vs. clinical targets

The colour on each marker is **not** a verdict of "healthy." The lab's
**reference range** is just the band where most of a reference population falls —
it says nothing about whether a value is *good for you*. For a few markers a
guideline-recommended **target** is tighter than the lab's range, so a value can
sit inside the lab range yet still be higher than you'd ideally want.

Since Sprint 7 the app makes that distinction visible (see
`docs/adr/014-clinical-targets-trend-signals.md`):

- **LDL, non-HDL, total cholesterol, triglycerides, and HbA1c** carry a guideline
  **clinical target** — drawn as a separate amber line on the chart. If your
  latest value is at or above it, the marker shows an amber **"Watch"** instead of
  green, even while it's inside the lab range. These are *general* guideline
  numbers, not personalised to your individual risk.
- The app also flags **big moves that stay in range** — for example a liver
  enzyme (ALT) doubling from 25 to 55 while still under the lab limit of 70. The
  old green flag used to hide exactly that.

This is still **decision-support, not medical advice**: it points at numbers
worth a second look and a conversation with your clinician — it does not diagnose
anything or claim your diet caused the change.

## A note on diet confounders

A few markers are routinely *misread* on these diets because the diet itself
moves the number for a reason unrelated to what the marker usually means. Since
Sprint 8, those markers carry a per-marker **interpretation note** on their
detail page (see `confounderText` in
`EmpiricalTracker/Features/BiomarkerDetail/BiomarkerDetailView.swift`):

- **eGFR** — creatinine-based eGFR is depressed by a high meat intake and more
  muscle mass, so it can look low without any real loss of kidney function;
  cystatin-C–based eGFR is the cleaner check.
- **HbA1c** — can read paradoxically high on keto/carnivore because longer-lived
  red cells accumulate more glucose over their lifespan.
- **Ferritin** — an acute-phase reactant that rises with inflammation, not only
  with iron stores; a high value on a high-heme-iron diet needs transferrin
  saturation and an inflammation marker to interpret.

---

## Carnivore (all-meat, near-zero carbohydrate)

An all-animal-foods elimination diet. It is high in saturated fat and heme
iron, very high in protein, and contains no plant foods — so it stresses the
lipid, iron, renal, hepatic and methylation systems, and removes the dietary
sources of folate and vitamin C.

| System | Markers | Why it matters on carnivore |
|--------|---------|------------------------------|
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL, Triglycerides, ApoB, Lp(a) | High saturated-fat intake can drive large LDL/non-HDL/ApoB shifts (incl. the "lean-mass hyper-responder" pattern); ApoB is the gold-standard atherogenic-particle count and Lp(a) the genetic risk modifier. Triglycerides typically fall on near-zero-carb eating. The single most important panel to watch. |
| **Metabolic** | HbA1c, Uric acid | HbA1c confirms the near-zero-carb glycemic effect over time; uric acid rises with the high purine load of an all-meat diet (gout / renal-load risk). |
| **Liver** | ALT, GGT | Fat-adapted metabolism; track resolution (or strain) of fatty-liver markers. |
| **Renal** | Creatinine, eGFR | Very high protein load increases filtration demand; creatinine also rises with high meat intake and muscle mass. |
| **Iron studies** | Ferritin, Iron, Transferrin | Heme iron from red meat is highly absorbed → watch for iron *overload*, not just deficiency. |
| **Methylation / B-vitamins** | Vitamin B12, Active B12, MMA, Homocysteine, Folate | Meat is B12-rich (B12/Active B12/MMA usually reassuring) but **folate** has no animal source — homocysteine + folate flag the main deficiency risk. |
| **Vitamin D** | Vitamin D (25-OH) | Limited dietary source; worth tracking. |
| **Electrolytes** | Sodium, Potassium | Shift during keto-adaptation ("carnivore flu"); sodium needs often rise. |
| **CBC (subset)** | Hemoglobin, Hematocrit | Track alongside iron status and for hemoconcentration. |

*Deliberately hidden:* RBC, WBC, MCH, MCHC, MCV (red-cell indices and white
count are general-wellness markers, not carnivore-specific) and the thyroid
panel (add via Custom if monitoring long-term low-carb thyroid effects).

---

## Low carb (reduced carbohydrate, not strictly all-meat)

Carbohydrate restriction without full elimination. The headline effects are on
glycemic control, the lipid panel, fatty-liver enzymes, and renal sodium
handling (lower insulin → natriuresis).

| System | Markers | Why it matters on low carb |
|--------|---------|-----------------------------|
| **Metabolic** | HbA1c | The primary endpoint — does carb restriction improve glycemic control? |
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL, Triglycerides, ApoB | HDL typically rises and triglycerides usually fall (the signature low-carb lipid response); LDL/non-HDL/ApoB responses vary and should be tracked. |
| **Liver** | ALT, GGT | Often improve as fatty-liver burden falls. |
| **Electrolytes** | Sodium, Potassium | Insulin drop causes sodium (and water) loss — a common cause of early fatigue. |
| **Iron** | Ferritin | Modest relevance as red-meat intake often rises. |

*Deliberately hidden:* the full CBC, thyroid, renal and most micronutrient
markers — informative on a stricter carnivore protocol, but noise for general
low-carb tracking. Add any of them via Custom.

---

## Fasting (intermittent / prolonged fasting)

Time-restricted or extended fasting. The dominant clinical concern is
**electrolyte and fluid balance** (depletion during the fast, refeeding risk
after), alongside glucose control, fat-fuel/liver markers, and
hydration-sensitive blood counts.

| System | Markers | Why it matters when fasting |
|--------|---------|------------------------------|
| **Electrolytes** | Sodium, Potassium, Magnesium, Phosphate | The top priority. Refeeding syndrome is defined by falling **phosphate, magnesium and potassium** when a fast is broken, so all three (plus sodium) belong here — not potassium alone. |
| **Metabolic** | HbA1c, Uric acid | HbA1c tracks the glycemic benefit; uric acid rises during a fast (ketone–urate competition for renal excretion) and can precipitate gout. |
| **Liver** | ALT, GGT | Reflect the shift to fat metabolism / autophagy. |
| **Renal** | Creatinine, eGFR | Sensitive to hydration status and fasting-related changes. |
| **CBC (subset)** | Hemoglobin, Hematocrit | Hemoconcentration is an early sign of dehydration during a fast. |
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL, Triglycerides, ApoB, Lp(a) | Free fatty-acid mobilisation shifts the lipid panel. |

*Deliberately hidden:* red-cell indices, white count, thyroid, and the
micronutrient panel — relevant for diet *composition*, less so for the *timing*
of fasting. Add via Custom.

---

## Custom

Any marker, hand-picked. Selecting **Custom** (or **Customize** on a preset)
opens a picker seeded from the current view, so a user can start from the
clinical list above and add or remove individual markers. Custom selections are
stored per-user by biomarker name, so they survive re-imports and new panels.
