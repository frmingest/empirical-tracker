"use client";

import { useMemo, useState } from "react";
import type { BiomarkerWithSeries } from "@/lib/api";
import {
  CATEGORY_ORDER,
  groupByCategory,
  shortLabel,
} from "@/lib/biomarkerCategories";

interface Props {
  results: BiomarkerWithSeries[];
  /** Marker names (name_no) to pre-check. */
  initialSelected: string[];
  onSave: (selected: string[]) => void;
  onClose: () => void;
}

/**
 * Picker for the Custom diet view — choose exactly which biomarkers to follow,
 * grouped by category with per-category and global select/clear shortcuts.
 */
export function CustomMarkerModal({
  results,
  initialSelected,
  onSave,
  onClose,
}: Props) {
  const [selected, setSelected] = useState<Set<string>>(
    () => new Set(initialSelected)
  );

  const grouped = useMemo(() => groupByCategory(results), [results]);
  const allNames = useMemo(
    () => results.map((r) => r.biomarker.name_no),
    [results]
  );

  const toggle = (name: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });

  const setMany = (names: string[], on: boolean) =>
    setSelected((prev) => {
      const next = new Set(prev);
      names.forEach((n) => (on ? next.add(n) : next.delete(n)));
      return next;
    });

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-2xl max-h-[85vh] flex flex-col rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-start justify-between gap-4 px-5 py-4 border-b border-[var(--border-subtle)]">
          <div>
            <h2 className="text-base font-semibold text-[var(--text-primary)]">
              Customize markers
            </h2>
            <p className="text-xs text-[var(--text-muted)] mt-0.5">
              Pick exactly which biomarkers to follow.
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="text-[var(--text-muted)] hover:text-[var(--text-primary)] text-xl leading-none"
          >
            ×
          </button>
        </div>

        {/* Toolbar */}
        <div className="flex items-center gap-3 px-5 py-2.5 border-b border-[var(--border-subtle)]">
          <button
            onClick={() => setMany(allNames, true)}
            className="text-xs font-medium text-[var(--color-accent)] hover:underline"
          >
            Select all
          </button>
          <span className="text-[var(--border-card)]">·</span>
          <button
            onClick={() => setMany(allNames, false)}
            className="text-xs font-medium text-[var(--text-secondary)] hover:text-[var(--text-primary)]"
          >
            Clear
          </button>
          <span className="ml-auto text-xs text-[var(--text-muted)] font-mono tabular-nums">
            {selected.size} / {allNames.length} selected
          </span>
        </div>

        {/* Body */}
        <div className="flex-1 overflow-y-auto px-5 py-4 space-y-5">
          {CATEGORY_ORDER.map((cat) => {
            const items = grouped[cat];
            if (items.length === 0) return null;
            const names = items.map((i) => i.biomarker.name_no);
            const allOn = names.every((n) => selected.has(n));

            return (
              <section key={cat}>
                <div className="flex items-center gap-3 mb-2">
                  <h3 className="text-xs font-semibold uppercase tracking-widest text-[var(--text-secondary)]">
                    {cat}
                  </h3>
                  <div className="flex-1 h-px bg-[var(--border-subtle)]" />
                  <button
                    onClick={() => setMany(names, !allOn)}
                    className="text-[10px] font-medium text-[var(--color-accent)] hover:underline"
                  >
                    {allOn ? "Clear" : "All"}
                  </button>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-1.5">
                  {items.map((item) => {
                    const name = item.biomarker.name_no;
                    const checked = selected.has(name);
                    return (
                      <label
                        key={item.biomarker.id}
                        className={`flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg border cursor-pointer transition-colors ${
                          checked
                            ? "border-[var(--color-accent)] bg-[var(--color-accent)]/5"
                            : "border-[var(--border-card)] hover:bg-[var(--bg-elevated)]"
                        }`}
                      >
                        <input
                          type="checkbox"
                          checked={checked}
                          onChange={() => toggle(name)}
                          className="accent-[var(--color-accent)]"
                        />
                        <span className="text-xs text-[var(--text-primary)] truncate">
                          {item.biomarker.name_en ?? shortLabel(name)}
                        </span>
                      </label>
                    );
                  })}
                </div>
              </section>
            );
          })}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 px-5 py-3.5 border-t border-[var(--border-subtle)]">
          <button
            onClick={onClose}
            className="text-xs font-medium border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={() => onSave([...selected])}
            className="text-xs font-medium bg-blue-600 hover:bg-blue-500 text-white px-4 py-1.5 rounded-lg transition-colors"
          >
            Apply selection
          </button>
        </div>
      </div>
    </div>
  );
}
