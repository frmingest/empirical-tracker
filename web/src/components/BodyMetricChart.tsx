"use client";

import { useEffect, useState } from "react";
import {
  CartesianGrid,
  Line,
  LineChart,
  ReferenceArea,
  ReferenceLine,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { fmtDate } from "@/lib/biomarkerCategories";
import type { BodyMetric, DietEvent, ResultPoint } from "@/lib/api";
import { buildAnnotations } from "@/lib/chartAnnotations";

/** One plotted series within a chart (a single chart may carry two, e.g. BP). */
export interface MetricLine {
  /** Key on each {@link BodyMetric} row to read the value from. */
  field: keyof Pick<BodyMetric, "weight_kg" | "waist_cm" | "systolic" | "diastolic">;
  label: string;
  /** Stroke colour (a CSS custom-property reference). */
  color: string;
}

/** An optional dashed guideline line — a general population reference, not a
 *  personalised target. Kept visually distinct (neutral, dashed) and always
 *  labelled "guideline" so it is never mistaken for a verdict. */
export interface Guideline {
  value: number;
  label: string;
}

interface Props {
  title: string;
  unit: string;
  metrics: BodyMetric[];
  lines: MetricLine[];
  guidelines?: Guideline[];
  /** Diet events to overlay as correlation annotations (Sprint 3 overlay). */
  annotations?: DietEvent[];
}

interface Row {
  label: string;
  [field: string]: string | number | null;
}

export function BodyMetricChart({
  title,
  unit,
  metrics,
  lines,
  guidelines = [],
  annotations = [],
}: Props) {
  const [mounted, setMounted] = useState(false);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => setMounted(true), []);

  // Only the rows that carry at least one of this chart's fields.
  const rows = metrics.filter((m) => lines.some((l) => m[l.field] != null));

  if (!mounted) {
    return <div className="h-64 rounded-xl bg-[var(--bg-elevated)] animate-pulse" />;
  }

  if (rows.length === 0) {
    return (
      <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-6 shadow-sm">
        <h3 className="text-sm font-semibold text-[var(--text-primary)] mb-1">{title}</h3>
        <div className="h-56 flex items-center justify-center">
          <p className="text-[var(--text-muted)] text-sm">No {title.toLowerCase()} recorded yet</p>
        </div>
      </div>
    );
  }

  const chartData: Row[] = rows.map((m) => {
    const row: Row = { label: fmtDate(m.measured_on) };
    for (const l of lines) row[l.field] = m[l.field];
    return row;
  });

  // Domain padding across every plotted value plus any guideline lines.
  const values = rows.flatMap((m) =>
    lines.map((l) => m[l.field]).filter((v): v is number => v != null)
  );
  const candidates = [...values, ...guidelines.map((g) => g.value)];
  const domainMin = Math.min(...candidates) * 0.92;
  const domainMax = Math.max(...candidates) * 1.08;

  // Correlation overlay — snap diet events onto this chart's x-axis. The
  // synthetic series only needs the dates buildAnnotations() reads.
  const series: ResultPoint[] = rows.map((m) => ({
    tested_at: m.measured_on,
    value: 0,
    in_range: null,
  }));
  const overlay = buildAnnotations(annotations, series);

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-6 shadow-sm">
      <div className="flex items-baseline justify-between mb-3">
        <h3 className="text-sm font-semibold text-[var(--text-primary)]">{title}</h3>
        <span className="text-xs text-[var(--text-muted)] font-mono">{unit}</span>
      </div>
      <ResponsiveContainer width="100%" height={240}>
        <LineChart data={chartData} margin={{ top: 16, right: 24, bottom: 8, left: 0 }}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--border-subtle)" vertical={false} />
          <XAxis
            dataKey="label"
            tick={{ fill: "var(--text-muted)", fontSize: 11, fontFamily: "var(--font-geist-mono)" }}
            axisLine={{ stroke: "var(--border-subtle)" }}
            tickLine={false}
          />
          <YAxis
            domain={[domainMin, domainMax]}
            tick={{ fill: "var(--text-muted)", fontSize: 11, fontFamily: "var(--font-geist-mono)" }}
            axisLine={false}
            tickLine={false}
            width={48}
          />
          <Tooltip
            contentStyle={{
              background: "var(--bg-surface)",
              border: "1px solid var(--border-card)",
              borderRadius: "0.5rem",
              fontSize: "12px",
            }}
            labelStyle={{ color: "var(--text-secondary)" }}
          />

          {/* General population guideline(s) — neutral dashed, never a verdict */}
          {guidelines.map((g) => (
            <ReferenceLine
              key={`guide-${g.label}`}
              y={g.value}
              stroke="var(--text-muted)"
              strokeDasharray="5 3"
              strokeOpacity={0.6}
              label={{ value: g.label, fill: "var(--text-muted)", fontSize: 10, position: "insideBottomRight" }}
            />
          ))}

          {/* Correlation overlay — diet annotations (Sprint 3) */}
          {overlay.map((a) =>
            a.x2 ? (
              <ReferenceArea key={`area-${a.id}`} x1={a.x1} x2={a.x2} fill={a.color} fillOpacity={0.08} stroke="none" />
            ) : null
          )}
          {overlay.map((a) => (
            <ReferenceLine
              key={`line-${a.id}`}
              x={a.x1}
              stroke={a.color}
              strokeDasharray="3 3"
              strokeOpacity={0.7}
              label={{ value: a.label, fill: a.color, fontSize: 10, position: "insideTopLeft" }}
            />
          ))}

          {lines.map((l) => (
            <Line
              key={l.field}
              type="monotone"
              dataKey={l.field}
              name={l.label}
              stroke={l.color}
              strokeWidth={2}
              dot={{ r: 3, fill: l.color, stroke: "var(--bg-base)", strokeWidth: 1 }}
              activeDot={{ r: 5 }}
              connectNulls
              isAnimationActive={false}
            />
          ))}
        </LineChart>
      </ResponsiveContainer>

      {/* Legend: plotted lines + any guideline */}
      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-[var(--text-secondary)]">
        {lines.map((l) => (
          <span key={`legend-${l.field}`} className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-1 rounded" style={{ backgroundColor: l.color }} />
            {l.label}
          </span>
        ))}
        {guidelines.map((g) => (
          <span key={`legend-guide-${g.label}`} className="flex items-center gap-1.5">
            <span className="inline-block w-3 border-t-2 border-dashed border-[var(--text-muted)]" />
            {g.label}
          </span>
        ))}
      </div>

      {/* Correlation-overlay legend */}
      {overlay.length > 0 && (
        <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1.5 text-xs text-[var(--text-secondary)]">
          {overlay.map((a) => (
            <span key={`legend-${a.id}`} className="flex items-center gap-1.5">
              <span
                className="inline-block w-3 h-3 rounded-sm border"
                style={{ backgroundColor: a.color, borderColor: a.color, opacity: 0.7 }}
              />
              {a.label}
              {a.x2 ? ` (${a.x1} → ${a.x2})` : ` (${a.x1})`}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}
