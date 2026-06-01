"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import {
  createFoodEntry,
  createMealPlan,
  createPlannedMeal,
  deleteMealPlan,
  deletePlannedMeal,
  listMealPlans,
  listPlannedMeals,
  setPlannedMealDone,
  type Meal,
  type MealPlan,
  type PlannedMeal,
  type PlannedMealInput,
} from "@/lib/api";
import { MOCK_MEAL_PLANS, MOCK_PLANNED_MEALS } from "@/lib/mockData";
import { PlannedMealPicker } from "@/components/PlannedMealPicker";

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

/** Monday (ISO) of the week containing `iso`. */
function mondayOf(iso: string): string {
  const d = new Date(iso + "T12:00:00Z");
  const dow = (d.getUTCDay() + 6) % 7; // 0 = Monday
  d.setUTCDate(d.getUTCDate() - dow);
  return d.toISOString().slice(0, 10);
}

function shiftDate(iso: string, days: number): string {
  const d = new Date(iso + "T12:00:00Z");
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** The seven ISO dates of the week starting at `monday`. */
function weekDates(monday: string): string[] {
  return Array.from({ length: 7 }, (_, i) => shiftDate(monday, i));
}

function weekdayLabel(iso: string): { day: string; date: string } {
  const d = new Date(iso + "T12:00:00Z");
  return {
    day: d.toLocaleDateString("en-US", { weekday: "short", timeZone: "UTC" }),
    date: d.toLocaleDateString("en-US", { day: "numeric", month: "short", timeZone: "UTC" }),
  };
}

function round(n: number): number {
  return Math.round(n * 10) / 10;
}

export default function MealPlansPage() {
  const { session, loading } = useAuth();
  const token = session?.access_token ?? null;

  const [weekStart, setWeekStart] = useState(() => mondayOf(todayIso()));
  const [meals, setMeals] = useState<PlannedMeal[]>(MOCK_PLANNED_MEALS);
  const [plans, setPlans] = useState<MealPlan[]>(MOCK_MEAL_PLANS);
  const [isLive, setIsLive] = useState(false);
  const [planFilter, setPlanFilter] = useState<string | "all">("all");
  // Which day currently has its add-meal picker open (ISO date), or null.
  const [pickerDay, setPickerDay] = useState<string | null>(null);
  // New-plan form state.
  const [newPlanName, setNewPlanName] = useState("");
  const [newPlanDesc, setNewPlanDesc] = useState("");

  const days = weekDates(weekStart);
  const weekEnd = days[6];

  const refresh = (start = weekStart) => {
    if (!token) return;
    const end = shiftDate(start, 6);
    Promise.all([listPlannedMeals(token, start, end), listMealPlans(token)])
      .then(([m, p]) => {
        setMeals(m);
        setPlans(p);
        setIsLive(true);
      })
      .catch(() => {});
  };

  useEffect(() => {
    if (loading) return;
    if (!token) return; // signed out → keep demo data
    refresh(weekStart);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [session, loading, weekStart]);

  const visibleMeals = meals.filter(
    (m) => planFilter === "all" || m.plan_id === planFilter
  );

  const planName = (id: string | null): string | null =>
    id ? plans.find((p) => p.id === id)?.name ?? null : null;

  // ── Planned-meal actions ──────────────────────────────────────────────────────

  const handleAdd = async (input: PlannedMealInput) => {
    if (!token) {
      // Demo: append locally so the calendar still feels alive when signed out.
      setMeals((prev) => [
        ...prev,
        { id: `local-${Date.now()}`, done: false, ...input } as PlannedMeal,
      ]);
      return;
    }
    try {
      await createPlannedMeal(token, input);
      refresh();
    } catch {
      // non-critical
    }
  };

  const handleToggleDone = async (m: PlannedMeal) => {
    if (!token) {
      setMeals((prev) =>
        prev.map((x) => (x.id === m.id ? { ...x, done: !x.done } : x))
      );
      return;
    }
    try {
      await setPlannedMealDone(token, m.id, !m.done);
      refresh();
    } catch {
      // non-critical
    }
  };

  const handleDeleteMeal = async (id: string) => {
    if (!token) {
      setMeals((prev) => prev.filter((m) => m.id !== id));
      return;
    }
    try {
      await deletePlannedMeal(token, id);
      refresh();
    } catch {
      // non-critical
    }
  };

  // Copy a planned meal into the food diary (Sprint 4) for the day it's scheduled.
  const handleLogToDiary = async (m: PlannedMeal) => {
    if (!token) return;
    try {
      await createFoodEntry(token, {
        logged_on: m.scheduled_on,
        meal: m.meal,
        food_name: m.food_name,
        brand: m.brand,
        barcode: m.barcode,
        quantity_g: m.quantity_g,
        energy_kcal: m.energy_kcal,
        carbs_g: m.carbs_g,
        protein_g: m.protein_g,
        fat_g: m.fat_g,
        sodium_mg: m.sodium_mg,
        saturated_fat_g: m.saturated_fat_g,
      });
      if (!m.done) await setPlannedMealDone(token, m.id, true);
      refresh();
    } catch {
      // non-critical
    }
  };

  // ── Plan actions ──────────────────────────────────────────────────────────────

  const handleCreatePlan = async () => {
    const name = newPlanName.trim();
    if (!name) return;
    const input = { name, description: newPlanDesc.trim() || null };
    if (!token) {
      setPlans((prev) => [
        { id: `local-${Date.now()}`, created_at: new Date().toISOString(), ...input },
        ...prev,
      ]);
    } else {
      try {
        await createMealPlan(token, input);
        refresh();
      } catch {
        return;
      }
    }
    setNewPlanName("");
    setNewPlanDesc("");
  };

  const handleDeletePlan = async (id: string) => {
    if (!token) {
      setPlans((prev) => prev.filter((p) => p.id !== id));
      setMeals((prev) =>
        prev.map((m) => (m.plan_id === id ? { ...m, plan_id: null } : m))
      );
      if (planFilter === id) setPlanFilter("all");
      return;
    }
    try {
      await deleteMealPlan(token, id);
      if (planFilter === id) setPlanFilter("all");
      refresh();
    } catch {
      // non-critical
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* Nav */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-6xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link
            href="/"
            className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-sm"
          >
            ← Dashboard
          </Link>
          <span className="text-[var(--text-muted)]">·</span>
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
            Meal plans
          </span>
          <Link
            href="/food-diary"
            className="ml-auto text-xs text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
          >
            Food diary →
          </Link>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Title */}
        <div className="space-y-1">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
            Meal plans
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? "Your data" : "Sample data"} · plan the week ahead, then log
            meals to your diary as you eat them
          </p>
        </div>

        {/* Not signed in banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              Showing a sample plan.{" "}
              <Link href="/login" className="text-[var(--color-accent)] hover:underline">
                Sign in
              </Link>{" "}
              to build and save your own meal plans.
            </p>
          </div>
        )}

        {/* Week navigator */}
        <div className="flex items-center justify-between gap-3">
          <button
            onClick={() => setWeekStart((w) => shiftDate(w, -7))}
            className="text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg border border-[var(--border-card)] transition-colors"
          >
            ← Prev week
          </button>
          <div className="flex items-center gap-2">
            <span className="text-sm text-[var(--text-primary)] font-medium">
              {weekdayLabel(weekStart).date} – {weekdayLabel(weekEnd).date}
            </span>
            <button
              onClick={() => setWeekStart(mondayOf(todayIso()))}
              className="text-xs text-[var(--text-muted)] hover:text-[var(--text-secondary)] px-2 py-1.5 transition-colors"
            >
              This week
            </button>
          </div>
          <button
            onClick={() => setWeekStart((w) => shiftDate(w, 7))}
            className="text-sm text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg border border-[var(--border-card)] transition-colors"
          >
            Next week →
          </button>
        </div>

        {/* Plan filter chips */}
        {plans.length > 0 && (
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-xs text-[var(--text-muted)] uppercase tracking-widest">
              Filter
            </span>
            <FilterChip
              active={planFilter === "all"}
              onClick={() => setPlanFilter("all")}
              label="All plans"
            />
            {plans.map((p) => (
              <FilterChip
                key={p.id}
                active={planFilter === p.id}
                onClick={() => setPlanFilter(p.id)}
                label={p.name}
              />
            ))}
          </div>
        )}

        {/* Weekly calendar grid */}
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-7 gap-3">
          {days.map((d) => {
            const dayMeals = visibleMeals.filter((m) => m.scheduled_on === d);
            const kcal = round(
              dayMeals.reduce((acc, m) => acc + (m.energy_kcal ?? 0), 0)
            );
            const isToday = d === todayIso();
            return (
              <div
                key={d}
                className={`rounded-xl border bg-[var(--bg-card)] shadow-sm flex flex-col ${
                  isToday ? "border-blue-500/50" : "border-[var(--border-card)]"
                }`}
              >
                <div className="px-3 py-2 border-b border-[var(--border-subtle)] flex items-baseline justify-between">
                  <div>
                    <p
                      className={`text-xs font-semibold ${
                        isToday ? "text-[var(--color-accent)]" : "text-[var(--text-primary)]"
                      }`}
                    >
                      {weekdayLabel(d).day}
                    </p>
                    <p className="text-[10px] text-[var(--text-muted)]">
                      {weekdayLabel(d).date}
                    </p>
                  </div>
                  {kcal > 0 && (
                    <span className="text-[10px] font-mono text-[var(--text-muted)] tabular-nums">
                      {kcal} kcal
                    </span>
                  )}
                </div>

                <div className="p-2 space-y-2 flex-1">
                  {MEAL_ORDER.map((slot) => {
                    const slotMeals = dayMeals.filter((m) => m.meal === slot);
                    if (slotMeals.length === 0) return null;
                    return (
                      <div key={slot} className="space-y-1">
                        <p className="text-[9px] uppercase tracking-widest text-[var(--text-muted)]">
                          {MEAL_LABEL[slot]}
                        </p>
                        {slotMeals.map((m) => (
                          <PlannedMealRow
                            key={m.id}
                            meal={m}
                            planName={planName(m.plan_id)}
                            canLog={!!token}
                            onToggleDone={() => handleToggleDone(m)}
                            onDelete={() => handleDeleteMeal(m.id)}
                            onLogToDiary={() => handleLogToDiary(m)}
                          />
                        ))}
                      </div>
                    );
                  })}

                  {pickerDay === d ? (
                    <PlannedMealPicker
                      token={token}
                      scheduledOn={d}
                      planId={planFilter === "all" ? null : planFilter}
                      onAdd={handleAdd}
                      onClose={() => setPickerDay(null)}
                    />
                  ) : (
                    <button
                      onClick={() => setPickerDay(d)}
                      className="w-full text-xs text-[var(--text-muted)] hover:text-[var(--color-accent)] hover:border-[var(--color-accent)] border border-dashed border-[var(--border-card)] rounded-lg py-1.5 transition-colors"
                    >
                      + Add meal
                    </button>
                  )}
                </div>
              </div>
            );
          })}
        </div>

        {/* Meal plans management */}
        <section className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm space-y-4">
          <div>
            <h2 className="text-sm font-medium text-[var(--text-primary)]">Your plans</h2>
            <p className="text-xs text-[var(--text-muted)]">
              Name a plan (e.g. &ldquo;Carnivore week&rdquo;) and file scheduled
              meals under it. Deleting a plan keeps its meals on the calendar.
            </p>
          </div>

          {plans.length > 0 && (
            <ul className="divide-y divide-[var(--border-subtle)] rounded-lg border border-[var(--border-subtle)] overflow-hidden">
              {plans.map((p) => (
                <li key={p.id} className="flex items-center gap-3 px-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm text-[var(--text-primary)] truncate">{p.name}</p>
                    {p.description && (
                      <p className="text-[11px] text-[var(--text-muted)] truncate">
                        {p.description}
                      </p>
                    )}
                  </div>
                  <span className="shrink-0 text-[10px] font-mono text-[var(--text-muted)]">
                    {meals.filter((m) => m.plan_id === p.id).length} meals
                  </span>
                  <button
                    onClick={() => handleDeletePlan(p.id)}
                    className="shrink-0 text-[var(--text-muted)] hover:text-[var(--color-out-range)] transition-colors text-lg leading-none"
                    aria-label={`Delete ${p.name}`}
                  >
                    ×
                  </button>
                </li>
              ))}
            </ul>
          )}

          {/* New plan form */}
          <div className="flex flex-wrap items-end gap-2">
            <div className="space-y-1 flex-1 min-w-[160px]">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                Plan name
              </label>
              <input
                value={newPlanName}
                onChange={(e) => setNewPlanName(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleCreatePlan()}
                placeholder="Carnivore week"
                className="w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 placeholder:text-[var(--text-muted)]"
              />
            </div>
            <div className="space-y-1 flex-1 min-w-[160px]">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                Description (optional)
              </label>
              <input
                value={newPlanDesc}
                onChange={(e) => setNewPlanDesc(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleCreatePlan()}
                placeholder="High-protein, zero-carb"
                className="w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 placeholder:text-[var(--text-muted)]"
              />
            </div>
            <button
              onClick={handleCreatePlan}
              disabled={!newPlanName.trim()}
              className="rounded-lg bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white text-sm font-semibold px-4 py-2 transition-colors"
            >
              Add plan
            </button>
          </div>
        </section>

        <footer className="border-t border-[var(--border-subtle)] pt-6 pb-4">
          <p className="text-xs text-[var(--text-muted)] text-center">
            Macros for searched foods come from{" "}
            <a
              href="https://world.openfoodfacts.org"
              target="_blank"
              rel="noopener noreferrer"
              className="text-[var(--color-accent)] hover:underline"
            >
              Open Food Facts
            </a>{" "}
            (ODbL). Planning ahead is not medical advice.
          </p>
        </footer>
      </main>
    </div>
  );
}

function FilterChip({
  active,
  onClick,
  label,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
}) {
  return (
    <button
      onClick={onClick}
      className={`text-xs px-3 py-1.5 rounded-full border transition-colors ${
        active
          ? "bg-blue-600 border-blue-600 text-white"
          : "border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
      }`}
    >
      {label}
    </button>
  );
}

function PlannedMealRow({
  meal,
  planName,
  canLog,
  onToggleDone,
  onDelete,
  onLogToDiary,
}: {
  meal: PlannedMeal;
  planName: string | null;
  canLog: boolean;
  onToggleDone: () => void;
  onDelete: () => void;
  onLogToDiary: () => void;
}) {
  return (
    <div className="group rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-base)] px-2 py-1.5">
      <div className="flex items-start gap-1.5">
        <button
          onClick={onToggleDone}
          aria-label={meal.done ? "Mark not eaten" : "Mark eaten"}
          className={`shrink-0 mt-0.5 w-3.5 h-3.5 rounded border flex items-center justify-center text-[9px] leading-none transition-colors ${
            meal.done
              ? "bg-[var(--color-in-range)] border-[var(--color-in-range)] text-white"
              : "border-[var(--border-card)] text-transparent hover:border-[var(--color-accent)]"
          }`}
        >
          ✓
        </button>
        <div className="min-w-0 flex-1">
          <p
            className={`text-xs truncate ${
              meal.done
                ? "text-[var(--text-muted)] line-through"
                : "text-[var(--text-primary)]"
            }`}
          >
            {meal.food_name}
          </p>
          <p className="text-[10px] text-[var(--text-muted)] font-mono">
            {meal.energy_kcal != null ? `${meal.energy_kcal} kcal` : "—"}
            {planName && <span> · {planName}</span>}
          </p>
        </div>
        <button
          onClick={onDelete}
          aria-label={`Delete ${meal.food_name}`}
          className="shrink-0 text-[var(--text-muted)] hover:text-[var(--color-out-range)] transition-colors leading-none opacity-0 group-hover:opacity-100"
        >
          ×
        </button>
      </div>
      {canLog && (
        <button
          onClick={onLogToDiary}
          className="mt-1 text-[10px] text-[var(--text-muted)] hover:text-[var(--color-accent)] transition-colors"
        >
          ↳ Log to diary
        </button>
      )}
    </div>
  );
}
