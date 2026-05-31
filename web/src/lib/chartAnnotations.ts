import type { DietEvent, DietEventKind, ResultPoint } from "./api";
import { fmtDate } from "./biomarkerCategories";

/**
 * Correlation-overlay annotations.
 *
 * The biomarker chart uses a *categorical* x-axis keyed on each draw's formatted
 * label (e.g. "Sep '23"), so an annotation can only sit on a data point. A diet
 * event rarely falls exactly on a blood-draw date, so we snap it to the nearest
 * draw. This is an honest visual aid for spotting whether a regimen change lines
 * up with a shift in a marker — it is NOT a statistical or clinical claim of
 * cause and effect.
 */

export interface ChartAnnotation {
  id: string;
  label: string;
  kind: DietEventKind;
  /** Stroke/fill colour (a CSS custom property reference). */
  color: string;
  /** Category label for the marker line / start of a shaded period. */
  x1: string;
  /** Category label for the end of a shaded period; null for a point event. */
  x2: string | null;
}

/** Colour each kind of event, reusing the theme's semantic palette. */
const KIND_COLOR: Record<DietEventKind, string> = {
  diet: "var(--color-warning)",
  fast: "var(--color-accent)",
  supplement: "var(--color-in-range)",
  medication: "var(--color-out-range)",
  lifestyle: "var(--color-accent)",
  other: "var(--text-muted)",
};

export function kindColor(kind: DietEventKind): string {
  return KIND_COLOR[kind] ?? KIND_COLOR.other;
}

function daysBetween(a: string, b: string): number {
  const ms = Date.parse(a + "T12:00:00Z") - Date.parse(b + "T12:00:00Z");
  return Math.abs(ms) / 86_400_000;
}

/** Index of the draw closest in time to `iso`; -1 if the series is empty. */
function nearestIndex(series: ResultPoint[], iso: string): number {
  if (series.length === 0) return -1;
  let best = 0;
  let bestDist = Infinity;
  for (let i = 0; i < series.length; i++) {
    const d = daysBetween(series[i].tested_at, iso);
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/**
 * Project diet events onto the chart's category labels. Events are kept only
 * when there is at least one data point to anchor them to. Period events whose
 * start and end snap to the same draw collapse to a point marker.
 */
export function buildAnnotations(
  events: DietEvent[],
  series: ResultPoint[]
): ChartAnnotation[] {
  if (series.length === 0) return [];
  const out: ChartAnnotation[] = [];
  for (const ev of events) {
    const startIdx = nearestIndex(series, ev.started_on);
    if (startIdx < 0) continue;
    const x1 = fmtDate(series[startIdx].tested_at);
    let x2: string | null = null;
    if (ev.ended_on) {
      const endIdx = nearestIndex(series, ev.ended_on);
      if (endIdx > startIdx) x2 = fmtDate(series[endIdx].tested_at);
    }
    out.push({ id: ev.id, label: ev.label, kind: ev.kind, color: kindColor(ev.kind), x1, x2 });
  }
  return out;
}
