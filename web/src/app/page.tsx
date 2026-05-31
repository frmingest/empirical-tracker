"use client";

import { useState } from "react";
import Link from "next/link";
import { CategorySection } from "@/components/CategorySection";
import { ImportModal } from "@/components/ImportModal";
import { MOCK_RESULTS, getMockStats } from "@/lib/mockData";
import { groupByCategory, CATEGORY_ORDER, fmtDateLong } from "@/lib/biomarkerCategories";

export default function DashboardPage() {
  const [showImport, setShowImport] = useState(false);

  // TODO: Replace mock data with await getBiomarkerResults(token) when auth is wired
  const results = MOCK_RESULTS;
  const stats = getMockStats();
  const grouped = groupByCategory(results);

  const outOfRangeTotal = results.filter((r) => r.series.at(-1)?.in_range === false).length;

  return (
    <div className="min-h-screen bg-[#09090b]">
      {/* ── Top nav ──────────────────────────────────────────────────────────── */}
      <header className="sticky top-0 z-40 border-b border-zinc-900 bg-[#09090b]/90 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
          <span className="text-base font-semibold tracking-tight bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </span>
          <nav className="flex items-center gap-1">
            <Link
              href="/import"
              className="text-xs text-zinc-500 hover:text-zinc-300 px-3 py-1.5 rounded transition-colors"
            >
              Import
            </Link>
            <button
              onClick={() => setShowImport(true)}
              className="flex items-center gap-1.5 text-xs font-medium bg-blue-600 hover:bg-blue-500 text-white px-3 py-1.5 rounded-lg transition-colors"
            >
              <span className="text-base leading-none">↑</span>
              Upload
            </button>
          </nav>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 py-8 space-y-10">
        {/* ── Hero ─────────────────────────────────────────────────────────── */}
        <div className="space-y-1">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight bg-gradient-to-r from-blue-400 via-blue-300 to-emerald-400 bg-clip-text text-transparent">
            Blood biomarkers
          </h1>
          <p className="text-zinc-500 text-sm">
            Personal health tracking for elimination diets
          </p>
        </div>

        {/* ── Stats bar ────────────────────────────────────────────────────── */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
          <StatCard
            label="Biomarkers"
            value={stats.biomarkerCount.toString()}
          />
          <StatCard
            label="Test panels"
            value={stats.panelCount.toString()}
          />
          <StatCard
            label="Last tested"
            value={
              stats.lastTestedAt ? fmtDateLong(stats.lastTestedAt) : "—"
            }
            mono={false}
          />
          <StatCard
            label="Out of range"
            value={outOfRangeTotal.toString()}
            accent={outOfRangeTotal > 0 ? "rose" : "emerald"}
          />
        </div>

        {/* ── Biomarker categories ─────────────────────────────────────────── */}
        <div className="space-y-10">
          {CATEGORY_ORDER.map((cat) => (
            <CategorySection
              key={cat}
              category={cat}
              items={grouped[cat]}
            />
          ))}
        </div>

        {/* ── Footer ───────────────────────────────────────────────────────── */}
        <footer className="border-t border-zinc-900 pt-6 pb-4">
          <p className="text-xs text-zinc-700 text-center font-mono">
            Mock data — connect your account to see real results
          </p>
        </footer>
      </main>

      {showImport && <ImportModal onClose={() => setShowImport(false)} />}
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
      ? "text-rose-400"
      : accent === "emerald"
        ? "text-emerald-400"
        : "text-zinc-100";

  return (
    <div className="rounded-xl border border-zinc-800 bg-zinc-900 px-4 py-4">
      <p className="text-[10px] uppercase tracking-widest text-zinc-600 mb-1.5">
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
