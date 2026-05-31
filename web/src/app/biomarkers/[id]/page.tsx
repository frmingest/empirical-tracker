"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import { getBiomarkerResults } from "@/lib/api";
import type { BiomarkerWithSeries } from "@/lib/api";
import { MOCK_RESULTS } from "@/lib/mockData";
import { BiomarkerChart } from "@/components/BiomarkerChart";
import { StatusBadge } from "@/components/StatusBadge";
import {
  fmtDateLong,
  getCategory,
  shortLabel,
} from "@/lib/biomarkerCategories";

export default function BiomarkerDetailPage({ params }: { params: { id: string } }) {
  const { id } = params;
  const { session, loading } = useAuth();
  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [isLive, setIsLive] = useState(false);
  // Start true so the first render never reaches the "not found" branch while
  // auth is still settling or the real-data fetch hasn't fired yet.
  const [dataLoading, setDataLoading] = useState(true);

  useEffect(() => {
    if (loading) return; // auth not settled yet — keep the spinner
    if (!session?.access_token) {
      setDataLoading(false); // no session → show mock data
      return;
    }
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
  }, [session, loading]);

  if (loading || dataLoading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

  const entry = results.find((r) => r.biomarker.id === id);

  if (!entry) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="text-center space-y-3">
          <p className="text-[var(--text-secondary)]">Biomarker not found.</p>
          <Link href="/" className="text-blue-400 hover:text-blue-300 text-sm">
            ← Back to Dashboard
          </Link>
        </div>
      </div>
    );
  }

  const { biomarker, series } = entry;
  const latest = series.at(-1);
  const category = getCategory(biomarker.name_no);

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
          <span className="text-[var(--border-card)]">·</span>
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
            {category}
          </span>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Not signed in banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3 flex items-center justify-between gap-4">
            <p className="text-sm text-[var(--text-secondary)]">
              Showing mock data.{" "}
              <Link href="/login" className="text-blue-400 hover:text-blue-300">
                Sign in
              </Link>{" "}
              to see your real results.
            </p>
          </div>
        )}

        {/* Biomarker header */}
        <div className="space-y-2">
          <p className="text-xs text-[var(--text-muted)]">
            {isLive ? "Your data" : "Sample data"} · {category}
          </p>
          <div className="flex items-start justify-between gap-4">
            <h1 className="text-xl font-semibold text-[var(--text-primary)] leading-tight">
              {shortLabel(biomarker.name_no)}
            </h1>
            {latest && <StatusBadge inRange={latest.in_range} showLabel size="md" />}
          </div>
          {biomarker.name_no !== shortLabel(biomarker.name_no) && (
            <p className="text-xs text-[var(--text-muted)] font-mono">{biomarker.name_no}</p>
          )}
        </div>

        {/* Current value + ref range */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
            <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
              Latest value
            </p>
            <p className="text-2xl font-mono font-semibold text-[var(--text-primary)] tabular-nums">
              {latest?.value ?? "—"}
            </p>
            {biomarker.unit && (
              <p className="text-xs text-[var(--text-muted)] font-mono mt-0.5">{biomarker.unit}</p>
            )}
          </div>

          {latest && (
            <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
              <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
                Test date
              </p>
              <p className="text-sm text-[var(--text-primary)] leading-snug">
                {fmtDateLong(latest.tested_at)}
              </p>
            </div>
          )}

          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
            <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
              Reference
            </p>
            <p className="text-sm font-mono text-[var(--text-secondary)]">
              {biomarker.ref_range_raw || "—"}
            </p>
          </div>

          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
            <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
              Data points
            </p>
            <p className="text-2xl font-mono font-semibold text-[var(--text-primary)]">
              {series.length}
            </p>
          </div>
        </div>

        {/* Trend chart */}
        <div>
          <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)] mb-3">
            Trend over time
          </h2>
          <BiomarkerChart data={entry} />
        </div>

        {/* History table */}
        {series.length > 0 && (
          <div>
            <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)] mb-3">
              All results
            </h2>
            <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] overflow-hidden shadow-sm">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-[var(--border-subtle)]">
                    <th className="text-left px-4 py-3 text-[10px] uppercase tracking-widest text-[var(--text-muted)] font-normal">
                      Date
                    </th>
                    <th className="text-right px-4 py-3 text-[10px] uppercase tracking-widest text-[var(--text-muted)] font-normal">
                      Value
                    </th>
                    <th className="text-right px-4 py-3 text-[10px] uppercase tracking-widest text-[var(--text-muted)] font-normal">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {[...series].reverse().map((point, i) => (
                    <tr
                      key={point.tested_at}
                      className={i < series.length - 1 ? "border-b border-[var(--border-subtle)]" : ""}
                    >
                      <td className="px-4 py-3 text-[var(--text-secondary)] text-xs">
                        {fmtDateLong(point.tested_at)}
                      </td>
                      <td className="px-4 py-3 text-right font-mono text-[var(--text-primary)] tabular-nums">
                        {point.value}
                        {biomarker.unit && (
                          <span className="text-[var(--text-muted)] ml-1 text-xs">{biomarker.unit}</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <StatusBadge inRange={point.in_range} showLabel size="sm" />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}
