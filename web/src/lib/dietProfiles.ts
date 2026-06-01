import type { BiomarkerWithSeries } from "./api";

/**
 * Diet-aware biomarker filtering.
 *
 * Each supported diet maps to the set of biomarkers worth following on it (see
 * docs/DIET_BIOMARKERS.md for the clinical rationale). The dashboard uses this
 * to hide markers that aren't informative for the chosen diet.
 *
 * Matching is done against `name_no` (the only field present on both mock and
 * imported data — imported biomarkers have `name_en === null`). `markerKey()`
 * resolves the messy lab names to a stable canonical key, mirroring the
 * keyword approach in `biomarkerCategories.ts`.
 */

export type DietKey = "all" | "carnivore" | "low_carb" | "fasting" | "custom";

/** Canonical, stable identifier for each biomarker in the panel. */
export type MarkerKey =
  | "hdl" | "ldl" | "total_chol" | "nonhdl" | "triglycerides" | "apob" | "lpa"
  | "hemoglobin" | "rbc" | "wbc" | "hematocrit" | "mch" | "mchc" | "mcv"
  | "hba1c" | "uric_acid" | "tsh" | "free_t4" | "creatinine" | "egfr" | "alt" | "ggt"
  | "ferritin" | "folate" | "b12" | "active_b12" | "vitamin_d" | "transferrin"
  | "iron" | "homocysteine" | "mma" | "sodium" | "potassium" | "magnesium" | "phosphate";

/**
 * Ordered keyword rules — first match wins. Order resolves ambiguity:
 *  - "hba1c" before "hemoglobin" (its name contains "Glycated Hemoglobin")
 *  - "non-hdl" before "hdl"; "mchc" before "mch"
 *  - the red-cell indices (mch/mchc/mcv) before "hemoglobin" (their names
 *    contain "… Hemoglobin …")
 *  - "gfr" before "kreatinin" so eGFR doesn't fall through to anything else
 *  - the particle markers (apob/lp(a)/triglycerides) carry their own distinct
 *    keywords, so order among the lipids is not load-bearing for them
 */
const MARKER_RULES: [MarkerKey, string[]][] = [
  ["hba1c", ["hba1c"]],
  ["nonhdl", ["non-hdl"]],
  ["hdl", ["hdl"]],
  ["ldl", ["ldl"]],
  ["triglycerides", ["triglyserid", "triglycerid"]],
  ["apob", ["apolipoprotein b", "apolipoprotein", "apob"]],
  ["lpa", ["lp(a)", "lipoprotein (a)", "lipoprotein a"]],
  ["total_chol", ["kolesterol", "cholesterol"]],
  ["uric_acid", ["urinsyre", "uric acid", "urat"]],
  ["mchc", ["mchc"]],
  ["mch", ["mch"]],
  ["mcv", ["mcv"]],
  ["hemoglobin", ["hemoglobin"]],
  ["rbc", ["erytrocytter"]],
  ["wbc", ["leukocytter"]],
  ["hematocrit", ["hematokritt"]],
  ["tsh", ["tsh"]],
  ["free_t4", ["t4"]],
  ["egfr", ["gfr"]],
  ["creatinine", ["kreatinin"]],
  ["alt", ["alat"]],
  ["ggt", ["p-gt", "ggt"]],
  ["ferritin", ["ferritin"]],
  ["folate", ["folat"]],
  ["active_b12", ["aktivt"]],
  ["b12", ["b12"]],
  ["vitamin_d", ["vitamin d", "25-oh"]],
  ["transferrin", ["transferrin"]],
  ["iron", ["jern"]],
  ["homocysteine", ["homocystein"]],
  ["mma", ["mma", "metylmalon"]],
  ["sodium", ["natrium"]],
  ["potassium", ["kalium"]],
  ["magnesium", ["magnesium"]],
  ["phosphate", ["fosfat", "phosphate"]],
];

/** Resolve a Norwegian biomarker name to its canonical key, or null if unknown. */
export function markerKey(nameNo: string): MarkerKey | null {
  const lower = nameNo.toLowerCase();
  for (const [key, keywords] of MARKER_RULES) {
    if (keywords.some((kw) => lower.includes(kw))) return key;
  }
  return null;
}

