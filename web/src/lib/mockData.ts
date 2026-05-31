import type { BiomarkerWithSeries, DietEvent, FoodEntry } from "./api";

/** Representative mock data matching the real XLSX structure.
 *  Dates: 2023-09-15, 2024-05-31, 2025-03-13, 2026-05-22 (chronological).
 *  TODO: replace with live getBiomarkerResults() when auth is wired (Sprint 1 auth).
 */
export const MOCK_RESULTS: BiomarkerWithSeries[] = [
  // ── Lipids ──────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-hdl",
      name_no: "P-HDL-kolesterol (High-Density Lipoprotein Cholesterol)",
      name_en: "HDL Cholesterol",
      unit: "mmol/L",
      ref_range_raw: "0,9 - 2,0",
      ref_low: 0.9,
      ref_high: 2.0,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 1.1, in_range: true },
      { tested_at: "2024-05-31", value: 1.5, in_range: true },
      { tested_at: "2025-03-13", value: 1.3, in_range: true },
      { tested_at: "2026-05-22", value: 1.3, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-ldl",
      name_no: "P-LDL-kolesterol (Low-Density Lipoprotein Cholesterol)",
      name_en: "LDL Cholesterol",
      unit: "mmol/L",
      ref_range_raw: "1,4 - 4,7",
      ref_low: 1.4,
      ref_high: 4.7,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 4.3, in_range: true },
      { tested_at: "2024-05-31", value: 3.5, in_range: true },
      { tested_at: "2025-03-13", value: 3.6, in_range: true },
      { tested_at: "2026-05-22", value: 4.1, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-chol",
      name_no: "P-Kolesterol (Cholesterol)",
      name_en: "Total Cholesterol",
      unit: "mmol/L",
      ref_range_raw: "3,3 - 6,9",
      ref_low: 3.3,
      ref_high: 6.9,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 5.5, in_range: true },
      { tested_at: "2024-05-31", value: 4.8, in_range: true },
      { tested_at: "2025-03-13", value: 4.8, in_range: true },
      { tested_at: "2026-05-22", value: 5.8, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-nonhdl",
      name_no: "P-non-HDL-kolesterol",
      name_en: "non-HDL Cholesterol",
      unit: "mmol/L",
      ref_range_raw: "1,5 - 4,8",
      ref_low: 1.5,
      ref_high: 4.8,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 4.4, in_range: true },
      { tested_at: "2024-05-31", value: 3.3, in_range: true },
      { tested_at: "2025-03-13", value: 3.5, in_range: true },
      { tested_at: "2026-05-22", value: 4.5, in_range: true },
    ],
  },

  // ── CBC ──────────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-hgb",
      name_no: "B-Hemoglobin",
      name_en: "Hemoglobin",
      unit: "g/dL",
      ref_range_raw: "13,4 - 17,0",
      ref_low: 13.4,
      ref_high: 17.0,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2025-03-13", value: 15.4, in_range: true },
      { tested_at: "2026-05-22", value: 15.2, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-rbc",
      name_no: "B-Erytrocytter (Red Blood Cells)",
      name_en: "RBC",
      unit: "10¹²/L",
      ref_range_raw: "4,5 - 5,8",
      ref_low: 4.5,
      ref_high: 5.8,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 5.4, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-wbc",
      name_no: "B-Leukocytter (White Blood Cells)",
      name_en: "WBC",
      unit: "10⁹/L",
      ref_range_raw: "3,9 - 9,8",
      ref_low: 3.9,
      ref_high: 9.8,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 4.9, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-hct",
      name_no: "B-Hematokritt (Hematocrit)",
      name_en: "Hematocrit",
      unit: "%",
      ref_range_raw: "39 - 51",
      ref_low: 39,
      ref_high: 51,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 45, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-mch",
      name_no: "Ery-MCH (Mean Corpuscular Hemoglobin)",
      name_en: "MCH",
      unit: "pg",
      ref_range_raw: "28 - 33",
      ref_low: 28,
      ref_high: 33,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 29, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-mchc",
      name_no: "Ery-MCHC (Mean Corpuscular Hemoglobin Concentration)",
      name_en: "MCHC",
      unit: "g/dL",
      ref_range_raw: "32,8 - 36,6",
      ref_low: 32.8,
      ref_high: 36.6,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 34.4, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-mcv",
      name_no: "Ery-MCV (Mean Corpuscular Volume)",
      name_en: "MCV",
      unit: "fL",
      ref_range_raw: "83 - 97",
      ref_low: 83,
      ref_high: 97,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 83, in_range: true }],
  },

  // ── Metabolic ────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-hba1c",
      name_no: "B-HbA1c (Glycated Hemoglobin)",
      name_en: "HbA1c",
      unit: "mmol/mol",
      ref_range_raw: "27 - 42",
      ref_low: 27,
      ref_high: 42,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2025-03-13", value: 34, in_range: true }],
  },

  // ── Thyroid ──────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-tsh",
      name_no: "P-TSH (Thyroid Stimulating Hormone)",
      name_en: "TSH",
      unit: "mIU/L",
      ref_range_raw: "0,35 - 3,6",
      ref_low: 0.35,
      ref_high: 3.6,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 0.62, in_range: true },
      { tested_at: "2024-05-31", value: 0.46, in_range: true },
      { tested_at: "2025-03-13", value: 0.37, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-t4",
      name_no: "P-T4, fritt",
      name_en: "Free T4",
      unit: "pmol/L",
      ref_range_raw: "9,5 - 16,0",
      ref_low: 9.5,
      ref_high: 16.0,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 13.8, in_range: true },
      { tested_at: "2024-05-31", value: 12.4, in_range: true },
      { tested_at: "2025-03-13", value: 11.9, in_range: true },
    ],
  },

  // ── Renal ────────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-creat",
      name_no: "P-Kreatinin (Creatinine)",
      name_en: "Creatinine",
      unit: "µmol/L",
      ref_range_raw: "60 - 105",
      ref_low: 60,
      ref_high: 105,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 68, in_range: true },
      { tested_at: "2024-05-31", value: 70, in_range: true },
      { tested_at: "2025-03-13", value: 66, in_range: true },
      { tested_at: "2026-05-22", value: 61, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-gfr",
      name_no:
        "Nyre-estimert GFR (Estimated Glomerular Filtration Rate) (overfl. = 1,73m²)",
      name_en: "eGFR",
      unit: "mL/min/1.73m²",
      ref_range_raw: "83 - 136",
      ref_low: 83,
      ref_high: 136,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 116, in_range: true },
      { tested_at: "2024-05-31", value: 113, in_range: true },
      { tested_at: "2025-03-13", value: 116, in_range: true },
      { tested_at: "2026-05-22", value: 116, in_range: true },
    ],
  },

  // ── Liver ────────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-alat",
      name_no: "P-ALAT (Alanine Aminotransferase)",
      name_en: "ALT",
      unit: "U/L",
      ref_range_raw: "10 - 70",
      ref_low: 10,
      ref_high: 70,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 27, in_range: true },
      { tested_at: "2024-05-31", value: 22, in_range: true },
      { tested_at: "2025-03-13", value: 25, in_range: true },
      { tested_at: "2026-05-22", value: 55, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-gt",
      name_no: "P-GT",
      name_en: "GGT",
      unit: "U/L",
      ref_range_raw: "10 - 80",
      ref_low: 10,
      ref_high: 80,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2023-09-15", value: 18, in_range: true }],
  },

  // ── Nutrients ────────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-ferr",
      name_no: "P-Ferritin",
      name_en: "Ferritin",
      unit: "µg/L",
      ref_range_raw: "30 - 470",
      ref_low: 30,
      ref_high: 470,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 262, in_range: true },
      { tested_at: "2024-05-31", value: 217, in_range: true },
      { tested_at: "2025-03-13", value: 295, in_range: true },
      { tested_at: "2026-05-22", value: 335, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-folat",
      name_no: "P-Folat (Folate)",
      name_en: "Folate",
      unit: "nmol/L",
      ref_range_raw: "6,3 - 34",
      ref_low: 6.3,
      ref_high: 34,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 25, in_range: true },
      { tested_at: "2024-05-31", value: 25, in_range: true },
      { tested_at: "2025-03-13", value: 19, in_range: true },
      { tested_at: "2026-05-22", value: 14.4, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-b12",
      name_no: "P-Vit B12, total (Kobalamin) (Vitamin B12)",
      name_en: "Vitamin B12",
      unit: "pmol/L",
      ref_range_raw: "167 - 695",
      ref_low: 167,
      ref_high: 695,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 424, in_range: true },
      { tested_at: "2024-05-31", value: 497, in_range: true },
      { tested_at: "2025-03-13", value: 502, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-b12-active",
      name_no: "P-Vit B12 aktivt",
      name_en: "Active B12",
      unit: "pmol/L",
      ref_range_raw: "32 - 207",
      ref_low: 32,
      ref_high: 207,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2024-05-31", value: 128, in_range: true },
      { tested_at: "2025-03-13", value: 128, in_range: true },
      { tested_at: "2026-05-22", value: 150, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-vitd",
      name_no: "P-Vitamin D (25-OH)",
      name_en: "Vitamin D",
      unit: "nmol/L",
      ref_range_raw: "50 - 150",
      ref_low: 50,
      ref_high: 150,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2023-09-15", value: 70, in_range: true },
      { tested_at: "2024-05-31", value: 57, in_range: true },
      { tested_at: "2025-03-13", value: 43, in_range: false },
    ],
  },
  {
    biomarker: {
      id: "mock-transferrin",
      name_no: "P-Transferrin",
      name_en: "Transferrin",
      unit: "g/L",
      ref_range_raw: "1,9 - 3,3",
      ref_low: 1.9,
      ref_high: 3.3,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2023-09-15", value: 2.3, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-iron",
      name_no: "P-Jern",
      name_en: "Iron",
      unit: "µmol/L",
      ref_range_raw: "6,0 - 28",
      ref_low: 6.0,
      ref_high: 28,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2023-09-15", value: 18, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-homocys",
      name_no: "P-Homocystein",
      name_en: "Homocysteine",
      unit: "µmol/L",
      ref_range_raw: "6,2 - 16,0",
      ref_low: 6.2,
      ref_high: 16.0,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2023-09-15", value: 7.5, in_range: true }],
  },
  {
    biomarker: {
      id: "mock-mma",
      name_no: "P-MMA (Metylmalonsyre)",
      name_en: "MMA",
      unit: "µmol/L",
      ref_range_raw: "0,08 - 0,24",
      ref_low: 0.08,
      ref_high: 0.24,
      ref_type: "bounded",
    },
    series: [{ tested_at: "2023-09-15", value: 0.1, in_range: true }],
  },

  // ── Electrolytes ─────────────────────────────────────────────────────────────
  {
    biomarker: {
      id: "mock-na",
      name_no: "S-Natrium (Sodium)",
      name_en: "Sodium",
      unit: "mmol/L",
      ref_range_raw: "137 - 145",
      ref_low: 137,
      ref_high: 145,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2024-05-31", value: 139, in_range: true },
      { tested_at: "2025-03-13", value: 139, in_range: true },
    ],
  },
  {
    biomarker: {
      id: "mock-k",
      name_no: "S-Kalium (Potassium)",
      name_en: "Potassium",
      unit: "mmol/L",
      ref_range_raw: "3,5 - 5,0",
      ref_low: 3.5,
      ref_high: 5.0,
      ref_type: "bounded",
    },
    series: [
      { tested_at: "2024-05-31", value: 4.4, in_range: true },
      { tested_at: "2025-03-13", value: 4.3, in_range: true },
    ],
  },
];

