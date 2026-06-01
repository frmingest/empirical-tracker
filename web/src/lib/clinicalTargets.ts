import { markerKey, type MarkerKey } from "./dietProfiles";

/**
 * Clinical-target layer (Sprint 7).
 *
 * The lab "reference range" is a population interval, not a statement of health.
 * For several markers a guideline-recommended *optimal* bound is tighter than the
 * lab's upper limit — e.g. LDL can sit comfortably inside the lab reference yet
 * above the cardiovascular target an at-risk person should aim for.
 *
 * These are **general guideline values, not per-user PII**: they depend only on
 * the marker's identity, so — like the diet-focus lists in `dietProfiles.ts` —
 * they live as a static reference map keyed by `markerKey()`, with no database
 * table and no migration. They are *decision-support context*, never a
 * personalised clinical instruction (the UI says so).
 *
 * Every seeded target here is an **upper** optimal bound ("lower is better"):
 * the value is flagged when it sits at or above the bound, even while still
 * inside the lab reference range. See `docs/adr/014-clinical-targets-trend-signals.md`.
 */

export interface ClinicalTarget {
  /** Optimal upper bound. Values at or above this are flagged. */
  upper: number;
  unit: string;
  /** One-line, plain-language reason the target is tighter than the lab range. */
  rationale: string;
  /** Guideline attribution, kept short. */
  source: string;
}

/**
 * Seeded guideline targets. Conservative, general-population/low-risk bounds —
 * deliberately not the aggressive secondary-prevention numbers, since the app
 * cannot know a user's individual risk. Sprint 8 added triglycerides alongside
 * the marker itself.
 */
const TARGETS: Partial<Record<MarkerKey, ClinicalTarget>> = {
  ldl: {
    upper: 3.0,
    unit: "mmol/L",
    rationale:
      "Guideline LDL targets for low-to-moderate cardiovascular risk sit around 3.0 mmol/L — lower still for higher-risk people. The lab's upper reference is well above that.",
    source: "ESC/EAS 2019 dyslipidaemia guideline (low-risk target)",
  },
  nonhdl: {
    upper: 3.4,
    unit: "mmol/L",
    rationale:
      "Non-HDL counts every atherogenic particle, not just LDL; a common general target is below ~3.4 mmol/L.",
    source: "ESC/EAS 2019 (non-HDL, low-risk target)",
  },
  total_chol: {
    upper: 5.0,
    unit: "mmol/L",
    rationale:
      "The general-population guideline target for total cholesterol is below ~5.0 mmol/L.",
    source: "ESC/EAS 2019 general-population target",
  },
  hba1c: {
    upper: 39,
    unit: "mmol/mol",
    rationale:
      "Below ~39 mmol/mol (5.7%) is the optimal, non-prediabetic band. The lab's upper reference (42) already overlaps the prediabetes range.",
    source: "ADA glycaemic categories (optimal < 39 mmol/mol)",
  },
  triglycerides: {
    upper: 1.7,
    unit: "mmol/L",
    rationale:
      "Desirable fasting triglycerides sit below ~1.7 mmol/L. On low-carb / carnivore eating this number usually falls well under the lab's upper reference, so the tighter target is the more informative line to watch.",
    source: "ESC/EAS 2019 dyslipidaemia guideline (desirable fasting TG)",
  },
};

/** Guideline target for a marker by its raw Norwegian name, or null if none seeded. */
export function clinicalTarget(nameNo: string): ClinicalTarget | null {
  const key = markerKey(nameNo);
  return key ? TARGETS[key] ?? null : null;
}

export interface TargetStatus {
  target: ClinicalTarget;
  /** True when the value is at or above the optimal upper bound. */
  aboveTarget: boolean;
  /** value − upper (positive when over target). */
  margin: number;
}

/** Evaluate a value against the marker's clinical target, if one exists. */
export function evaluateTarget(
  nameNo: string,
  value: number | null
): TargetStatus | null {
  const target = clinicalTarget(nameNo);
  if (!target || value === null) return null;
  return {
    target,
    aboveTarget: value >= target.upper,
    margin: value - target.upper,
  };
}
