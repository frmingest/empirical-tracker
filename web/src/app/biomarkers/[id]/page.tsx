"use client";

import { use, useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import { getBiomarkerResults, listDietEvents } from "@/lib/api";
import type { BiomarkerWithSeries, DietEvent } from "@/lib/api";
import { MOCK_DIET_EVENTS, MOCK_RESULTS } from "@/lib/mockData";
import { BiomarkerChart } from "@/components/BiomarkerChart";
import { DietEventManager } from "@/components/DietEventManager";
import { ManualEntryModal } from "@/components/ManualEntryModal";
import { MarkerSignals } from "@/components/MarkerSignals";
import { MarkerNote } from "@/components/MarkerNote";
import { StatusBadge } from "@/components/StatusBadge";
import { assessMarker } from "@/lib/markerSignals";
import {
  fmtDateLong,
  getCategory,
  shortLabel,
} from "@/lib/biomarkerCategories";

export default function BiomarkerDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { session, loading } = useAuth();
  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [dietEvents, setDietEvents] = useState<DietEvent[]>(MOCK_DIET_EVENTS);
  const [isLive, setIsLive] = useState(false);
  const [showManual, setShowManual] = useState(false);
  // Start true so the first render never reaches the "not found" branch while
  // auth is still settling or the real-data fetch hasn't fired yet.
  const [dataLoading, setDataLoading] = useState(true);

  const token = session?.access_token ?? null;

  const refreshResults = () => {
    if (!token) return;
    getBiomarkerResults(token)
      .then((data) => {
        if (data.length > 0) {
          setResults(data);
          setIsLive(true);
        }
      })
      .catch(() => {});
  };

  const refreshDietEvents = () => {
    if (!token) return;
    listDietEvents(token)
      .then((evts) => setDietEvents(evts))
      .catch(() => {});
  };

  useEffect(() => {
    if (loading) return; // auth not settled yet — keep the spinner
    if (!token) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDataLoading(false); // no session → show mock data
      return;
    }
    setDataLoading(true);
    Promise.all([
      getBiomarkerResults(token)
        .then((data) => {
          if (data.length > 0) {
            setResults(data);
            setIsLive(true);
          }
        })
        .catch(() => {}),
      listDietEvents(token)
        .then((evts) => setDietEvents(evts))
        .catch(() => {}),
    ]).finally(() => setDataLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
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
  const assessment = assessMarker(biomarker, series);

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
          {session && (
            <button
              onClick={() => setShowManual(true)}
              className="ml-auto text-xs font-medium border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg transition-colors"
            >
              + Add result
            </button>
          )}
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
            {latest && (
              <StatusBadge
                inRange={latest.in_range}
                attention={assessment.level === "attention"}
                showLabel
                size="md"
              />
            )}
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
          <BiomarkerChart data={entry} annotations={dietEvents} />
          {dietEvents.length > 0 && (
            <p className="mt-2 text-xs text-[var(--text-muted)]">
              Diet annotations are snapped to the nearest blood draw and show
              visual context only — a marker lining up with a change does not
              prove cause and effect.
            </p>
          )}
        </div>

        {/* Target + within-range trend signals (Sprint 7) */}
        <MarkerSignals data={entry} />

        {/* Per-marker confounder note (Sprint 8) */}
        <MarkerNote nameNo={biomarker.name_no} />

        {/* Diet annotations (correlation overlay) */}
        <DietEventManager
          token={token}
          events={dietEvents}
          onChange={refreshDietEvents}
        />

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

      {showManual && (
        <ManualEntryModal
          onClose={() => setShowManual(false)}
          token={token}
          results={results}
          initialBiomarkerId={id}
          onSuccess={() => {
            setShowManual(false);
            refreshResults();
          }}
        />
      )}
    </div>
  );
}
