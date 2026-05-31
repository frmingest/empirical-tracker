import type { BiomarkerWithSeries } from "./api";

export const CATEGORY_ORDER = [
  "Lipids",
  "CBC",
  "Metabolic",
  "Thyroid",
  "Renal",
  "Liver",
  "Nutrients",
  "Electrolytes",
  "Other",
] as const;

export type Category = (typeof CATEGORY_ORDER)[number];

/** Keyword-to-category map — first match wins. */
const RULES: [Category, string[]][] = [
  ["Lipids",       ["HDL", "LDL", "Kolesterol", "non-HDL"]],
  ["Thyroid",      ["TSH", "T4", "Tyroxin"]],
  ["Metabolic",    ["HbA1c", "HBA1C", "Glukose"]],
  ["CBC",          ["Hemoglobin", "Erytrocytter", "Leukocytter", "Hematokritt", "MCH", "MCV", "MCHC", "Trombocytter", "HB"]],
  ["Renal",        ["Kreatinin", "GFR", "Nyre"]],
  ["Liver",        ["ALAT", "ASAT", "GT", "Bilirubin", "ALP"]],
  ["Nutrients",    ["Ferritin", "Folat", "B12", "Vitamin D", "Transferrin", "Jern", "TIBC", "MMA", "Homocystein"]],
  ["Electrolytes", ["Natrium", "Kalium", "Kalsium", "Magnesium", "Fosfat"]],
];

export function getCategory(name: string): Category {
  const lower = name.toLowerCase();
  for (const [cat, keywords] of RULES) {
    if (keywords.some((kw) => lower.includes(kw.toLowerCase()))) return cat;
  }
  return "Other";
}

export type Grouped = Record<Category, BiomarkerWithSeries[]>;

export function groupByCategory(items: BiomarkerWithSeries[]): Grouped {
  const groups = Object.fromEntries(
    CATEGORY_ORDER.map((c) => [c, [] as BiomarkerWithSeries[]])
  ) as Grouped;

  for (const item of items) {
    groups[getCategory(item.biomarker.name_no)].push(item);
  }
  return groups;
}

/** Short display label — strip Norwegian prefix + parenthetical. */
export function shortLabel(name: string): string {
  const noParens = name.replace(/\s*\([^)]*\)/g, "").trim();
  return noParens.length > 26 ? noParens.slice(0, 24) + "…" : noParens;
}

/** Format ISO date "YYYY-MM-DD" → "Sep '23" */
export function fmtDate(iso: string): string {
  const d = new Date(iso + "T12:00:00Z");
  return d.toLocaleDateString("en-US", {
    month: "short",
    year: "2-digit",
    timeZone: "UTC",
  });
}

/** Format ISO date for display: "May 22, 2026" */
export function fmtDateLong(iso: string): string {
  const d = new Date(iso + "T12:00:00Z");
  return d.toLocaleDateString("en-US", {
    day: "numeric",
    month: "long",
    year: "numeric",
    timeZone: "UTC",
  });
}
