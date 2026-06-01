export interface BiomarkerInfo {
  id: string;
  name_no: string;
  name_en: string | null;
  unit: string | null;
  ref_range_raw: string;
  ref_low: number | null;
  ref_high: number | null;
  ref_type: "bounded" | "lt" | "gt" | "none";
}

export interface ResultPoint {
  /** ISO date: "YYYY-MM-DD" */
  tested_at: string;
  value: number;
  in_range: boolean | null;
}

export interface BiomarkerWithSeries {
  biomarker: BiomarkerInfo;
  series: ResultPoint[];
}

export interface ImportResult {
  panels_created: number;
  results_inserted: number;
}

export interface UserSettings {
  /** Which diet focus is active; see lib/dietProfiles.ts. */
  diet: "all" | "carnivore" | "low_carb" | "fasting" | "custom";
  /** Biomarker names (name_no) hand-picked for the 'custom' view. */
  custom_markers: string[];
}

// ── Sprint 3: diet events (correlation overlay annotations) ─────────────────────

export type DietEventKind =
  | "diet"
  | "fast"
  | "supplement"
  | "medication"
  | "lifestyle"
  | "other";

export interface DietEvent {
  id: string;
  label: string;
  kind: DietEventKind;
  /** ISO date "YYYY-MM-DD" when the change took effect. */
  started_on: string;
  /** Optional ISO end date; when set the event spans a shaded period. */
  ended_on: string | null;
  note: string | null;
}

export interface DietEventInput {
  label: string;
  kind: DietEventKind;
  started_on: string;
  ended_on?: string | null;
  note?: string | null;
}

// ── Sprint 4: food diary + multi-source food data ───────────────────────────────

/**
 * Where a food's numbers came from (ADR-018):
 *   off  — Open Food Facts (branded / barcode)
 *   mvt  — Matvaretabellen (Norwegian whole foods, lab-analysed)
 *   usda — USDA FoodData Central (American whole foods, lab-analysed)
 */
export type FoodSource = "off" | "mvt" | "usda";

/** A source the search box can target — a real source or "all" merged. */
export type FoodSearchSource = FoodSource | "all";

/** Short labels for the source badge / selector, keyed by source code. */
export const FOOD_SOURCE_LABEL: Record<FoodSource, string> = {
  off: "Open Food Facts",
  mvt: "Matvaretabellen",
  usda: "USDA",
};

/** A normalised food (nutrients per 100 g, as published — never estimated). */
export interface FoodItem {
  code: string;
  name: string;
  brand: string | null;
  quantity: string | null;
  energy_kcal_100g: number | null;
  carbs_100g: number | null;
  protein_100g: number | null;
  fat_100g: number | null;
  saturated_fat_100g: number | null;
  sodium_mg_100g: number | null;
  source: FoodSource;
}

export type Meal = "breakfast" | "lunch" | "dinner" | "snack" | "other";

/** A logged food item. Nutrient fields are the amounts actually consumed. */
export interface FoodEntry {
  id: string;
  logged_on: string;
  meal: Meal;
  food_name: string;
  brand: string | null;
  barcode: string | null;
  quantity_g: number | null;
  energy_kcal: number | null;
  carbs_g: number | null;
  protein_g: number | null;
  fat_g: number | null;
  sodium_mg: number | null;
  saturated_fat_g: number | null;
  source: FoodSource | null;
  note: string | null;
}

export interface FoodEntryInput {
  logged_on: string;
  meal: Meal;
  food_name: string;
  brand?: string | null;
  barcode?: string | null;
  quantity_g?: number | null;
  energy_kcal?: number | null;
  carbs_g?: number | null;
  protein_g?: number | null;
  fat_g?: number | null;
  sodium_mg?: number | null;
  saturated_fat_g?: number | null;
  source?: FoodSource | null;
  note?: string | null;
}

// ── Sprint 5: meal plans + calendar ─────────────────────────────────────────────

/** A named, reusable meal plan ("Carnivore week"). Groups planned meals. */
export interface MealPlan {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
}

export interface MealPlanInput {
  name: string;
  description?: string | null;
}

/** A meal scheduled on the calendar. Nutrient fields mirror FoodEntry. */
export interface PlannedMeal {
  id: string;
  plan_id: string | null;
  scheduled_on: string;
  meal: Meal;
  food_name: string;
  brand: string | null;
  barcode: string | null;
  quantity_g: number | null;
  energy_kcal: number | null;
  carbs_g: number | null;
  protein_g: number | null;
  fat_g: number | null;
  sodium_mg: number | null;
  saturated_fat_g: number | null;
  source: FoodSource | null;
  note: string | null;
  done: boolean;
}