/** Sample diet annotations for the signed-out correlation-overlay demo. */
export const MOCK_DIET_EVENTS: DietEvent[] = [
  {
    id: "mock-evt-carnivore",
    label: "Started carnivore",
    kind: "diet",
    started_on: "2024-05-31",
    ended_on: null,
    note: "Switched to an all-meat elimination diet.",
  },
  {
    id: "mock-evt-fast",
    label: "5-day fast",
    kind: "fast",
    started_on: "2025-03-13",
    ended_on: "2026-05-22",
    note: "Sample extended-fasting block.",
  },
];

/** Sample food-diary entries for the signed-out demo. */
export const MOCK_FOOD_ENTRIES: FoodEntry[] = [
  {
    id: "mock-food-1",
    logged_on: new Date().toISOString().slice(0, 10),
    meal: "breakfast",
    food_name: "Eggs, whole, cooked",
    brand: null,
    barcode: null,
    quantity_g: 100,
    energy_kcal: 155,
    carbs_g: 1.1,
    protein_g: 13,
    fat_g: 11,
    note: null,
  },
  {
    id: "mock-food-2",
    logged_on: new Date().toISOString().slice(0, 10),
    meal: "dinner",
    food_name: "Ribeye steak",
    brand: null,
    barcode: null,
    quantity_g: 250,
    energy_kcal: 728,
    carbs_g: 0,
    protein_g: 60,
    fat_g: 55,
    note: null,
  },
];

/** Derive summary stats from mock data. */
export function getMockStats() {
  const allDates = new Set(
    MOCK_RESULTS.flatMap((r) => r.series.map((p) => p.tested_at))
  );
  const sortedDates = [...allDates].sort();
  return {
    biomarkerCount: MOCK_RESULTS.length,
    panelCount: allDates.size,
    lastTestedAt: sortedDates.at(-1) ?? null,
  };
}
