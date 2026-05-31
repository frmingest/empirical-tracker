"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { Line, LineChart, ResponsiveContainer } from "recharts";
import { shortLabel } from "@/lib/biomarkerCategories";
import type { BiomarkerWithSeries, ResultPoint } from "@/lib/api";
import { StatusBadge } from "./StatusBadge";

interface Props {
  data: BiomarkerWithSeries;
}

export function BiomarkerCard({ data }: Props) {
  const { biomarker, series } = data;
  const [mounted, setMounted] = useState(false);
  useEffect(() => setMounted(true), []);

  const latest: ResultPoint | undefined = series.at(-1);
  const latestValue = latest?.value ?? null;
  const latestInRange = latest?.in_range ?? null;

  const sparkData = series.map((p) => ({ v: p.value }));

  const lineColor =
    latestInRange === false ? "var(--color-out-range)" : "var(--color-in-range)";

  const rangeLabel =
    biomarker.ref_type === "bounded" &&
    biomarker.ref_low !== null &&
    biomarker.ref_high !== null
      ? `${biomarker.ref_low} – ${biomarker.ref_high}`
      : biomarker.ref_type === "lt" && biomarker.ref_high !== null
        ? `< ${biomarker.ref_high}`
        : biomarker.ref_type === "gt" && biomarker.ref_low !== null
          ? `> ${biomarker.ref_low}`
          : null;

  return (
    <Link
      href={`/biomarkers/${biomarker.id}`}
      className="group block rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 transition-all duration-200 hover:border-[var(--border-subtle)] hover:bg-[var(--bg-elevated)] hover:-translate-y-0.5 hover:shadow-md"
    >
      {/* Name row */}
      <div className="flex items-start justify-between gap-2 mb-3">
        <span className="text-sm text-[var(--text-secondary)] leading-tight line-clamp-2 group-hover:text-[var(--text-primary)] transition-colors">
          {shortLabel(biomarker.name_no)}
        </span>
        <StatusBadge inRange={latestInRange} />
      </div>

      {/* Value row */}
      <div className="flex items-baseline gap-1.5 mb-3">
        {latestValue !== null ? (
          <>
            <span
              className={`text-2xl font-mono font-semibold tabular-nums leading-none ${
                latestInRange === false ? "text-[var(--color-out-range)]" : "text-[var(--text-primary)]"
              }`}
            >
              {latestValue}
            </span>
            {biomarker.unit && (
              <span className="text-xs text-[var(--text-secondary)] font-mono">
                {biomarker.unit}
              </span>
            )}
          </>
        ) : (
          <span className="text-sm text-[var(--text-muted)] font-mono">No data</span>
        )}
      </div>

      {/* Sparkline */}
      <div className="h-8 mb-2">
        {mounted && sparkData.length > 1 ? (
          <ResponsiveContainer width="100%" height="100%">
            <LineChart data={sparkData}>
              <Line
                type="monotone"
                dataKey="v"
                stroke={lineColor}
                strokeWidth={1.5}
                dot={false}
                isAnimationActive={false}
              />
            </LineChart>
          </ResponsiveContainer>
        ) : (
          <div className="h-full w-full flex items-center">
            {sparkData.length === 1 ? (
              <div className="w-full h-px bg-[var(--border-card)]" />
            ) : (
              <div className="w-full h-px bg-[var(--border-subtle)]" />
            )}
          </div>
        )}
      </div>

      {/* Ref range */}
      {rangeLabel && (
        <div className="text-xs text-[var(--text-muted)] font-mono">
          ref {rangeLabel}
        </div>
      )}
    </Link>
  );
}
