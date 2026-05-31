"use client";

import { useEffect, useRef, useState } from "react";
import type { FoodEntryInput, FoodItem, Meal } from "@/lib/api";
import { lookupBarcode, searchFoods } from "@/lib/api";

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

/** Scale a per-100g nutrient to the consumed amount, rounded to 1 decimal. */
function scale(per100g: number | null, grams: number): number | null {
  if (per100g === null) return null;
  return Math.round((per100g * grams) / 100 * 10) / 10;
}

export function FoodSearch({ token, loggedOn, onAdd }: Props) {
  const [query, setQuery] = useState("");
  const [barcode, setBarcode] = useState("");
  const [results, setResults] = useState<FoodItem[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState("");
  // The result currently being added, plus its quantity/meal selection.
  const [selected, setSelected] = useState<FoodItem | null>(null);
  const [grams, setGrams] = useState("100");
  const [meal, setMeal] = useState<Meal>("breakfast");
  const reqId = useRef(0);

  // Debounced full-text search. OFF rate-limits search to ~10 req/min, so we
  // wait until the user pauses typing before firing.
  useEffect(() => {
    if (!token) return;
    const q = query.trim();
    if (q.length < 2) {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      setResults([]);
      return;
    }
    const id = ++reqId.current;
    setSearching(true);
    setError("");
    const timer = setTimeout(() => {
      searchFoods(token, q)
        .then((items) => {
          if (id === reqId.current) setResults(items);
        })
        .catch(() => {
          if (id === reqId.current) setError("Couldn't reach Open Food Facts. Try again.");
        })
        .finally(() => {
          if (id === reqId.current) setSearching(false);
        });
    }, 450);
    return () => clearTimeout(timer);
  }, [query, token]);

  const handleBarcode = async () => {
    if (!token || !barcode.trim()) return;
    setSearching(true);
    setError("");
    try {
      const item = await lookupBarcode(token, barcode.trim());
      setResults([item]);
    } catch {
      setError("No product found for that barcode.");
      setResults([]);
    } finally {
      setSearching(false);
    }
  };

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
      energy_kcal: qty !== null ? scale(selected.energy_kcal_100g, qty) : null,
      carbs_g: qty !== null ? scale(selected.carbs_100g, qty) : null,
      protein_g: qty !== null ? scale(selected.protein_100g, qty) : null,
      fat_g: qty !== null ? scale(selected.fat_100g, qty) : null,
    });
    setSelected(null);
    setGrams("100");
    setQuery("");
    setBarcode("");
    setResults([]);
  };

  const inputCls =
    "w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50 placeholder:text-[var(--text-muted)]";

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm space-y-3">
      <div>
        <h3 className="text-sm font-medium text-[var(--text-primary)]">Add food</h3>
        <p className="text-xs text-[var(--text-muted)]">
          Search the Open Food Facts branded &amp; barcode database, or enter a
          barcode directly. Nutrition is taken as-published — never estimated.
        </p>
      </div>

      {!token ? (
        <p className="text-xs text-amber-600">
          Sign in to search Open Food Facts and log food.
        </p>
      ) : (
        <>
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search foods (e.g. ribeye, cheddar, eggs)…"
            className={inputCls}
          />
          <div className="flex gap-2">
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

          {searching && <p className="text-xs text-[var(--text-muted)]">Searching…</p>}
          {error && <p className="text-xs text-[var(--color-out-range)]">{error}</p>}

          {/* Results */}
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
                      {selected?.code === item.code ? "Close" : "Add"}
                    </button>
                  </div>

                  {/* Inline quantity + meal picker */}
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
                        className="rounded-lg bg-blue-600 hover:bg-blue-500 text-white text-sm font-semibold px-4 py-2 transition-colors"
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
