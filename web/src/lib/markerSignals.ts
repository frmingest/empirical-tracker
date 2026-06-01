import type { BiomarkerInfo, ResultPoint } from "./api";
import { evaluateTarget, type TargetStatus } from "./clinicalTargets";

/**
 * Within-range trend signals + combined marker assessment (Sprint 7).
 *
 * The binary in/out-of-range flag hides the movement that often matters most:
 * a marker can stay green while doubling (ALT 25 → 55, lab upper 70) or while
 * climbing toward its bound. This module surfaces those — and folds in the
 * clinical-target check — into a single assessment so the green flag never
 * overrides a flagged trend.
 *
 * Everything here is **descriptive, not diagnostic**. With only a handful of
 * draws we deliberately avoid statistics or causal language; signals say "this
 * moved / this is near a line — look at it," nothing stronger. The strongest
 * within-range severity is "watch"; only an actual out-of-range value is "alert".
 */

export type SignalSeverity = "info" | "watch" | "alert";

export interface MarkerSignal {
  /** Stable identifier for the rule that fired. */
  id: string;
  severity: SignalSeverity;
  /** Short chip label, e.g. "Rising fast". */
  label: string;
  /** One-sentence explanation with the numbers behind it. */
  detail: string;
}

export type ConcernLevel = "out_of_range" | "attention" | "ok" | "unknown";

export interface MarkerAssessment {
  level: ConcernLevel;
  inRange: boolean | null;
  /** Target + trend findings, most severe first. */
  signals: MarkerSignal[];
  /** Clinical-target evaluation for the latest value, if a target is seeded. */
  target: TargetStatus | null;
}

/** Relative change of the last step that counts as a "large jump". */
const LARGE_JUMP = 0.5; // ≥50% (includes any doubling / halving)
const NOTABLE_JUMP = 0.25; // ≥25%
/** Fractional position within a bounded range that counts as "near a bound". */
const NEAR_BOUND = 0.1; // within 10% of either end

function round(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * Trend signals derived purely from the time-ordered series. The series is
 * assumed already sorted ascending by date (as the API returns it).
 */
export function trendSignals(
  series: ResultPoint[],
  biomarker: Pick<BiomarkerInfo, "ref_low" | "ref_high" | "ref_type" | "unit">
): MarkerSignal[] {
  const signals: MarkerSignal[] = [];
  if (series.length === 0) return signals;

  const latest = series[series.length - 1];
  const unit = biomarker.unit ? ` ${biomarker.unit}` : "";

  // 1. Step change between the two most recent draws.
  if (series.length >= 2) {
    const prev = series[series.length - 2];
    if (prev.value !== 0) {
      const rel = (latest.value - prev.value) / Math.abs(prev.value);
      const mag = Math.abs(rel);
      const up = rel > 0;
      const pct = Math.round(mag * 100);
      if (mag >= LARGE_JUMP) {
        signals.push({
          id: up ? "large-rise" : "large-fall",
          severity: "watch",
          label: up ? "Rising fast" : "Falling fast",
          detail: `${up ? "Up" : "Down"} ${pct}% since the previous draw (${round(
            prev.value
          )} → ${round(latest.value)}${unit}) — a large move even though it is still within range.`,
        });
      } else if (mag >= NOTABLE_JUMP) {
        signals.push({
          id: up ? "notable-rise" : "notable-fall",
          severity: "info",
          label: up ? "Trending up" : "Trending down",
          detail: `${up ? "Up" : "Down"} ${pct}% since the previous draw (${round(
            prev.value
          )} → ${round(latest.value)}${unit}).`,
        });
      }
    }
  }

  // 2. Latest value sitting near a bound of a bounded reference range.
  if (
    biomarker.ref_type === "bounded" &&
    biomarker.ref_low !== null &&
    biomarker.ref_high !== null &&
    biomarker.ref_high > biomarker.ref_low &&
    latest.in_range !== false
  ) {
    const pos =
      (latest.value - biomarker.ref_low) /
      (biomarker.ref_high - biomarker.ref_low);
    if (pos >= 1 - NEAR_BOUND) {
      signals.push({
        id: "near-upper",
        severity: "info",
        label: "Near upper limit",
        detail: `In range, but close to the upper reference bound (${round(
          latest.value
        )} vs ${biomarker.ref_high}${unit}).`,
      });
    } else if (pos <= NEAR_BOUND) {
      signals.push({
        id: "near-lower",
        severity: "info",
        label: "Near lower limit",
        detail: `In range, but close to the lower reference bound (${round(
          latest.value
        )} vs ${biomarker.ref_low}${unit}).`,
      });
    }
  }

  return signals;
}

const SEVERITY_RANK: Record<SignalSeverity, number> = {
  alert: 0,
  watch: 1,
  info: 2,
};

/**
 * Combine the in/out-of-range flag, the clinical target, and the trend signals
 * into one assessment. `level` drives the colour everywhere so that an in-range
 * marker with a flagged target or trend reads as "attention", never plain green.
 */
export function assessMarker(
  biomarker: BiomarkerInfo,
  series: ResultPoint[]
): MarkerAssessment {
  const latest = series.at(-1) ?? null;
  const inRange = latest?.in_range ?? null;

  const signals: MarkerSignal[] = [];

  const target = evaluateTarget(biomarker.name_no, latest?.value ?? null);
  if (target?.aboveTarget) {
    signals.push({
      id: "above-target",
      severity: "watch",
      label: "Above target",
      detail: `Within the lab reference, but at or above the clinical target of ${target.target.upper} ${target.target.unit} (latest ${round(
        latest!.value
      )}).`,
    });
  }

  signals.push(...trendSignals(series, biomarker));

  signals.sort((a, b) => SEVERITY_RANK[a.severity] - SEVERITY_RANK[b.severity]);

  let level: ConcernLevel;
  if (inRange === false) {
    level = "out_of_range";
  } else if (signals.some((s) => s.severity === "watch")) {
    level = "attention";
  } else if (inRange === true) {
    level = "ok";
  } else {
    level = "unknown";
  }

  return { level, inRange, signals, target };
}

/** CSS custom-property colour for a concern level (matches the theme palette). */
export function levelColor(level: ConcernLevel): string {
  switch (level) {
    case "out_of_range":
      return "var(--color-out-range)";
    case "attention":
      return "var(--color-warning)";
    case "ok":
      return "var(--color-in-range)";
    default:
      return "var(--text-muted)";
  }
}
