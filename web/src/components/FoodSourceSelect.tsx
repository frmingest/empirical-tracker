"use client";

import { FOOD_SOURCE_LABEL, type FoodSearchSource, type FoodSource } from "@/lib/api";

/** Options offered in the search-source selector, in display order. */
const SOURCE_OPTIONS: { value: FoodSearchSource; label: string }[] = [
  { value: "mvt", label: "Whole foods (NO)" },
  { value: "usda", label: "Whole foods (US)" },
  { value: "off", label: "Branded (OFF)" },
  { value: "all", label: "All sources" },
];

/** Short badge text per source, for tagging individual result/entry rows. */
const SOURCE_BADGE: Record<FoodSource, string> = {
  mvt: "NO",
  usda: "US",
  off: "OFF",
};

interface SelectProps {
  value: FoodSearchSource;
  onChange: (value: FoodSearchSource) => void;
}

/** Picks which food database(s) the text search targets (ADR-018). */
export function FoodSourceSelect({ value, onChange }: SelectProps) {
  return (
    <div className="space-y-1">
      <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
        Source
      </label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as FoodSearchSource)}
        className="rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500"
      >
        {SOURCE_OPTIONS.map((o) => (
          <option key={o.value} value={o.value}>
            {o.label}
          </option>
        ))}
      </select>
    </div>
  );
}

/**
 * A small provenance badge showing which database a food's numbers came from.
 * Lab-analysed whole-food sources (NO/US) are tinted to stand apart from the
 * crowd-sourced branded source (OFF) — provenance the user, and their clinician
 * reading an export, can see at a glance.
 */
export function FoodSourceBadge({ source }: { source: FoodSource | null }) {
  if (!source) return null;
  const isWholeFood = source === "mvt" || source === "usda";
  const cls = isWholeFood
    ? "border-emerald-500/30 text-emerald-600 bg-emerald-500/10"
    : "border-[var(--border-card)] text-[var(--text-muted)] bg-[var(--bg-elevated)]";
  return (
    <span
      title={FOOD_SOURCE_LABEL[source]}
      className={`shrink-0 rounded px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-wide border ${cls}`}
    >
      {SOURCE_BADGE[source]}
    </span>
  );
}
