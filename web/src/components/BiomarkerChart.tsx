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
import type { BiomarkerWithSeries, ResultPoint } from "@/lib/api";

interface TooltipPayload {
  payload?: { tested_at: string; value: number; in_range: boolean | null };
}

function CustomTooltip({ active, payload }: { active?: boolean; payload?: TooltipPayload[] }) {
  if (!active || !payload?.length) return null;
  const d = payload[0]?.payload;
  if (!d) return null;

  return (
    <div className="rounded-lg border border-[var(--border-card)] bg-[var(--bg-surface)] px-3 py-2 shadow-xl text-xs">
      <p className="text-[var(--text-secondary)] mb-1">{fmtDate(d.tested_at)}</p>
      <p className="font-mono font-semibold text-[var(--text-primary)] text-sm">{d.value}</p>
      {d.in_range !== null && (
        <p className={d.in_range ? "text-emerald-600 mt-0.5" : "text-rose-500 mt-0.5"}>
          {d.in_range ? "In range" : "Out of range"}
        </p>
      )}
    </div>
  );
}

interface CustomDotProps {
  cx?: number;
  cy?: number;
  payload?: ResultPoint;
}

function CustomDot({ cx, cy, payload }: CustomDotProps) {
  if (cx === undefined || cy === undefined || !payload) return null;
  const color = payload.in_range === false ? "var(--color-out-range)" : "var(--color-in-range)";
  return (
    <circle
      cx={cx}
      cy={cy}
      r={4}
      fill={color}
      stroke="var(--bg-base)"
      strokeWidth={2}
    />
  );
}

interface Props {
  data: BiomarkerWithSeries;
}

export function BiomarkerChart({ data }: Props) {
  const { biomarker, series } = data;
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  if (!mounted) {
    return <div className="h-64 rounded-xl bg-[var(--bg-elevated)] animate-pulse" />;
  }

  if (series.length === 0) {
    return (
      <div className="h-64 rounded-xl bg-[var(--bg-card)] border border-[var(--border-card)] flex items-center justify-center">
        <p className="text-[var(--text-muted)] text-sm">No data recorded yet</p>
      </div>
    );
  }

  const chartData = series.map((p) => ({
    ...p,
    label: fmtDate(p.tested_at),
  }));

  const values = series.map((p) => p.value);
  const minVal = Math.min(...values);
  const maxVal = Math.max(...values);
  const refLow = biomarker.ref_low;
  const refHigh = biomarker.ref_high;

  // Pad domain to fit ref range and data
  const domainMin =
    refLow !== null ? Math.min(minVal, refLow) * 0.9 : minVal * 0.9;
  const domainMax =
    refHigh !== null ? Math.max(maxVal, refHigh) * 1.1 : maxVal * 1.1;

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-6 shadow-sm">
      <ResponsiveContainer width="100%" height={280}>
        <LineChart
          data={chartData}
          margin={{ top: 16, right: 24, bottom: 8, left: 0 }}
        >
          <CartesianGrid
            strokeDasharray="3 3"
            stroke="var(--border-subtle)"
            vertical={false}
          />
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
          <Tooltip content={<CustomTooltip />} />

          {/* Reference band */}
          {biomarker.ref_type === "bounded" &&
            refLow !== null &&
            refHigh !== null && (
              <ReferenceArea
                y1={refLow}
                y2={refHigh}
                fill="var(--color-in-range)"
                fillOpacity={0.07}
                stroke="none"
              />
            )}

          {/* Reference lines for one-sided ranges */}
          {biomarker.ref_type === "lt" && refHigh !== null && (
            <ReferenceLine
              y={refHigh}
              stroke="var(--color-in-range)"
              strokeDasharray="4 4"
              strokeOpacity={0.5}
              label={{ value: `< ${refHigh}`, fill: "var(--color-in-range)", fontSize: 10 }}
            />
          )}
          {biomarker.ref_type === "gt" && refLow !== null && (
            <ReferenceLine
              y={refLow}
              stroke="var(--color-in-range)"
              strokeDasharray="4 4"
              strokeOpacity={0.5}
              label={{ value: `> ${refLow}`, fill: "var(--color-in-range)", fontSize: 10 }}
            />
          )}

          <Line
            type="monotone"
            dataKey="value"
            stroke="var(--color-accent)"
            strokeWidth={2}
            dot={<CustomDot />}
            activeDot={{ r: 6, fill: "var(--color-accent)", stroke: "var(--bg-base)", strokeWidth: 2 }}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>

      {/* Legend */}
      {biomarker.ref_type !== "none" && (
        <div className="mt-4 flex items-center gap-4 text-xs text-[var(--text-secondary)]">
          <span className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-3 rounded-sm bg-emerald-500/20 border border-emerald-500/30" />
            Reference range
            {biomarker.ref_type === "bounded" &&
              refLow !== null &&
              refHigh !== null &&
              ` (${refLow} – ${refHigh})`}
          </span>
          <span className="flex items-center gap-1.5">
            <span className="inline-block w-3 h-1 bg-[var(--color-accent)] rounded" />
            Measured value
          </span>
        </div>
      )}
    </div>
  );
}
