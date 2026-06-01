"use client";

import { useLanguage } from "@/components/LanguageProvider";
import { markerNote } from "@/lib/markerNotes";

interface Props {
  /** Raw Norwegian marker name (name_no). */
  nameNo: string;
}

/**
 * Sprint 8 — per-marker "confounder" note. For the handful of markers that are
 * routinely misread on a carnivore / low-carb / fasting protocol (eGFR, HbA1c,
 * ferritin), this names *why* the diet itself can move the number. Renders
 * nothing for markers without a seeded note. Decision-support, not a diagnosis.
 */
export function MarkerNote({ nameNo }: Props) {
  const { lang } = useLanguage();
  const note = markerNote(nameNo);
  if (!note) return null;

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-5 shadow-sm space-y-2">
      <div className="flex items-center gap-2">
        <span className="w-4 h-4 flex items-center justify-center rounded-full border border-[var(--border-card)] text-[10px] font-semibold leading-none text-[var(--text-muted)]">
          i
        </span>
        <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)]">
          {note.title[lang]}
        </h2>
      </div>
      <p className="text-sm text-[var(--text-secondary)] leading-relaxed">
        {note.body[lang]}
      </p>
      <p className="text-[11px] text-[var(--text-muted)] leading-relaxed border-t border-[var(--border-subtle)] pt-3">
        Context to read this marker with — decision-support, not medical advice.
      </p>
    </div>
  );
}
