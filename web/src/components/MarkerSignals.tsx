import type { BiomarkerWithSeries } from "@/lib/api";
import { assessMarker, type SignalSeverity } from "@/lib/markerSignals";

interface Props {
  data: BiomarkerWithSeries;
}

const SEVERITY_STYLE: Record<SignalSeverity, { dot: string; text: string }> = {
  alert: { dot: "bg-rose-400", text: "text-rose-400" },
  watch: { dot: "bg-amber-500", text: "text-[var(--color-warning)]" },
  info: { dot: "bg-[var(--text-muted)]", text: "text-[var(--text-secondary)]" },
};

/**
 * Sprint 7 — surfaces clinical-target and within-range trend signals for a
 * single marker. Stays explicitly decision-support: it describes movement and
 * compares against general guideline bounds, never diagnoses.
 */
export function MarkerSignals({ data }: Props) {
  const { biomarker, series } = data;
  const assessment = assessMarker(biomarker, series);

  if (assessment.signals.length === 0 && !assessment.target) return null;

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-5 shadow-sm space-y-4">
      <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)]">
        Signals
      </h2>

      {assessment.signals.length > 0 ? (
        <ul className="space-y-2.5">
          {assessment.signals.map((s) => {
            const style = SEVERITY_STYLE[s.severity];
            return (
              <li key={s.id} className="flex items-start gap-2.5">
                <span
                  className={`mt-1.5 w-2 h-2 shrink-0 rounded-full ${style.dot}`}
                />
                <div className="space-y-0.5">
                  <p className={`text-sm font-medium ${style.text}`}>{s.label}</p>
                  <p className="text-xs text-[var(--text-secondary)] leading-relaxed">
                    {s.detail}
                  </p>
                </div>
              </li>
            );
          })}
        </ul>
      ) : (
        <p className="text-sm text-[var(--text-secondary)]">
          No target or trend signals — the latest value is within range and not
          near a bound.
        </p>
      )}

      {assessment.target && (
        <div className="rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-base)] px-3 py-2.5">
          <p className="text-xs text-[var(--text-secondary)] leading-relaxed">
            <span className="font-medium text-[var(--text-primary)]">
              Clinical target ≤ {assessment.target.target.upper}{" "}
              {assessment.target.target.unit}.
            </span>{" "}
            {assessment.target.target.rationale}
          </p>
          <p className="mt-1 text-[10px] text-[var(--text-muted)]">
            {assessment.target.target.source}
          </p>
        </div>
      )}

      <p className="text-[11px] text-[var(--text-muted)] leading-relaxed border-t border-[var(--border-subtle)] pt-3">
        Decision-support, not medical advice. Clinical targets are general
        guideline values, not personalised to your individual risk, and these
        signals describe movement across a handful of draws — they do not imply a
        diagnosis, causation, or statistical significance.
      </p>
    </div>
  );
}