// ── Clinical focus lists (keep in sync with docs/DIET_BIOMARKERS.md) ──────────

const CARNIVORE: MarkerKey[] = [
  "hdl", "ldl", "total_chol", "nonhdl", "triglycerides", "apob", "lpa",
  "hba1c",
  "uric_acid",
  "alt", "ggt",
  "creatinine", "egfr",
  "ferritin", "iron", "transferrin",
  "b12", "active_b12", "mma", "homocysteine", "folate",
  "vitamin_d",
  "sodium", "potassium",
  "hemoglobin", "hematocrit",
];

const LOW_CARB: MarkerKey[] = [
  "hba1c",
  "hdl", "ldl", "total_chol", "nonhdl", "triglycerides", "apob", "lpa",
  "alt", "ggt",
  "sodium", "potassium",
  "ferritin",
];

const FASTING: MarkerKey[] = [
  "sodium", "potassium", "magnesium", "phosphate",
  "hba1c",
  "uric_acid",
  "alt", "ggt",
  "creatinine", "egfr",
  "hemoglobin", "hematocrit",
  "hdl", "ldl", "total_chol", "nonhdl", "triglycerides", "apob", "lpa",
];

/** Preset diets → the marker keys they reveal. */
export const DIET_MARKERS: Record<"carnivore" | "low_carb" | "fasting", Set<MarkerKey>> = {
  carnivore: new Set(CARNIVORE),
  low_carb: new Set(LOW_CARB),
  fasting: new Set(FASTING),
};

export interface DietOption {
  key: DietKey;
  label: string;
  description: string;
}

export const DIET_OPTIONS: DietOption[] = [
  {
    key: "all",
    label: "All",
    description: "Show every biomarker in your panel.",
  },
  {
    key: "carnivore",
    label: "Carnivore",
    description:
      "Lipid panel (incl. triglycerides, ApoB, Lp(a)), iron stores, kidney load, liver enzymes, uric acid, electrolytes and B-vitamin / folate status — the markers most affected by an all-meat diet.",
  },
  {
    key: "low_carb",
    label: "Low carb",
    description:
      "Glycemic control (HbA1c), the full lipid panel (incl. triglycerides and ApoB), liver enzymes and the electrolytes that shift when you cut carbs.",
  },
  {
    key: "fasting",
    label: "Fasting",
    description:
      "Refeeding-syndrome electrolytes (sodium, potassium, magnesium, phosphate), glucose control, uric acid, kidney and liver markers, plus hydration-sensitive blood counts to watch during a fast.",
  },
  {
    key: "custom",
    label: "Custom",
    description: "Hand-pick exactly which biomarkers you want to follow.",
  },
];

/** Whether a single biomarker is shown for the given diet selection. */
export function isRelevant(
  nameNo: string,
  diet: DietKey,
  customMarkers: string[]
): boolean {
  if (diet === "all") return true;
  if (diet === "custom") return customMarkers.includes(nameNo);
  const key = markerKey(nameNo);
  return key !== null && DIET_MARKERS[diet].has(key);
}

/** Filter a results list down to the markers relevant for the diet selection. */
export function filterByDiet(
  results: BiomarkerWithSeries[],
  diet: DietKey,
  customMarkers: string[]
): BiomarkerWithSeries[] {
  if (diet === "all") return results;
  if (diet === "custom") {
    const selected = new Set(customMarkers);
    return results.filter((r) => selected.has(r.biomarker.name_no));
  }
  const keys = DIET_MARKERS[diet];
  return results.filter((r) => {
    const key = markerKey(r.biomarker.name_no);
    return key !== null && keys.has(key);
  });
}

/**
 * The biomarker names a given selection currently reveals — used to seed the
 * Custom picker when "forking" from a preset (or from All).
 */
export function visibleMarkerNames(
  results: BiomarkerWithSeries[],
  diet: DietKey,
  customMarkers: string[]
): string[] {
  return filterByDiet(results, diet, customMarkers).map((r) => r.biomarker.name_no);
}
