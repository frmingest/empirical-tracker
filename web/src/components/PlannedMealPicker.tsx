"use client";

import { useState } from "react";
import type { FoodItem, Meal, PlannedMealInput } from "@/lib/api";
import { scaleNutrient, useFoodSearch } from "@/lib/useFoodSearch";

interface Props {
  token: string | null;
  /** ISO date the meal is being scheduled for. */
  scheduledOn: string;
  /** Meal slot to default the picker to. */
  defaultMeal?: Meal;
  /** Plan this meal is filed under, if any. */
  planId?: string | null;
  onAdd: (input: PlannedMealInput) => Promise<void> | void;
  onClose: () => void;
}

const MEALS: Meal[] = ["breakfast", "lunch", "dinner", "snack", "other"];

const MEAL_LABEL: Record<Meal, string> = {
  breakfast: "Breakfast",
  lunch: "Lunch",
  dinner: "Dinner",
  snack: "Snack",
  other: "Other",
};

export function PlannedMealPicker({
  token,
  scheduledOn,
  defaultMeal = "breakfast",
  planId = null,
  onAdd,
  onClose,
}: Props) {
  const search = useFoodSearch(token);
  const { query, setQuery, barcode, setBarcode, results, searching, error, handleBarcode } =
    search;
  const [selected, setSelected] = useState<FoodItem | null>(null);
  const [grams, setGrams] = useState("100");
  const [meal, setMeal] = useState<Meal>(defaultMeal);
  // Free-text fallback for planning a meal that isn't in Open Food Facts.
  const [freeText, setFreeText] = useState("");

  const inputCls =
    "w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50 placeholder:text-[var(--text-muted)]";

  const handleConfirmFromSearch = async () => {
    if (!selected) return;
    const g = parseFloat(grams);
    const qty = isNaN(g) ? null : g;
    await onAdd({
      scheduled_on: scheduledOn,
      meal,
      plan_id: planId,
      food_name: selected.name,
      brand: selected.brand,
      barcode: selected.code || null,
      quantity_g: qty,
      energy_kcal: qty !== null ? scaleNutrient(selected.energy_kcal_100g, qty) : null,
      carbs_g: qty !== null ? scaleNutrient(selected.carbs_100g, qty) : null,
      protein_g: qty !== null ? scaleNutrient(selected.protein_100g, qty) : null,
      fat_g: qty !== null ? scaleNutrient(selected.fat_100g, qty) : null,
    });
    onClose();
  };

  const handleConfirmFreeText = async () => {
    const name = freeText.trim();
    if (!name) return;
    await onAdd({
      scheduled_on: scheduledOn,
      meal,
      plan_id: planId,
      food_name: name,
    });
    onClose();
  };

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm space-y-3">
      <div className="flex items-start justify-between gap-3">
        <div>
          <h3 className="text-sm font-medium text-[var(--text-primary)]">Plan a meal</h3>
          <p className="text-xs text-[var(--text-muted)]">
            Search Open Food Facts for macros, or just jot down what you intend to
            eat.
          </p>
        </div>
        <button
          onClick={onClose}
          className="shrink-0 text-[var(--text-muted)] hover:text-[var(--text-primary)] text-lg leading-none"
          aria-label="Close"
        >
          ×
        </button>
      </div>

      {/* Meal slot — shared by both add paths */}
      <div className="flex items-end gap-2">
        <div className="space-y-1">
          <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
            Meal
          </label>
          <select
            value={meal}
            onChange={(e) => setMeal(e.target.value as Meal)}
            className="rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500"
          >
            {MEALS.map((m) => (
              <option key={m} value={m}>
                {MEAL_LABEL[m]}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Free-text quick add */}
      <div className="flex gap-2">
        <input
          value={freeText}
          onChange={(e) => setFreeText(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && handleConfirmFreeText()}
          placeholder="Quick add (e.g. Ribeye + eggs)…"
          className={inputCls}
        />
        <button
          onClick={handleConfirmFreeText}
          disabled={!freeText.trim()}
          className="shrink-0 rounded-lg bg-blue-600 hover:bg-blue-500 disabled:opacity-40 text-white text-sm font-semibold px-4 transition-colors"
        >
          Add
        </button>
      </div>

      {!token ? (
        <p className="text-xs text-amber-600">
          Sign in to search Open Food Facts for nutrition data.
        </p>
      ) : (
        <>
          <div className="border-t border-[var(--border-subtle)] pt-3">
            <p className="text-[10px] uppercase tracking-widest text-[var(--text-muted)] mb-2">
              …or search for macros
            </p>
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search foods (e.g. ribeye, cheddar, eggs)…"
              className={inputCls}
            />
            <div className="flex gap-2 mt-2">
              <input
                value={barcode}
                onChange={(e) => setBarcode(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && handleBarcode()}
                placeholder="…or enter a barcode"
                inputMode="numeric"
                className={inputCls}
              />
              <button
                onClick={handleBarcode}
                className="shrink-0 text-xs font-medium border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 rounded-lg transition-colors"
              >
                Look up
              </button>
            </div>
          </div>

          {searching && <p className="text-xs text-[var(--text-muted)]">Searching…</p>}
          {error && <p className="text-xs text-[var(--color-out-range)]">{error}</p>}

          {results.length > 0 && (
            <ul className="divide-y divide-[var(--border-subtle)] rounded-lg border border-[var(--border-subtle)] overflow-hidden">
              {results.map((item) => (
                <li key={item.code || item.name} className="px-3 py-2">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="text-sm text-[var(--text-primary)] truncate">
                        {item.name}
                        {item.brand && (
                          <span className="text-[var(--text-muted)]"> · {item.brand}</span>
                        )}
                      </p>
                      <p className="text-[11px] text-[var(--text-muted)] font-mono">
                        {item.energy_kcal_100g ?? "—"} kcal · C{item.carbs_100g ?? "—"} /
                        P{item.protein_100g ?? "—"} / F{item.fat_100g ?? "—"} per 100 g
                      </p>
                    </div>
                    <button
                      onClick={() =>
                        setSelected(selected?.code === item.code ? null : item)
                      }
                      className="shrink-0 text-xs font-medium text-[var(--color-accent)] hover:underline"
                    >
                      {selected?.code === item.code ? "Close" : "Choose"}
                    </button>
                  </div>

                  {selected?.code === item.code && (
                    <div className="mt-2 flex flex-wrap items-end gap-2">
                      <div className="space-y-1">
                        <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                          Grams
                        </label>
                        <input
                          type="number"
                          min="0"
                          step="1"
                          value={grams}
                          onChange={(e) => setGrams(e.target.value)}
                          className="w-24 rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500"
                        />
                      </div>
                      <button
                        onClick={handleConfirmFromSearch}
                        className="rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold px-4 py-2 transition-colors"
                      >
                        Plan it
                      </button>
                    </div>
                  )}
                </li>
              ))}
            </ul>
          )}
        </>
      )}
    </div>
  );
}