export interface PlannedMealInput {
  scheduled_on: string;
  meal: Meal;
  food_name: string;
  plan_id?: string | null;
  brand?: string | null;
  barcode?: string | null;
  quantity_g?: number | null;
  energy_kcal?: number | null;
  carbs_g?: number | null;
  protein_g?: number | null;
  fat_g?: number | null;
  sodium_mg?: number | null;
  saturated_fat_g?: number | null;
  source?: FoodSource | null;
  note?: string | null;
  done?: boolean;
}

const API_BASE = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000";

function bearerHeaders(token: string): HeadersInit {
  return { Authorization: `Bearer ${token}` };
}

export async function getBiomarkerResults(
  token: string
): Promise<BiomarkerWithSeries[]> {
  const res = await fetch(`${API_BASE}/biomarkers/results`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /biomarkers/results → ${res.status}`);
  return res.json() as Promise<BiomarkerWithSeries[]>;
}

export async function importXlsx(
  file: File,
  token: string
): Promise<ImportResult> {
  const form = new FormData();
  form.append("file", file);
  const res = await fetch(`${API_BASE}/biomarkers/import`, {
    method: "POST",
    headers: bearerHeaders(token),
    body: form,
  });
  if (!res.ok) throw new Error(`POST /biomarkers/import → ${res.status}`);
  return res.json() as Promise<ImportResult>;
}

export async function deleteAllImports(token: string): Promise<void> {
  const res = await fetch(`${API_BASE}/biomarkers/import`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /biomarkers/import → ${res.status}`);
}

export async function deletePanelImport(
  panelId: string,
  token: string
): Promise<void> {
  const res = await fetch(`${API_BASE}/biomarkers/import/${panelId}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok)
    throw new Error(`DELETE /biomarkers/import/${panelId} → ${res.status}`);
}

export async function getSettings(token: string): Promise<UserSettings> {
  const res = await fetch(`${API_BASE}/settings`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /settings → ${res.status}`);
  return res.json() as Promise<UserSettings>;
}

export async function updateSettings(
  token: string,
  settings: UserSettings
): Promise<UserSettings> {
  const res = await fetch(`${API_BASE}/settings`, {
    method: "PUT",
    headers: {
      ...bearerHeaders(token),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(settings),
  });
  if (!res.ok) throw new Error(`PUT /settings → ${res.status}`);
  return res.json() as Promise<UserSettings>;
}

export async function addManualResult(
  token: string,
  biomarkerId: string,
  testedAt: string,
  value: number
): Promise<void> {
  const res = await fetch(`${API_BASE}/biomarkers/results/manual`, {
    method: "POST",
    headers: {
      ...bearerHeaders(token),
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ biomarker_id: biomarkerId, tested_at: testedAt, value }),
  });
  if (!res.ok) throw new Error(await res.text());
}

// ── Diet events ─────────────────────────────────────────────────────────────────

export async function listDietEvents(token: string): Promise<DietEvent[]> {
  const res = await fetch(`${API_BASE}/diet-events`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /diet-events → ${res.status}`);
  return res.json() as Promise<DietEvent[]>;
}

export async function createDietEvent(
  token: string,
  input: DietEventInput
): Promise<DietEvent> {
  const res = await fetch(`${API_BASE}/diet-events`, {
    method: "POST",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<DietEvent>;
}

export async function deleteDietEvent(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/diet-events/${id}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /diet-events/${id} → ${res.status}`);
}

// ── Food diary + Open Food Facts ─────────────────────────────────────────────────

export async function searchFoods(
  token: string,
  q: string,
  source: FoodSearchSource = "off"
): Promise<FoodItem[]> {
  const res = await fetch(
    `${API_BASE}/food-diary/search?q=${encodeURIComponent(q)}&source=${source}`,
    { headers: bearerHeaders(token), cache: "no-store" }
  );
  if (!res.ok) throw new Error(`GET /food-diary/search → ${res.status}`);
  return res.json() as Promise<FoodItem[]>;
}

export async function lookupBarcode(
  token: string,
  barcode: string
): Promise<FoodItem> {
  const res = await fetch(`${API_BASE}/food-diary/barcode/${encodeURIComponent(barcode)}`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /food-diary/barcode/${barcode} → ${res.status}`);
  return res.json() as Promise<FoodItem>;
}

export async function listFoodEntries(
  token: string,
  date?: string
): Promise<FoodEntry[]> {
  const qs = date ? `?date=${encodeURIComponent(date)}` : "";
  const res = await fetch(`${API_BASE}/food-diary${qs}`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /food-diary → ${res.status}`);
  return res.json() as Promise<FoodEntry[]>;
}

