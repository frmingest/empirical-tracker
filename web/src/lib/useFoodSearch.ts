"use client";

import { useEffect, useRef, useState } from "react";
import type { FoodItem, FoodSearchSource } from "@/lib/api";
import { lookupBarcode, searchFoods } from "@/lib/api";

/**
 * Shared multi-source food search state machine, reused by the food diary
 * (Sprint 4) and the meal-plan calendar (Sprint 5). Both screens add foods the
 * same way — debounced text search across the chosen source (Open Food Facts,
 * Matvaretabellen, USDA, or all — ADR-018) plus direct barcode lookup — they
 * only differ in what they do with the chosen item, so the search/result state
 * lives here and the picker UI stays in each component.
 *
 * The source defaults to Matvaretabellen, matching the Norwegian-first framing:
 * the whole-food table is the right default for the app's primary user.
 */
export function useFoodSearch(
  token: string | null,
  initialSource: FoodSearchSource = "mvt"
) {
  const [query, setQuery] = useState("");
  const [barcode, setBarcode] = useState("");
  const [source, setSource] = useState<FoodSearchSource>(initialSource);
  const [results, setResults] = useState<FoodItem[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState("");
  const reqId = useRef(0);

  // Debounced full-text search. Live sources rate-limit (OFF ~10 req/min), so we
  // wait until the user pauses typing before firing. Re-runs when the chosen
  // source changes so switching sources re-queries the current text.
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
      searchFoods(token, q, source)
        .then((items) => {
          if (id === reqId.current) setResults(items);
        })
        .catch(() => {
          if (id === reqId.current)
            setError("Couldn't reach the food database. Try again.");
        })
        .finally(() => {
          if (id === reqId.current) setSearching(false);
        });
    }, 450);
    return () => clearTimeout(timer);
  }, [query, token, source]);

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

  const reset = () => {
    setQuery("");
    setBarcode("");
    setResults([]);
    setError("");
  };

  return {
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
    reset,
  };
}

/** Scale a per-100g nutrient to the consumed amount, rounded to 1 decimal. */
export function scaleNutrient(per100g: number | null, grams: number): number | null {
  if (per100g === null) return null;
  return Math.round(((per100g * grams) / 100) * 10) / 10;
}

/**
 * Stable identity for a search result. Codes can collide across sources (a USDA
 * fdcId and an OFF barcode are both numeric), so the source is part of the key —
 * needed once results from several sources are merged under "All".
 */
export function itemKey(item: Pick<FoodItem, "source" | "code" | "name">): string {
  return `${item.source}:${item.code || item.name}`;
}
