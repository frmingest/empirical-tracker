"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import {
  createFoodEntry,
  deleteFoodEntry,
  listFoodEntries,
  type FoodEntry,
  type FoodEntryInput,
  type Meal,
} from "@/lib/api";
import { MOCK_FOOD_ENTRIES } from "@/lib/mockData";
import { FoodSearch } from "@/components/FoodSearch";
import { fmtDateLong } from "@/lib/biomarkerCategories";

const MEAL_ORDER: Meal[] = ["breakfast", "lunch", "dinner", "snack", "other"];

const MEAL_LABEL: Record<Meal, string> = {
  breakfast: "Breakfast",
  lunch: "Lunch",
  dinner: "Dinner",
  snack: "Snack",
  other: "Other",
};

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

function shiftDate(iso: string, days: number): string {
  const d = new Date(iso + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

function sum(entries: FoodEntry[], key: keyof FoodEntry): number {
  return entries.reduce((acc, e) => acc + (typeof e[key] === "number" ? (e[key] as number) : 0), 0);
}

function round(n: number): number {
  return Math.round(n * 10) / 10;
}

export default function FoodDiaryPage() {
  const { session, loading } = useAuth();
  const token = session?.access_token ?? null;
  const [day, setDay] = useState(todayIso());
  const [entries, setEntries] = useState<FoodEntry[]>(MOCK_FOOD_ENTRIES);
  const [isLive, setIsLive] = useState(false);

  const refresh = (d = day) => {
    if (!token) return;
    listFoodEntries(token, d)
      .then((rows) => {
        setEntries(rows);
        setIsLive(true);
      })
      .catch(() => {});
  };

  useEffect(() => {
    if (loading) return;
    if (!token) return; // signed out → keep demo entries
    refresh(day);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session, loading, day]);

  const handleAdd = async (input: FoodEntryInput) => {
    if (!token) return;
    try {
      await createFoodEntry(token, input);
      refresh();
    } catch {
      // surfaced inline by FoodSearch on its own errors; ignore here
    }
  };

  const handleDelete = async (id: string) => {
    if (!token) {
      setEntries((prev) => prev.filter((e) => e.id !== id)); // demo: local only
      return;
    }
    try {
      await deleteFoodEntry(token, id);
      refresh();
    } catch {
      // non-critical
    }
  };

  // For the signed-out demo, only show the entries logged "today".
  const dayEntries = isLive ? entries : entries.filter((e) => e.logged_on === day);

  const totals = {
    kcal: round(sum(dayEntries, "energy_kcal")),
    carbs: round(sum(dayEntries, "carbs_g")),
    protein: round(sum(dayEntries, "protein_g")),
    fat: round(sum(dayEntries, "fat_g")),
    satFat: round(sum(dayEntries, "saturated_fat_g")),
    sodium: round(sum(dayEntries, "sodium_mg")),
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-[var(--color-accent)] rounded-full animate-spin" />
      </div>
    );
  }

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
            Food diary
          </span>
          <Link
            href="/meal-plans"
            className="ml-auto text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
          >
            Meal plans →
          </Link>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Title */}
        <div className="space-y-1">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
            Food diary
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? "Your data" : "Sample data"} · log what you eat to correlate
            it with your biomarkers
          </p>
        </div>

        {/* Not signed in banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              Showing sample entries.{" "}
              <Link href="/login" className="text-[var(--color-accent)] hover:underline">
                Sign in
              </Link>{" "}
              to keep your own food diary.
            </p>
          </div>
        )}

        {/* Date navigator */}
        <div className="flex items-center justify-between gap-3">
          <button
            onClick={() => setDay((d) => shiftDate(d, -1))}
            className="text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg border border-[var(--border-card)] transition-colors"
          >
            ← Prev
          </button>
          <div className="flex items-center gap-2">
            <input
              type="date"
              value={day}
              onChange={(e) => setDay(e.target.value || todayIso())}
              className="rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-1.5 focus:outline-none focus:border-blue-500"
            />
            <button
              onClick={() => setDay(todayIso())}
              className="text-xs text-[var(--text-muted)] hover:text-[var(--text-secondary)] px-2 py-1.5 transition-colors"
            >
              Today
            </button>
          </div>
          <button
            onClick={() => setDay((d) => shiftDate(d, 1))}
            className="text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg border border-[var(--border-card)] transition-colors"
          >
            Next →
          </button>
        </div>

        {/* Daily totals */}
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
          <Totals label="Energy" value={`${totals.kcal}`} unit="kcal" />
          <Totals label="Carbs" value={`${totals.carbs}`} unit="g" />
          <Totals label="Protein" value={`${totals.protein}`} unit="g" />
          <Totals label="Fat" value={`${totals.fat}`} unit="g" />
          <Totals label="Sat. fat" value={`${totals.satFat}`} unit="g" />
          <Totals label="Sodium" value={`${totals.sodium}`} unit="mg" />
        </div>

        {/* Add food */}
        <FoodSearch token={token} loggedOn={day} onAdd={handleAdd} />

        {/* Entries grouped by meal */}
        {dayEntries.length === 0 ? (
          <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-6 py-10 text-center">
            <p className="text-sm text-[var(--text-secondary)]">
              Nothing logged for {fmtDateLong(day)} yet.
            </p>
          </div>
        ) : (
          <div className="space-y-5">
            {MEAL_ORDER.map((m) => {
              const meals = dayEntries.filter((e) => e.meal === m);
              if (meals.length === 0) return null;
              return (
                <div key={m}>
                  <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)] mb-2">
                    {MEAL_LABEL[m]}
                  </h2>
                  <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] overflow-hidden shadow-sm divide-y divide-[var(--border-subtle)]">
                    {meals.map((e) => (
                      <div key={e.id} className="flex items-center gap-3 px-4 py-3">
                        <div className="min-w-0 flex-1">
                          <p className="text-sm text-[var(--text-primary)] truncate">
                            {e.food_name}
                            {e.brand && (
                              <span className="text-[var(--text-muted)]"> · {e.brand}</span>
                            )}
                          </p>
                          <p className="text-[11px] text-[var(--text-muted)] font-mono">
                            {e.quantity_g != null ? `${e.quantity_g} g · ` : ""}
                            {e.energy_kcal ?? "—"} kcal · C{e.carbs_g ?? "—"} /
                            P{e.protein_g ?? "—"} / F{e.fat_g ?? "—"}
                            {" "}(sat {e.saturated_fat_g ?? "—"}) · Na{" "}
                            {e.sodium_mg ?? "—"} mg
                          </p>
                        </div>
                        <button
                          onClick={() => handleDelete(e.id)}
                          className="shrink-0 text-[var(--text-muted)] hover:text-[var(--color-out-range)] transition-colors text-lg leading-none"
                          aria-label={`Delete ${e.food_name}`}
                        >
                          ×
                        </button>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        )}

        <footer className="border-t border-[var(--border-subtle)] pt-6 pb-4">
          <p className="text-xs text-[var(--text-muted)] text-center">
            Nutrition data from{" "}
            <a
              href="https://world.openfoodfacts.org"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[var(--color-accent)] hover:underline"
            >
              Open Food Facts
            </a>{" "}
            (ODbL). Values are as-published and may be incomplete.
          </p>
        </footer>
      </main>
    </div>
  );
}

function Totals({ label, value, unit }: { label: string; value: string; unit: string }) {
  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-4 py-4 shadow-sm">
      <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-1.5">
        {label}
      </p>
      <p className="text-xl font-mono font-semibold text-[var(--text-primary)] tabular-nums">
        {value}
        <span className="text-xs text-[var(--text-muted)] ml-1">{unit}</span>
      </p>
    </div>
  );
}
