"use client";

import { use, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import { getBiomarkerResults, listDietEvents } from "@/lib/api";
import type { BiomarkerWithSeries, DietEvent } from "@/lib/api";
import { MOCK_DIET_EVENTS, MOCK_RESULTS } from "@/lib/mockData";
import {
  CATEGORY_ORDER,
  categoryFromSlug,
  categorySlug,
  groupByCategory,
  shortLabel,
  type Category,
} from "@/lib/biomarkerCategories";
import { CATEGORY_DESCRIPTIONS, CATEGORY_LABELS } from "@/lib/i18n";
import { filterByDiet, type DietKey } from "@/lib/dietProfiles";
import { loadSettings } from "@/lib/dietSettings";
import { assessMarker } from "@/lib/markerSignals";
import { BiomarkerChart } from "@/components/BiomarkerChart";
import { CategoryNav } from "@/components/CategoryNav";
import { StatusBadge } from "@/components/StatusBadge";
import { useLanguage } from "@/components/LanguageProvider";

export default function CategoryGraphsPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = use(params);
  const { lang, t } = useLanguage();
  const { session, loading } = useAuth();

  const [results, setResults] = useState<BiomarkerWithSeries[]>(MOCK_RESULTS);
  const [dietEvents, setDietEvents] = useState<DietEvent[]>(MOCK_DIET_EVENTS);
  const [diet, setDiet] = useState<DietKey>("all");
  const [customMarkers, setCustomMarkers] = useState<string[]>([]);
  const [isLive, setIsLive] = useState(false);
  const [dataLoading, setDataLoading] = useState(true);

  const token = session?.access_token ?? null;
  const category = categoryFromSlug(slug);

  // Pull real data + diet annotations + the saved diet focus once auth settles.
  useEffect(() => {
    if (loading) return;
    if (!token) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setDataLoading(false); // no session → mock data
      loadSettings(null)
        .then((s) => {
          setDiet(s.diet);
          setCustomMarkers(s.custom_markers);
        })
        .catch(() => {});
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
      loadSettings(token)
        .then((s) => {
          setDiet(s.diet);
          setCustomMarkers(s.custom_markers);
        })
        .catch(() => {}),
    ]).finally(() => setDataLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session, loading]);

  // Respect the dashboard's diet focus so this view mirrors what the user sees
  // there, then bucket into categories.
  const grouped = useMemo(() => {
    const visible = filterByDiet(results, diet, customMarkers);
    return groupByCategory(visible);
  }, [results, diet, customMarkers]);

  // Only groups with at least one marker are worth navigating to.
  const navItems = useMemo(
    () =>
      CATEGORY_ORDER.filter((c) => grouped[c].length > 0).map((c) => ({
        category: c,
        count: grouped[c].length,
        outOfRange: grouped[c].filter(
          (i) => i.series.at(-1)?.in_range === false
        ).length,
      })),
    [grouped]
  );

  if (loading || dataLoading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-[var(--color-accent)] rounded-full animate-spin" />
      </div>
    );
  }

  // Unknown slug → friendly fallback rather than a hard 404.
  if (!category) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="text-center space-y-3">
          <p className="text-[var(--text-secondary)]">Unknown category.</p>
          <Link href="/" className="text-blue-400 hover:text-blue-300 text-sm">
            ← Dashboard
          </Link>
        </div>
      </div>
    );
  }

  const items = grouped[category];

  // Wrap-around prev/next so the user can sweep through every populated group
  // without returning to the dashboard.
  const order = navItems.map((n) => n.category);
  const idx = order.indexOf(category);
  const prev: Category | null =
    order.length > 1 && idx >= 0
      ? order[(idx - 1 + order.length) % order.length]
      : null;
  const next: Category | null =
    order.length > 1 && idx >= 0
      ? order[(idx + 1) % order.length]
      : null;

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* Sticky header: back link + category switcher rail */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 py-2.5 space-y-2.5">
          <div className="flex items-center gap-3">
            <Link
              href="/"
              className="shrink-0 text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-sm"
            >
              ← Dashboard
            </Link>
          </div>
          {navItems.length > 0 && (
            <CategoryNav items={navItems} active={category} />
          )}
        </div>
      </header>

      <main className="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Mock-data banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              {t("banner.mock")}{" "}
              <Link href="/login" className="text-blue-400 hover:text-blue-300">
                {t("nav.signIn")}
              </Link>{" "}
              {t("banner.signInPrompt")}
            </p>
          </div>
        )}

        {/* Group header */}
        <div className="space-y-1">
          <p className="text-xs text-[var(--text-muted)]">
            {isLive ? t("hero.yourData") : t("hero.sampleData")} ·{" "}
            {t("category.subtitle")}
          </p>
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
            {CATEGORY_LABELS[lang][category]}
          </h1>
          <p className="text-sm text-[var(--text-secondary)] max-w-2xl">
            {CATEGORY_DESCRIPTIONS[lang][category]}
          </p>
        </div>

        {/* Graphs */}
        {items.length === 0 ? (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-10 text-center">
            <p className="text-sm text-[var(--text-secondary)]">
              {t("category.empty")}
            </p>
            <Link
              href="/"
              className="mt-3 inline-block text-xs font-medium text-[var(--color-accent)] hover:underline"
            >
              ← Dashboard
            </Link>
          </div>
        ) : (
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
            {items.map((item) => (
              <CategoryChart
                key={item.biomarker.id}
                data={item}
                annotations={dietEvents}
                openLabel={t("category.openDetail")}
              />
            ))}
          </div>
        )}

        {/* Prev / next category navigation */}
        {(prev || next) && (
          <div className="flex items-center justify-between gap-3 border-t border-[var(--border-subtle)] pt-5">
            {prev ? (
              <Link
                href={`/categories/${categorySlug(prev)}`}
                scroll
                className="group flex items-center gap-2 rounded-lg border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-2.5 text-sm transition-colors hover:bg-[var(--bg-elevated)]"
              >
                <span className="text-[var(--text-muted)] group-hover:text-[var(--text-primary)]">
                  ←
                </span>
                <span className="text-left">
                  <span className="block text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                    {t("category.prev")}
                  </span>
                  <span className="block text-[var(--text-secondary)] group-hover:text-[var(--text-primary)]">
                    {CATEGORY_LABELS[lang][prev]}
                  </span>
                </span>
              </Link>
            ) : (
              <span />
            )}
            {next ? (
              <Link
                href={`/categories/${categorySlug(next)}`}
                scroll
                className="group flex items-center gap-2 rounded-lg border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-2.5 text-sm transition-colors hover:bg-[var(--bg-elevated)]"
              >
                <span className="text-right">
                  <span className="block text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                    {t("category.next")}
                  </span>
                  <span className="block text-[var(--text-secondary)] group-hover:text-[var(--text-primary)]">
                    {CATEGORY_LABELS[lang][next]}
                  </span>
                </span>
                <span className="text-[var(--text-muted)] group-hover:text-[var(--text-primary)]">
                  →
                </span>
              </Link>
            ) : (
              <span />
            )}
          </div>
        )}
      </main>
    </div>
  );
}

