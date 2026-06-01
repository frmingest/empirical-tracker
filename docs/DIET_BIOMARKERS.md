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
`web/src/lib/dietProfiles.ts` (`DIET_MARKERS`). Keep the two in sync.

---

## A note on "in range" vs. clinical targets

The colour on each marker is **not** a verdict of "healthy." The lab's
**reference range** is just the band where most of a reference population falls —
it says nothing about whether a value is *good for you*. For a few markers a
guideline-recommended **target** is tighter than the lab's range, so a value can
sit inside the lab range yet still be higher than you'd ideally want.

Since Sprint 7 the app makes that distinction visible (see
`docs/adr/014-clinical-targets-trend-signals.md`):

- **LDL, non-HDL, total cholesterol, and HbA1c** carry a guideline **clinical
  target** — drawn as a separate amber line on the chart. If your latest value is
  at or above it, the marker shows an amber **"Watch"** instead of green, even
  while it's inside the lab range. These are *general* guideline numbers, not
  personalised to your individual risk.
- The app also flags **big moves that stay in range** — for example a liver
  enzyme (ALT) doubling from 25 to 55 while still under the lab limit of 70. The
  old green flag used to hide exactly that.

This is still **decision-support, not medical advice**: it points at numbers
worth a second look and a conversation with your clinician — it does not diagnose
anything or claim your diet caused the change.

---

## Carnivore (all-meat, near-zero carbohydrate)

An all-animal-foods elimination diet. It is high in saturated fat and heme
iron, very high in protein, and contains no plant foods — so it stresses the
lipid, iron, renal, hepatic and methylation systems, and removes the dietary
sources of folate and vitamin C.

| System | Markers | Why it matters on carnivore |
|--------|---------|------------------------------|
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL | High saturated-fat intake can drive large LDL/non-HDL shifts (incl. the "lean-mass hyper-responder" pattern). The single most important panel to watch. |
| **Metabolic** | HbA1c | Confirms the near-zero-carb glycemic effect over time. |
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
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL | HDL typically rises; LDL/non-HDL responses vary and should be tracked. |
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
| **Electrolytes** | Sodium, Potassium | The top priority — depletion during prolonged fasts and refeeding-syndrome risk on breaking them. |
| **Metabolic** | HbA1c | Tracks the glycemic benefit of the fasting pattern. |
| **Liver** | ALT, GGT | Reflect the shift to fat metabolism / autophagy. |
| **Renal** | Creatinine, eGFR | Sensitive to hydration status and fasting-related changes. |
| **CBC (subset)** | Hemoglobin, Hematocrit | Hemoconcentration is an early sign of dehydration during a fast. |
| **Lipids** | HDL, LDL, Total cholesterol, non-HDL | Free fatty-acid mobilisation shifts the lipid panel. |

*Deliberately hidden:* red-cell indices, white count, thyroid, and the
micronutrient panel — relevant for diet *composition*, less so for the *timing*
of fasting. Add via Custom.

---

## Custom

Any marker, hand-picked. Selecting **Custom** (or **Customize** on a preset)
opens a picker seeded from the current view, so a user can start from the
clinical list above and add or remove individual markers. Custom selections are
stored per-user by biomarker name, so they survive re-imports and new panels.
