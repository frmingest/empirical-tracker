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
    latestInRange === false ? "#f87171" : "#34d399";

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
      className="group block rounded-xl border border-zinc-800 bg-zinc-900 p-4 transition-all duration-200 hover:border-zinc-700 hover:bg-zinc-800/80 hover:-translate-y-0.5 hover:shadow-lg hover:shadow-black/40"
    >
      {/* Name row */}
      <div className="flex items-start justify-between gap-2 mb-3">
        <span className="text-sm text-zinc-300 leading-tight line-clamp-2 group-hover:text-zinc-100 transition-colors">
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
                latestInRange === false ? "text-rose-400" : "text-zinc-100"
              }`}
            >
              {latestValue}
            </span>
            {biomarker.unit && (
              <span className="text-xs text-zinc-500 font-mono">
                {biomarker.unit}
              </span>
            )}
          </>
        ) : (
          <span className="text-sm text-zinc-600 font-mono">No data</span>
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
              <div className="w-full h-px bg-zinc-700" />
            ) : (
              <div className="w-full h-px bg-zinc-800" />
            )}
          </div>
        )}
      </div>

      {/* Ref range */}
      {rangeLabel && (
        <div className="text-xs text-zinc-600 font-mono">
          ref {rangeLabel}
        </div>
      )}
    </Link>
  );
}