export async function createFoodEntry(
  token: string,
  input: FoodEntryInput
): Promise<FoodEntry> {
  const res = await fetch(`${API_BASE}/food-diary`, {
    method: "POST",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<FoodEntry>;
}

export async function deleteFoodEntry(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/food-diary/${id}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /food-diary/${id} → ${res.status}`);
}

// ── Meal plans + calendar ────────────────────────────────────────────────────────

export async function listMealPlans(token: string): Promise<MealPlan[]> {
  const res = await fetch(`${API_BASE}/meal-plans`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /meal-plans → ${res.status}`);
  return res.json() as Promise<MealPlan[]>;
}

export async function createMealPlan(
  token: string,
  input: MealPlanInput
): Promise<MealPlan> {
  const res = await fetch(`${API_BASE}/meal-plans`, {
    method: "POST",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<MealPlan>;
}

export async function deleteMealPlan(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/meal-plans/${id}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /meal-plans/${id} → ${res.status}`);
}

export async function listPlannedMeals(
  token: string,
  start?: string,
  end?: string
): Promise<PlannedMeal[]> {
  const params = new URLSearchParams();
  if (start) params.set("start", start);
  if (end) params.set("end", end);
  const qs = params.toString() ? `?${params.toString()}` : "";
  const res = await fetch(`${API_BASE}/meal-plans/calendar${qs}`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /meal-plans/calendar → ${res.status}`);
  return res.json() as Promise<PlannedMeal[]>;
}

export async function createPlannedMeal(
  token: string,
  input: PlannedMealInput
): Promise<PlannedMeal> {
  const res = await fetch(`${API_BASE}/meal-plans/calendar`, {
    method: "POST",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<PlannedMeal>;
}

export async function setPlannedMealDone(
  token: string,
  id: string,
  done: boolean
): Promise<PlannedMeal> {
  const res = await fetch(`${API_BASE}/meal-plans/calendar/${id}`, {
    method: "PATCH",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify({ done }),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<PlannedMeal>;
}

export async function deletePlannedMeal(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/meal-plans/calendar/${id}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /meal-plans/calendar/${id} → ${res.status}`);
}

// ── Sprint 6: account (GDPR data export + erasure) ──────────────────────────────

export interface AccountDeletion {
  data_deleted: boolean;
  account_deleted: boolean;
}

/** Download all of the user's data as a JSON document or a zip of CSVs. */
export async function exportAccountData(
  token: string,
  format: "json" | "csv"
): Promise<Blob> {
  const res = await fetch(`${API_BASE}/account/export?format=${format}`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /account/export → ${res.status}`);
  return res.blob();
}

/** Permanently erase the user's data and account (GDPR right to erasure). */
export async function deleteAccount(token: string): Promise<AccountDeletion> {
  const res = await fetch(`${API_BASE}/account`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /account → ${res.status}`);
  return res.json() as Promise<AccountDeletion>;
}

// ── Sprint 10: body metrics (weight, waist, blood pressure) ──────────────────────

/** A body-metric measurement. Every metric is optional; a row carries at least one. */
export interface BodyMetric {
  id: string;
  /** ISO date "YYYY-MM-DD" the measurement was taken. */
  measured_on: string;
  /** Weight in kilograms. */
  weight_kg: number | null;
  /** Waist circumference in centimetres. */
  waist_cm: number | null;
  /** Blood pressure, mmHg. Both halves or neither. */
  systolic: number | null;
  diastolic: number | null;
  note: string | null;
}

export interface BodyMetricInput {
  measured_on: string;
  weight_kg?: number | null;
  waist_cm?: number | null;
  systolic?: number | null;
  diastolic?: number | null;
  note?: string | null;
}

export async function listBodyMetrics(token: string): Promise<BodyMetric[]> {
  const res = await fetch(`${API_BASE}/body-metrics`, {
    headers: bearerHeaders(token),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`GET /body-metrics → ${res.status}`);
  return res.json() as Promise<BodyMetric[]>;
}

export async function createBodyMetric(
  token: string,
  input: BodyMetricInput
): Promise<BodyMetric> {
  const res = await fetch(`${API_BASE}/body-metrics`, {
    method: "POST",
    headers: { ...bearerHeaders(token), "Content-Type": "application/json" },
    body: JSON.stringify(input),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json() as Promise<BodyMetric>;
}

export async function deleteBodyMetric(token: string, id: string): Promise<void> {
  const res = await fetch(`${API_BASE}/body-metrics/${id}`, {
    method: "DELETE",
    headers: bearerHeaders(token),
  });
  if (!res.ok) throw new Error(`DELETE /body-metrics/${id} → ${res.status}`);
}
