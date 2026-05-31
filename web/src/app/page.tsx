"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import { getBiomarkerResults } from "@/lib/api";
import type { BiomarkerWithSeries } from "@/lib/api";
import { MOCK_RESULTS } from "@/lib/mockData";
import {
  fmtDateLong,
  groupByCategory,
  CATEGORY_ORDER,
} from "@/lib/biomarkerCategories";
import {
  filterByDiet,
  visibleMarkerNames,
  type DietKey,
} from "@/lib/dietProfiles";
import { loadSettings, persistSettings } from "@/lib/dietSettings";
import { CategorySection } from "@/components/CategorySection";
import { DietFilter } from "@/components/DietFilter";
import { CustomMarkerModal } from "@/components/CustomMarkerModal";
import { ImportModal } from "@/components/ImportModal";
import { ManualEntryModal } from "@/components/ManualEntryModal";
import { ThemeToggle } from "@/components/ThemeToggle";

function derivedStats(results: BiomarkerWithSeries[]) {
  const allDates = new Set(results.flatMap((r) => r.series.map((p) => p.tested_at)));
  const sorted = [...allDates].sort();
  return {
    biomarkerCount: results.length,
    panelCount: allDates.size,
    lastTestedAt: sorted.at(-1) ?? null,
  };
}

export default function DashboardPage() {
  const { session, loading, signOut } = useAuth();
  const [showImport, setShowImport] = useState(false);
  const [showManual, setShowManual] = useState(false);
  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [isLive, setIsLive] = useState(false);
  const [dataLoading, setDataLoading] = useState(true);

  // Diet focus preference (DB-backed when signed in, localStorage otherwise).
  const [diet, setDiet] = useState<DietKey>("all");
  const [customMarkers, setCustomMarkers] = useState<string[]>([]);
  const [showCustom, setShowCustom] = useState(false);

  const token = session?.access_token ?? null;

  // Once auth settles, swap mock data for real data when a session exists.
  useEffect(() => {
    if (loading) return; // auth not settled yet
    if (!session?.access_token) {
      setDataLoading(false); // no session → stick with mock data
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
      .catch(() => {}) // keep showing mock data on error
      .finally(() => setDataLoading(false));
  }, [session, loading]);

  // Load the saved diet focus once auth settles.
  useEffect(() => {
    if (loading) return;
    loadSettings(session?.access_token ?? null)
      .then((s) => {
        setDiet(s.diet);
        setCustomMarkers(s.custom_markers);
      })
      .catch(() => {});
  }, [session, loading]);

  // Persist + apply a new diet selection.
  const applySelection = (nextDiet: DietKey, nextCustom = customMarkers) => {
    setDiet(nextDiet);
    setCustomMarkers(nextCustom);
    persistSettings(token, { diet: nextDiet, custom_markers: nextCustom });
  };

  const handleSelectDiet = (nextDiet: DietKey) => {
    if (nextDiet === "custom") {
      setShowCustom(true); // configure before committing to custom
      return;
    }
    applySelection(nextDiet);
  };

  const visible = filterByDiet(results, diet, customMarkers);

  const stats = derivedStats(visible);
  const grouped = groupByCategory(visible);
  const outOfRangeTotal = visible.filter(
    (r) => r.series.at(-1)?.in_range === false
  ).length;

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* ── Top nav ─────────────────────────────────────────────────────────── */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
          <span className="text-base font-semibold tracking-tight bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </span>
          <nav className="flex items-center gap-1">
            <ThemeToggle />
            <Link
              href="/panels"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
            >
              Panels
            </Link>
            {session ? (
              <>
                <span className="text-xs text-[var(--text-muted)] px-2 hidden sm:block truncate max-w-[160px]">
                  {session.user.email}
                </span>
                <button
                  onClick={() => setShowManual(true)}
                  className="text-xs font-medium border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg transition-colors"
                >
                  Add result
                </button>
                <button
                  onClick={() => setShowImport(true)}
                  className="flex items-center gap-1.5 text-xs font-medium bg-blue-600 hover:bg-blue-500 text-white px-3 py-1.5 rounded-lg transition-colors"
                >
                  <span className="text-base leading-none">↑</span>
                  Import
                </button>
                <button
                  onClick={signOut}
                  className="text-xs text-[var(--text-muted)] hover:text-[var(--text-secondary)] px-2 py-1.5 rounded transition-colors"
                >
                  Sign out
                </button>
              </>
            ) : (
              <Link
                href="/login"
                className="text-xs font-medium bg-blue-600 hover:bg-blue-500 text-white px-3 py-1.5 rounded-lg transition-colors ml-1"
              >
                Sign in
              </Link>
            )}
          </nav>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-10">
        {/* ── Not signed in banner ─────────────────────────────────────────── */}
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

        {/* ── Hero ─────────────────────────────────────────────────────────── */}
        <div className="space-y-1">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight bg-gradient-to-r from-blue-400 via-blue-300 to-emerald-400 bg-clip-text text-transparent">
            Blood biomarkers
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? "Your data" : "Sample data"} · personal health tracking
            for elimination diets
          </p>
        </div>

        {/* ── Diet focus filter ────────────────────────────────────────────── */}
        <DietFilter
          diet={diet}
          onSelect={handleSelectDiet}
          onCustomize={() => setShowCustom(true)}
          visibleCount={visible.length}
          totalCount={results.length}
        />

        {/* ── Stats bar ────────────────────────────────────────────────────── */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <StatCard label="Biomarkers" value={stats.biomarkerCount.toString()} />
          <StatCard label="Test panels" value={stats.panelCount.toString()} />
          <StatCard
            label="Last tested"
            value={stats.lastTestedAt ? fmtDateLong(stats.lastTestedAt) : "—"}
            mono={false}
          />
          <StatCard
            label="Out of range"
            value={
              dataLoading ? "…" : outOfRangeTotal.toString()
            }
            accent={outOfRangeTotal > 0 ? "rose" : "emerald"}
          />
        </div>

        {/* ── Biomarker categories ─────────────────────────────────────────── */}
        {visible.length === 0 ? (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-10 text-center">
            <p className="text-sm text-[var(--text-secondary)]">
              No markers selected for this view.
            </p>
            <button
              onClick={() => setShowCustom(true)}
              className="mt-3 text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              Choose markers
            </button>
          </div>
        ) : (
          <div className="space-y-10">
            {CATEGORY_ORDER.map((cat) => (
              <CategorySection key={cat} category={cat} items={grouped[cat]} />
            ))}
          </div>
        )}

        <footer className="border-t border-[var(--border-subtle)] pt-6 pb-4">
          <p className="text-xs text-[var(--text-muted)] text-center font-mono">
            {isLive ? "Live data from Supabase" : "Mock data — sign in to load your results"}
          </p>
        </footer>
      </main>

      {showImport && (
        <ImportModal
          onClose={() => setShowImport(false)}
          token={session?.access_token ?? null}
          onSuccess={() => {
            // Refresh real data after a successful import
            if (session?.access_token) {
              getBiomarkerResults(session.access_token)
                .then((data) => {
                  if (data.length > 0) { setResults(data); setIsLive(true); }
                })
                .catch(() => {});
            }
          }}
        />
      )}

      {showCustom && (
        <CustomMarkerModal
          results={results}
          initialSelected={visibleMarkerNames(results, diet, customMarkers)}
          onClose={() => setShowCustom(false)}
          onSave={(selected) => {
            applySelection("custom", selected);
            setShowCustom(false);
          }}
        />
      )}

      {showManual && (
        <ManualEntryModal
          onClose={() => setShowManual(false)}
          token={session?.access_token ?? null}
          results={results}
          onSuccess={() => {
            setShowManual(false);
            if (session?.access_token) {
              getBiomarkerResults(session.access_token)
                .then((data) => {
                  if (data.length > 0) { setResults(data); setIsLive(true); }
                })
                .catch(() => {});
            }
          }}
        />
      )}
    </div>
  );
}

function StatCard({
  label,
  value,
  mono = true,
  accent,
}: {
  label: string;
  value: string;
  mono?: boolean;
  accent?: "rose" | "emerald";
}) {
  const valueColor =
    accent === "rose"
      ? "text-rose-500"
      : accent === "emerald"
        ? "text-emerald-600"
        : "text-[var(--text-primary)]";

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
      <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
        {label}
      </p>
      <p
        className={`text-xl font-semibold leading-tight ${valueColor} ${
          mono ? "font-mono tabular-nums" : ""
        }`}
      >
        {value}
      </p>
    </div>
  );
}
