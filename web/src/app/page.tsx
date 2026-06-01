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
import { assessMarker } from "@/lib/markerSignals";
import { CategorySection } from "@/components/CategorySection";
import { DietFilter } from "@/components/DietFilter";
import { CustomMarkerModal } from "@/components/CustomMarkerModal";
import { ImportModal } from "@/components/ImportModal";
import { ThemeToggle } from "@/components/ThemeToggle";
import { LanguageToggle } from "@/components/LanguageToggle";
import { useLanguage } from "@/components/LanguageProvider";

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
  const { t } = useLanguage();
  const { session, loading, signOut } = useAuth();
  const [showImport, setShowImport] = useState(false);
  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [isLive, setIsLive] = useState(false);
  const [dataLoading, setDataLoading] = useState(true);

  // Diet focus preference (DB-backed when signed in, localStorage otherwise).
  const [diet, setDiet] = useState<DietKey>("all");
  const [customMarkers, setCustomMarkers] = useState<string[]>([]);
  const [showCustom, setShowCustom] = useState(false);
  // When on, the grid is narrowed to markers that are out of range or "Watch".
  const [flaggedOnly, setFlaggedOnly] = useState(false);

  const token = session?.access_token ?? null;

  // Once auth settles, swap mock data for real data when a session exists.
  useEffect(() => {
    if (loading) return; // auth not settled yet
    if (!session?.access_token) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
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
  const outOfRangeTotal = visible.filter(
    (r) => r.series.at(-1)?.in_range === false
  ).length;
  // Sprint 7 — in-range markers carrying a clinical-target or trend signal.
  const attentionTotal = visible.filter(
    (r) => assessMarker(r.biomarker, r.series).level === "attention"
  ).length;

  // A marker is "flagged" if it's out of range or carries a Watch signal.
  const flaggedCount = outOfRangeTotal + attentionTotal;
  const isFlagged = (r: BiomarkerWithSeries) => {
    const level = assessMarker(r.biomarker, r.series).level;
    return level === "out_of_range" || level === "attention";
  };
  const displayed = flaggedOnly ? visible.filter(isFlagged) : visible;
  const grouped = groupByCategory(displayed);

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-[var(--color-accent)] rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* ── Top nav ─────────────────────────────────────────────────────────── */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 h-14 flex items-center justify-between">
          <span className="shrink-0 mr-2 text-base font-semibold tracking-tight bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </span>
          <nav className="flex items-center gap-1 min-w-0 flex-1 justify-end overflow-x-auto">
            <LanguageToggle />
            <ThemeToggle />
            <Link
              href="/panels"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
            >
              {t("nav.panels")}
            </Link>
            <Link
              href="/food-diary"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
            >
              {t("nav.foodDiary")}
            </Link>
            <Link
              href="/meal-plans"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
            >
              {t("nav.mealPlans")}
            </Link>
            <Link
              href="/body-metrics"
              className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
            >
              {t("nav.bodyMetrics")}
            </Link>
            {session ? (
              <>
                <Link
                  href="/account"
                  className="text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-2 py-1.5 rounded transition-colors"
                >
                  {t("nav.account")}
                </Link>
                <span className="text-xs text-[var(--text-muted)] px-2 hidden sm:block truncate max-w-[160px]">
                  {session.user.email}
                </span>
                <button
                  onClick={() => setShowImport(true)}
                  className="shrink-0 flex items-center gap-1.5 text-xs font-medium bg-[var(--btn-accent)] hover:bg-[var(--btn-accent-hover)] text-[var(--btn-accent-text)] px-3 py-1.5 rounded-lg transition-colors"
                >
                  <span className="text-base leading-none">↑</span>
                  {t("nav.import")}
                </button>
                <button
                  onClick={signOut}
                  className="text-xs text-[var(--text-muted)] hover:text-[var(--text-secondary)] px-2 py-1.5 rounded transition-colors"
                >
                  {t("nav.signOut")}
                </button>
              </>
            ) : (
              <Link
                href="/login"
                className="shrink-0 text-xs font-medium bg-[var(--btn-accent)] hover:bg-[var(--btn-accent-hover)] text-[var(--btn-accent-text)] px-3 py-1.5 rounded-lg transition-colors ml-1"
              >
                {t("nav.signIn")}
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
              {t("banner.mock")}{" "}
              <Link href="/login" className="text-blue-400 hover:text-blue-300">
                {t("nav.signIn")}
              </Link>{" "}
              {t("banner.signInPrompt")}
            </p>
          </div>
        )}

        {/* ── Hero ─────────────────────────────────────────────────────────── */}
        <div className="space-y-1">
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight bg-gradient-to-r from-blue-400 via-blue-300 to-emerald-400 bg-clip-text text-transparent">
            {t("hero.title")}
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? t("hero.yourData") : t("hero.sampleData")} ·{" "}
            {t("hero.subtitle")}
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
          <StatCard label={t("stats.biomarkers")} value={stats.biomarkerCount.toString()} />
          <StatCard label={t("stats.panels")} value={stats.panelCount.toString()} />
          <StatCard
            label={t("stats.lastTested")}
            value={stats.lastTestedAt ? fmtDateLong(stats.lastTestedAt) : "—"}
            mono={false}
          />
          <StatCard
            label={t("stats.outOfRange")}
            value={
              dataLoading ? "…" : outOfRangeTotal.toString()
            }
            accent={outOfRangeTotal > 0 ? "rose" : "emerald"}
            onClick={
              flaggedCount > 0 ? () => setFlaggedOnly((v) => !v) : undefined
            }
            active={flaggedOnly}
            title={flaggedCount > 0 ? t("filter.viewFlagged") : undefined}
          />
        </div>

        {/* Sprint 7 — within-range markers worth a second look. Acts as a
            shortcut into the flagged-only view. */}
        {!dataLoading && attentionTotal > 0 && (
          <button
            type="button"
            onClick={() => setFlaggedOnly(true)}
            aria-pressed={flaggedOnly}
            className="w-full text-left rounded-xl border border-[var(--color-warning)]/30 bg-[var(--color-warning)]/5 px-4 py-3 transition-colors hover:bg-[var(--color-warning)]/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)]"
          >
            <p className="text-sm text-[var(--text-secondary)]">
              {t("signals.watchNote").replace(
                "{n}",
                (attentionTotal === 1
                  ? t("signals.watchNote.one")
                  : t("signals.watchNote.many").replace("{n}", attentionTotal.toString())
                )
              )}
            </p>
          </button>
        )}

        {/* Flagged-only filter status bar */}
        {!dataLoading && flaggedOnly && (
          <div className="flex items-center justify-between gap-3 rounded-xl border border-[var(--color-accent)]/30 bg-[var(--color-accent)]/5 px-4 py-2.5">
            <span className="text-xs font-medium text-[var(--text-secondary)]">
              {t("filter.flaggedOnly")} · {displayed.length} / {visible.length}
            </span>
            <button
              type="button"
              onClick={() => setFlaggedOnly(false)}
              className="text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              {t("filter.showAll")}
            </button>
          </div>
        )}

        {/* ── Biomarker categories ─────────────────────────────────────────── */}
        {visible.length === 0 ? (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-10 text-center">
            <p className="text-sm text-[var(--text-secondary)]">
              {t("empty.none")}
            </p>
            <button
              onClick={() => setShowCustom(true)}
              className="mt-3 text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              {t("empty.choose")}
            </button>
          </div>
        ) : flaggedOnly && displayed.length === 0 ? (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-10 text-center">
            <p className="text-sm text-[var(--text-secondary)]">
              {t("filter.allClear")}
            </p>
            <button
              onClick={() => setFlaggedOnly(false)}
              className="mt-3 text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              {t("filter.showAll")}
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
            {isLive ? t("footer.live") : t("footer.mock")}
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
    </div>
  );
}

function StatCard({
  label,
  value,
  mono = true,
  accent,
  onClick,
  active = false,
  title,
}: {
  label: string;
  value: string;
  mono?: boolean;
  accent?: "rose" | "emerald";
  /** When set, the card becomes a toggle button. */
  onClick?: () => void;
  active?: boolean;
  title?: string;
}) {
  const valueColor =
    accent === "rose"
      ? "text-[var(--color-out-range)]"
      : accent === "emerald"
        ? "text-[var(--color-in-range)]"
        : "text-[var(--text-primary)]";

  const body = (
    <>
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
    </>
  );

  const base =
    "rounded-xl border bg-[var(--bg-card)] px-4 py-4 shadow-sm text-left";

  if (onClick) {
    return (
      <button
        type="button"
        onClick={onClick}
        aria-pressed={active}
        title={title}
        className={`${base} transition-colors hover:bg-[var(--bg-elevated)] focus:outline-none focus-visible:ring-2 focus-visible:ring-[var(--color-accent)] ${
          active
            ? "border-[var(--color-accent)] ring-1 ring-[var(--color-accent)]"
            : "border-[var(--border-card)]"
        }`}
      >
        {body}
      </button>
    );
  }

  return <div className={`${base} border-[var(--border-card)]`}>{body}</div>;
}
