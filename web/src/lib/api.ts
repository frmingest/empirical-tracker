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
