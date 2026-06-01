"use client";

import { useEffect, useRef, useState } from "react";
import type { FoodItem } from "@/lib/api";
import { lookupBarcode, searchFoods } from "@/lib/api";

/**
 * Shared Open Food Facts search state machine, reused by the food diary
 * (Sprint 4) and the meal-plan calendar (Sprint 5). Both screens add foods the
 * same way — debounced text search plus direct barcode lookup — they only
 * differ in what they do with the chosen item, so the search/result state lives
 * here and the picker UI stays in each component.
 */
export function useFoodSearch(token: string | null) {
  const [query, setQuery] = useState("");
  const [barcode, setBarcode] = useState("");
  const [results, setResults] = useState<FoodItem[]>([]);
  const [searching, setSearching] = useState(false);
  const [error, setError] = useState("");
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
          if (id === reqId.current)
            setError("Couldn't reach Open Food Facts. Try again.");
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
