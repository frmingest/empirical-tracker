"use client";

import { useState } from "react";
import type { FoodEntryInput, FoodItem, Meal } from "@/lib/api";
import { itemKey, scaleNutrient, useFoodSearch } from "@/lib/useFoodSearch";
import { FoodSourceBadge, FoodSourceSelect } from "@/components/FoodSourceSelect";

interface Props {
  token: string | null;
  loggedOn: string;
  onAdd: (input: FoodEntryInput) => Promise<void> | void;
}

const MEALS: Meal[] = ["breakfast", "lunch", "dinner", "snack", "other"];

const MEAL_LABEL: Record<Meal, string> = {
  breakfast: "Breakfast",
  lunch: "Lunch",
  dinner: "Dinner",
  snack: "Snack",
  other: "Other",
};

export function FoodSearch({ token, loggedOn, onAdd }: Props) {
  const search = useFoodSearch(token);
  const {
    query,
    setQuery,
    barcode,
    setBarcode,
    source,
    setSource,
    results,
    searching,
    error,
    handleBarcode,
  } = search;
  // The result currently being added, plus its quantity/meal selection.
  const [selected, setSelected] = useState<FoodItem | null>(null);
  const [grams, setGrams] = useState("100");
  const [meal, setMeal] = useState<Meal>("breakfast");

  const handleConfirmAdd = async () => {
    if (!selected) return;
    const g = parseFloat(grams);
    const qty = isNaN(g) ? null : g;
    await onAdd({
      logged_on: loggedOn,
      meal,
      food_name: selected.name,
      brand: selected.brand,
      barcode: selected.code || null,
      quantity_g: qty,
      energy_kcal: qty !== null ? scaleNutrient(selected.energy_kcal_100g, qty) : null,
      carbs_g: qty !== null ? scaleNutrient(selected.carbs_100g, qty) : null,
      protein_g: qty !== null ? scaleNutrient(selected.protein_100g, qty) : null,
      fat_g: qty !== null ? scaleNutrient(selected.fat_100g, qty) : null,
      saturated_fat_g: qty !== null ? scaleNutrient(selected.saturated_fat_100g, qty) : null,
      sodium_mg: qty !== null ? scaleNutrient(selected.sodium_mg_100g, qty) : null,
      source: selected.source,
    });
    setSelected(null);
    setGrams("100");
    search.reset();
  };

  const inputCls =
    "w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50 placeholder:text-[var(--text-muted)]";

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm space-y-3">
      <div>
        <h3 className="text-sm font-medium text-[var(--text-primary)]">Add food</h3>
        <p className="text-xs text-[var(--text-muted)]">
          Search lab-analysed whole foods (Matvaretabellen, USDA) or the Open Food
          Facts branded &amp; barcode database. Nutrition is taken as-published —
          never estimated.
        </p>
      </div>

      {!token ? (
        <p className="text-xs text-amber-600">
          Sign in to search the food databases and log food.
        </p>
      ) : (
        <>
          <div className="flex items-end gap-2">
            <FoodSourceSelect value={source} onChange={setSource} />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search foods (e.g. ribeye, cheddar, eggs)…"
              className={inputCls}
            />
          </div>
          <div className="flex gap-2">
            <input
              value={barcode}
              onChange={(e) => setBarcode(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && handleBarcode()}
              placeholder="…or enter a barcode (Open Food Facts)"
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

          {searching && <p className="text-xs text-[var(--text-muted)]">Searching…</p>}
          {error && <p className="text-xs text-[var(--color-out-range)]">{error}</p>}

          {/* Results */}
          {results.length > 0 && (
            <ul className="divide-y divide-[var(--border-subtle)] rounded-lg border border-[var(--border-subtle)] overflow-hidden">
              {results.map((item) => (
                <li key={itemKey(item)} className="px-3 py-2">
                  <div className="flex items-center justify-between gap-3">
                    <div className="min-w-0">
                      <p className="flex items-center gap-1.5 text-sm text-[var(--text-primary)]">
                        <FoodSourceBadge source={item.source} />
                        <span className="truncate">
                          {item.name}
                          {item.brand && (
                            <span className="text-[var(--text-muted)]"> · {item.brand}</span>
                          )}
                        </span>
                      </p>
                      <p className="text-[11px] text-[var(--text-muted)] font-mono">
                        {item.energy_kcal_100g ?? "—"} kcal · C{item.carbs_100g ?? "—"} /
                        P{item.protein_100g ?? "—"} / F{item.fat_100g ?? "—"}
                        {" "}(sat {item.saturated_fat_100g ?? "—"}) · Na{" "}
                        {item.sodium_mg_100g ?? "—"} mg per 100 g
                      </p>
                    </div>
                    <button
                      onClick={() =>
                        setSelected(selected && itemKey(selected) === itemKey(item) ? null : item)
                      }
                      className="shrink-0 text-xs font-medium text-[var(--color-accent)] hover:underline"
                    >
                      {selected && itemKey(selected) === itemKey(item) ? "Close" : "Add"}
                    </button>
                  </div>

                  {/* Inline quantity + meal picker */}
                  {selected && itemKey(selected) === itemKey(item) && (
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
                      <button
                        onClick={handleConfirmAdd}
                        className="rounded-lg bg-[var(--btn-accent)] hover:bg-[var(--btn-accent-hover)] text-[var(--btn-accent-text)] text-sm font-semibold px-4 py-2 transition-colors"
                      >
                        Log it
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
