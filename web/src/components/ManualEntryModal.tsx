"use client";

import { useState } from "react";
import Link from "next/link";
import type { BiomarkerWithSeries } from "@/lib/api";
import { addManualResult } from "@/lib/api";
import { shortLabel } from "@/lib/biomarkerCategories";

interface Props {
  onClose: () => void;
  token: string | null;
  results: BiomarkerWithSeries[];
  onSuccess: () => void;
  /** When set (e.g. opened from a biomarker page), pre-select this marker. */
  initialBiomarkerId?: string;
}

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

export function ManualEntryModal({
  onClose,
  token,
  results,
  onSuccess,
  initialBiomarkerId,
}: Props) {
  const [biomarkerId, setBiomarkerId] = useState(
    initialBiomarkerId ?? results[0]?.biomarker.id ?? ""
  );
  const [testedAt, setTestedAt] = useState(todayIso());
  const [valueStr, setValueStr] = useState("");
  const [status, setStatus] = useState<"idle" | "submitting" | "success" | "error">("idle");
  const [errorMsg, setErrorMsg] = useState("");

  const handleSubmit = async () => {
    if (!token) {
      setErrorMsg("You need to sign in to add a result.");
      setStatus("error");
      return;
    }
    if (!biomarkerId || !testedAt || valueStr === "") {
      setErrorMsg("Please fill in all fields.");
      setStatus("error");
      return;
    }
    const value = parseFloat(valueStr);
    if (isNaN(value)) {
      setErrorMsg("Value must be a number.");
      setStatus("error");
      return;
    }

    setStatus("submitting");
    setErrorMsg("");

    try {
      await addManualResult(token, biomarkerId, testedAt, value);
      setStatus("success");
      onSuccess();
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : "Submit failed");
      setStatus("error");
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div className="w-full max-w-md rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-2xl">
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4 border-b border-[var(--border-card)]">
          <h2 className="text-base font-semibold text-[var(--text-primary)]">
            Add result
          </h2>
          <button
            onClick={onClose}
            className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-xl leading-none"
          >
            ×
          </button>
        </div>

        <div className="px-6 py-5 space-y-4">
          {/* Auth gate */}
          {!token && (
            <div className="rounded-lg border border-amber-500/20 bg-amber-500/5 px-4 py-3">
              <p className="text-amber-600 text-sm">
                <Link href="/login" className="underline underline-offset-2">
                  Sign in
                </Link>{" "}
                to add results.
              </p>
            </div>
          )}

          {/* Biomarker select */}
          <div className="space-y-1.5">
            <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
              Biomarker
            </label>
            <select
              value={biomarkerId}
              onChange={(e) => setBiomarkerId(e.target.value)}
              disabled={!token || status === "submitting"}
              className="w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            >
              {results.map((r) => (
                <option key={r.biomarker.id} value={r.biomarker.id}>
                  {shortLabel(r.biomarker.name_no)}
                  {r.biomarker.unit ? ` (${r.biomarker.unit})` : ""}
                </option>
              ))}
            </select>
          </div>

          {/* Date input */}
          <div className="space-y-1.5">
            <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
              Date
            </label>
            <input
              type="date"
              value={testedAt}
              onChange={(e) => setTestedAt(e.target.value)}
              disabled={!token || status === "submitting"}
              className="w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50"
            />
          </div>

          {/* Value input */}
          <div className="space-y-1.5">
            <label className="text-[10px] uppercase tracking-widest text-[var(--text-muted)]">
              Value
            </label>
            <input
              type="number"
              step="0.01"
              value={valueStr}
              onChange={(e) => setValueStr(e.target.value)}
              placeholder="e.g. 1.35"
              disabled={!token || status === "submitting"}
              className="w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-2 focus:outline-none focus:border-blue-500 disabled:opacity-50 placeholder:text-[var(--text-muted)]"
            />
          </div>

          {/* Success */}
          {status === "success" && (
            <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 px-4 py-3">
              <p className="text-emerald-600 text-sm font-mono">
                Result added successfully.
              </p>
            </div>
          )}

          {/* Error */}
          {status === "error" && (
            <div className="rounded-lg bg-rose-500/10 border border-rose-500/20 px-4 py-3">
              <p className="text-[var(--color-out-range)] text-sm">{errorMsg}</p>
            </div>
          )}

          {/* Submit */}
          <button
            onClick={handleSubmit}
            disabled={!token || status === "submitting" || status === "success"}
            className="w-full rounded-lg bg-blue-600 hover:bg-blue-500 disabled:bg-[var(--bg-elevated)] disabled:text-[var(--text-muted)] text-white text-sm font-semibold py-2.5 transition-colors"
          >
            {status === "submitting" ? "Saving…" : status === "success" ? "Saved" : "Add result"}
          </button>
        </div>
      </div>
    </div>
  );
}
