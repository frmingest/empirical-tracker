"use client";

import { useState } from "react";
import type { DietEvent, DietEventKind } from "@/lib/api";
import { createDietEvent, deleteDietEvent } from "@/lib/api";
import { kindColor } from "@/lib/chartAnnotations";
import { fmtDateLong } from "@/lib/biomarkerCategories";

interface Props {
  token: string | null;
  events: DietEvent[];
  /** Called after a successful add/delete so the parent can refetch. */
  onChange: () => void;
}

const KINDS: DietEventKind[] = [
  "diet",
  "fast",
  "supplement",
  "medication",
  "lifestyle",
  "other",
];

const KIND_LABEL: Record<DietEventKind, string> = {
  diet: "Diet",
  fast: "Fast",
  supplement: "Supplement",
  medication: "Medication",
  lifestyle: "Lifestyle",
  other: "Other",
};

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/**
 * Manage the diet events that annotate the biomarker charts (Sprint 3).
 * Events are account-wide — every chart shows the same overlay — so this editor
 * works on the full list, not a single biomarker.
 */
export function DietEventManager({ token, events, onChange }: Props) {
  const [open, setOpen] = useState(false);
  const [label, setLabel] = useState("");
  const [kind, setKind] = useState<DietEventKind>("diet");
  const [startedOn, setStartedOn] = useState(todayIso());
  const [endedOn, setEndedOn] = useState("");
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  const reset = () => {
    setLabel("");
    setKind("diet");
    setStartedOn(todayIso());
    setEndedOn("");
    setNote("");
    setError("");
  };

  const handleAdd = async () => {
    if (!token) return;
    if (!label.trim()) {
      setError("Give the annotation a short label.");
      return;
    }
    if (endedOn && endedOn < startedOn) {
      setError("End date can't be before the start date.");
      return;
    }
    setBusy(true);
    setError("");
    try {
      await createDietEvent(token, {
        label: label.trim(),
        kind,
        started_on: startedOn,
        ended_on: endedOn || null,
        note: note.trim() || null,
      });
      reset();
      setOpen(false);
      onChange();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Could not save annotation.");
    } finally {
      setBusy(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!token) return;
    try {
      await deleteDietEvent(token, id);
      onChange();
    } catch {
      // non-critical; leave the list as-is
    }
  };

  const inputCls =
    "w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50";

  return (
    <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-4 shadow-sm space-y-3">
      <div className="flex items-center justify-between gap-3">
        <div>
          <h3 className="text-sm font-medium text-[var(--text-primary)]">
            Diet annotations
          </h3>
          <p className="text-xs text-[var(--text-muted)]">
            Mark when you changed your regimen to see it on every chart.
          </p>
        </div>
        {token && (
          <button
            onClick={() => setOpen((v) => !v)}
            className="shrink-0 text-xs font-medium border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] px-3 py-1.5 rounded-lg transition-colors"
          >
            {open ? "Cancel" : "+ Add annotation"}
          </button>
        )}
      </div>

      {!token && (
        <p className="text-xs text-amber-600">
          Sign in to add your own diet annotations. The markers shown are sample data.
        </p>
      )}

      {/* Existing events */}
      {events.length > 0 && (
        <ul className="space-y-1.5">
          {events.map((ev) => (
            <li
              key={ev.id}
              className="flex items-center gap-2 text-xs text-[var(--text-secondary)]"
            >
              <span
                className="inline-block w-2.5 h-2.5 rounded-sm shrink-0"
                style={{ backgroundColor: kindColor(ev.kind), opacity: 0.8 }}
              />
              <span className="text-[var(--text-primary)] font-medium">{ev.label}</span>
              <span className="text-[var(--text-muted)]">
                · {fmtDateLong(ev.started_on)}
                {ev.ended_on ? ` → ${fmtDateLong(ev.ended_on)}` : ""}
              </span>
              {token && (
                <button
                  onClick={() => handleDelete(ev.id)}
                  className="ml-auto text-[var(--text-muted)] hover:text-[var(--color-out-range)] transition-colors"
                  aria-label={`Delete ${ev.label}`}
                >
                  ×
                </button>
              )}
            </li>
          ))}
        </ul>
      )}

      {/* Add form */}
      {open && token && (
        <div className="space-y-3 border-t border-[var(--border-subtle)] pt-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                Label
              </label>
              <input
                value={label}
                onChange={(e) => setLabel(e.target.value)}
                placeholder="e.g. Started carnivore"
                disabled={busy}
                className={`${inputCls} placeholder:text-[var(--text-muted)]`}
              />
            </div>
            <div className="space-y-1.5">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                Kind
              </label>
              <select
                value={kind}
                onChange={(e) => setKind(e.target.value as DietEventKind)}
                disabled={busy}
                className={inputCls}
              >
                {KINDS.map((k) => (
                  <option key={k} value={k}>
                    {KIND_LABEL[k]}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1.5">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                Start date
              </label>
              <input
                type="date"
                value={startedOn}
                onChange={(e) => setStartedOn(e.target.value)}
                disabled={busy}
                className={inputCls}
              />
            </div>
            <div className="space-y-1.5">
              <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
                End date (optional)
              </label>
              <input
                type="date"
                value={endedOn}
                onChange={(e) => setEndedOn(e.target.value)}
                disabled={busy}
                className={inputCls}
              />
            </div>
          </div>
          <div className="space-y-1.5">
            <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
              Note (optional)
            </label>
            <input
              value={note}
              onChange={(e) => setNote(e.target.value)}
              disabled={busy}
              className={inputCls}
            />
          </div>
          {error && <p className="text-xs text-[var(--color-out-range)]">{error}</p>}
          <button
            onClick={handleAdd}
            disabled={busy}
            className="w-full rounded-lg bg-[var(--btn-accent)] hover:bg-[var(--btn-accent-hover)] disabled:bg-[var(--bg-elevated)] disabled:text-[var(--text-muted)] text-[var(--btn-accent-text)] text-sm font-semibold py-2.5 transition-colors"
          >
            {busy ? "Saving…" : "Save annotation"}
          </button>
        </div>
      )}
    </div>
  );
}