/** One biomarker's full trend chart with a compact header + detail link. */
function CategoryChart({
  data,
  annotations,
  openLabel,
}: {
  data: BiomarkerWithSeries;
  annotations: DietEvent[];
  openLabel: string;
}) {
  const { biomarker, series } = data;
  const latest = series.at(-1);
  const assessment = assessMarker(biomarker, series);

  return (
    <section className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div className="min-w-0">
          <Link
            href={`/biomarkers/${biomarker.id}`}
            title={openLabel}
            className="text-sm font-medium text-[var(--text-primary)] leading-tight hover:text-[var(--color-accent)] transition-colors line-clamp-2"
          >
            {shortLabel(biomarker.name_no)}
          </Link>
          <div className="mt-1 flex items-baseline gap-1.5">
            <span className="text-xl font-mono font-semibold tabular-nums text-[var(--text-primary)]">
              {latest?.value ?? "—"}
            </span>
            {biomarker.unit && (
              <span className="text-xs text-[var(--text-muted)] font-mono">
                {biomarker.unit}
              </span>
            )}
          </div>
        </div>
        <StatusBadge
          inRange={latest?.in_range ?? null}
          attention={assessment.level === "attention"}
          showLabel
          size="sm"
        />
      </div>
      <BiomarkerChart data={data} annotations={annotations} />
    </section>
  );
}
