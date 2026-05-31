"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import { getBiomarkerResults } from "@/lib/api";
import type { BiomarkerWithSeries } from "@/lib/api";
import { MOCK_RESULTS } from "@/lib/mockData";
import { fmtDateLong, shortLabel } from "@/lib/biomarkerCategories";

type PanelSummary = {
  date: string;
  total: number;
  inRange: number;
  outOfRange: number;
  outOfRangeNames: string[];
};

function derivePanels(results: BiomarkerWithSeries[]): PanelSummary[] {
  const map = new Map<string, PanelSummary>();
  for (const { biomarker, series } of results) {
    for (const point of series) {
      if (!map.has(point.tested_at)) {
        map.set(point.tested_at, {
          date: point.tested_at,
          total: 0,
          inRange: 0,
          outOfRange: 0,
          outOfRangeNames: [],
        });
      }
      const p = map.get(point.tested_at)!;
      p.total++;
      if (point.in_range === true) p.inRange++;
      else if (point.in_range === false) {
        p.outOfRange++;
        p.outOfRangeNames.push(shortLabel(biomarker.name_no));
      }
    }
  }
  return [...map.values()].sort((a, b) => b.date.localeCompare(a.date));
}

export default function PanelsPage() {
  const { session, loading } = useAuth();
  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [isLive, setIsLive] = useState(false);
  const [dataLoading, setDataLoading] = useState(false);

  useEffect(() => {
    if (!session?.access_token) return;
    setDataLoading(true);
    getBiomarkerResults(session.access_token)
      .then((data) => {
        if (data.length > 0) {
          setResults(data);
          setIsLive(true);
        }
      })
      .catch(() => {})
      .finally(() => setDataLoading(false));
  }, [session]);

  if (loading || dataLoading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-zinc-700 border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

  const panels = derivePanels(results);

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* Nav */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link
            href="/"
            className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-sm"
          >
            ← Dashboard
          </Link>
          <span className="text-[var(--text-muted)]">·</span>
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
            Blood draw sessions
          </span>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Page title */}
        <div className="space-y-1">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
            Test panels
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? "Your data" : "Sample data"} · {panels.length} blood draw session{panels.length !== 1 ? "s" : ""}
          </p>
        </div>

        {/* Not signed in banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              Showing mock data.{" "}
              <Link href="/login" className="text-[var(--color-accent)] hover:underline">
                Sign in
              </Link>{" "}
              to see your real results.
            </p>
          </div>
        )}

        {/* Empty state */}
        {panels.length === 0 && (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-6 py-12 text-center">
            <p className="text-[var(--text-secondary)] text-sm">
              No panels yet — import a blood test to get started.
            </p>
            <Link
              href="/"
              className="inline-block mt-3 text-sm text-[var(--color-accent)] hover:underline"
            >
              Go to Dashboard
            </Link>
          </div>
        )}

        {/* Panel cards */}
        <div className="space-y-4">
          {panels.map((panel) => {
            const pct = panel.total > 0 ? Math.round((panel.inRange / panel.total) * 100) : 0;
            const shown = panel.outOfRangeNames.slice(0, 5);
            const extra = panel.outOfRangeNames.length - shown.length;

            return (
              <div
                key={panel.date}
                className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-5 py-5 space-y-4"
              >
                {/* Header row */}
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <p className="text-base font-semibold text-[var(--text-primary)]">
                      {fmtDateLong(panel.date)}
                    </p>
                    <p className="text-xs text-[var(--text-muted)] mt-0.5 font-mono">
                      {panel.total} biomarkers tested
                    </p>
                  </div>
                  <div className="flex items-center gap-3 text-sm font-mono tabular-nums shrink-0">
                    <span className="text-[var(--color-in-range)]">
                      {panel.inRange} in range
                    </span>
                    {panel.outOfRange > 0 && (
                      <span className="text-[var(--color-out-range)]">
                        {panel.outOfRange} out
                      </span>
                    )}
                  </div>
                </div>

                {/* Progress bar */}
                <div className="h-1.5 rounded-full bg-[var(--bg-elevated)] overflow-hidden">
                  <div
                    className="h-full rounded-full bg-emerald-500 transition-all"
                    style={{ width: `${pct}%` }}
                  />
                </div>

                {/* Out of range names */}
                {panel.outOfRangeNames.length > 0 && (
                  <div className="flex flex-wrap gap-1.5">
                    {shown.map((name) => (
                      <span
                        key={name}
                        className="text-xs px-2 py-0.5 rounded-full bg-rose-500/10 text-[var(--color-out-range)] border border-rose-500/20"
                      >
                        {name}
                      </span>
                    ))}
                    {extra > 0 && (
                      <span className="text-xs px-2 py-0.5 rounded-full bg-[var(--bg-elevated)] text-[var(--text-muted)]">
                        +{extra} more
                      </span>
                    )}
                  </div>
                )}
              </div>
            );
          })}
        </div>
      </main>
    </div>
  );
}
