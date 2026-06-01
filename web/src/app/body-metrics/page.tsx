"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useAuth } from "@/contexts/AuthContext";
import {
  createBodyMetric,
  deleteBodyMetric,
  listBodyMetrics,
  listDietEvents,
  type BodyMetric,
  type BodyMetricInput,
  type DietEvent,
} from "@/lib/api";
import { MOCK_BODY_METRICS, MOCK_DIET_EVENTS } from "@/lib/mockData";
import { BodyMetricChart } from "@/components/BodyMetricChart";
import { fmtDateLong } from "@/lib/biomarkerCategories";

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}

/** Parse a number input, returning null for blank/invalid. */
function num(v: string): number | null {
  if (v.trim() === "") return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

const EMPTY_FORM = {
  measured_on: todayIso(),
  weight_kg: "",
  waist_cm: "",
  systolic: "",
  diastolic: "",
  note: "",
};

export default function BodyMetricsPage() {
  const { session, loading } = useAuth();
  const token = session?.access_token ?? null;
  const [metrics, setMetrics] = useState<BodyMetric[]>(MOCK_BODY_METRICS);
  const [events, setEvents] = useState<DietEvent[]>(MOCK_DIET_EVENTS);
  const [isLive, setIsLive] = useState(false);
  const [form, setForm] = useState({ ...EMPTY_FORM });
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (loading || !token) return; // signed out → keep demo data
    Promise.all([listBodyMetrics(token), listDietEvents(token)])
      .then(([rows, evts]) => {
        setMetrics(rows);
        setEvents(evts);
        setIsLive(true);
      })
      .catch(() => {});
  }, [token, loading]);

  const refresh = () => {
    if (!token) return;
    listBodyMetrics(token)
      .then(setMetrics)
      .catch(() => {});
  };

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);

    const input: BodyMetricInput = {
      measured_on: form.measured_on,
      weight_kg: num(form.weight_kg),
      waist_cm: num(form.waist_cm),
      systolic: num(form.systolic),
      diastolic: num(form.diastolic),
      note: form.note.trim() || null,
    };

    // Mirror the server's coherence rules for a friendly inline message.
    if ((input.systolic == null) !== (input.diastolic == null)) {
      setError("Blood pressure needs both systolic and diastolic.");
      return;
    }
    if (input.weight_kg == null && input.waist_cm == null && input.systolic == null) {
      setError("Enter at least one of weight, waist, or blood pressure.");
      return;
    }

    if (!token) {
      // Demo: add to local state only.
      setMetrics((prev) =>
        [...prev, { id: `local-${Date.now()}`, note: input.note ?? null, ...input } as BodyMetric].sort(
          (a, b) => a.measured_on.localeCompare(b.measured_on)
        )
      );
      setForm({ ...EMPTY_FORM, measured_on: form.measured_on });
      return;
    }

    setSaving(true);
    try {
      await createBodyMetric(token, input);
      setForm({ ...EMPTY_FORM, measured_on: form.measured_on });
      refresh();
    } catch {
      setError("Could not save — please try again.");
    } finally {
      setSaving(false);
    }
  };

  const handleDelete = async (id: string) => {
    if (!token) {
      setMetrics((prev) => prev.filter((m) => m.id !== id));
      return;
    }
    try {
      await deleteBodyMetric(token, id);
      refresh();
    } catch {
      // non-critical
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

  // Most-recent-first for the log table.
  const log = [...metrics].sort((a, b) => b.measured_on.localeCompare(a.measured_on));

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      {/* Nav */}
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-3xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link
            href="/"
            className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-sm"
          >
            ← Dashboard
          </Link>
          <span className="text-[var(--text-muted)]">·</span>
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">Body metrics</span>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-6">
        {/* Title */}
        <div className="space-y-1">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">Body metrics</h1>
          <p className="text-[var(--text-secondary)] text-sm">
            {isLive ? "Your data" : "Sample data"} · weight, waist, and blood pressure on the same
            timeline as your biomarkers
          </p>
        </div>

        {/* Not signed in banner */}
        {!session && (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              Showing sample measurements.{" "}
              <Link href="/login" className="text-[var(--color-accent)] hover:underline">
                Sign in
              </Link>{" "}
              to track your own.
            </p>
          </div>
        )}

        {/* Add measurement */}
        <form
          onSubmit={handleSubmit}
          className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-5 shadow-sm space-y-4"
        >
          <h2 className="text-sm font-semibold text-[var(--text-primary)]">Add a measurement</h2>
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <Field label="Date">
              <input
                type="date"
                value={form.measured_on}
                onChange={(e) => set("measured_on", e.target.value || todayIso())}
                className={inputCls}
                required
              />
            </Field>
            <Field label="Weight (kg)">
              <input type="number" step="0.1" min="0" value={form.weight_kg} onChange={(e) => set("weight_kg", e.target.value)} className={inputCls} placeholder="—" />
            </Field>
            <Field label="Waist (cm)">
              <input type="number" step="0.1" min="0" value={form.waist_cm} onChange={(e) => set("waist_cm", e.target.value)} className={inputCls} placeholder="—" />
            </Field>
            <Field label="Systolic (mmHg)">
              <input type="number" step="1" min="0" value={form.systolic} onChange={(e) => set("systolic", e.target.value)} className={inputCls} placeholder="—" />
            </Field>
            <Field label="Diastolic (mmHg)">
              <input type="number" step="1" min="0" value={form.diastolic} onChange={(e) => set("diastolic", e.target.value)} className={inputCls} placeholder="—" />
            </Field>
            <Field label="Note">
              <input type="text" value={form.note} onChange={(e) => set("note", e.target.value)} className={inputCls} placeholder="optional" />
            </Field>
          </div>
          {error && <p className="text-xs text-[var(--color-out-range)]">{error}</p>}
          <button
            type="submit"
            disabled={saving}
            className="text-xs font-medium bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white px-4 py-2 rounded-lg transition-colors"
          >
            {saving ? "Saving…" : "Add measurement"}
          </button>
        </form>

        {/* Trend charts */}
        <div className="space-y-5">
          <BodyMetricChart
            title="Weight"
            unit="kg"
            metrics={metrics}
            lines={[{ field: "weight_kg", label: "Weight", color: "var(--color-accent)" }]}
            annotations={events}
          />
          <BodyMetricChart
            title="Waist"
            unit="cm"
            metrics={metrics}
            lines={[{ field: "waist_cm", label: "Waist", color: "var(--color-accent)" }]}
            annotations={events}
          />
          <BodyMetricChart
            title="Blood pressure"
            unit="mmHg"
            metrics={metrics}
            lines={[
              { field: "systolic", label: "Systolic", color: "var(--color-accent)" },
              { field: "diastolic", label: "Diastolic", color: "var(--color-out-range)" },
            ]}
            guidelines={[
              { value: 120, label: "guideline 120" },
              { value: 80, label: "guideline 80" },
            ]}
            annotations={events}
          />
        </div>

        {/* Log */}
        {log.length > 0 && (
          <div>
            <h2 className="text-xs uppercase tracking-widest text-[var(--text-muted)] mb-2">
              Measurement log
            </h2>
            <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] overflow-hidden shadow-sm divide-y divide-[var(--border-subtle)]">
              {log.map((m) => (
                <div key={m.id} className="flex items-center gap-3 px-4 py-3">
                  <div className="min-w-0 flex-1">
                    <p className="text-sm text-[var(--text-primary)]">{fmtDateLong(m.measured_on)}</p>
                    <p className="text-[11px] text-[var(--text-muted)] font-mono">
                      {m.weight_kg != null && `${m.weight_kg} kg`}
                      {m.weight_kg != null && (m.waist_cm != null || m.systolic != null) && " · "}
                      {m.waist_cm != null && `waist ${m.waist_cm} cm`}
                      {m.waist_cm != null && m.systolic != null && " · "}
                      {m.systolic != null && `BP ${m.systolic}/${m.diastolic} mmHg`}
                      {m.note && <span className="text-[var(--text-secondary)]"> · {m.note}</span>}
                    </p>
                  </div>
                  <button
                    onClick={() => handleDelete(m.id)}
                    className="shrink-0 text-[var(--text-muted)] hover:text-[var(--color-out-range)] transition-colors text-lg leading-none"
                    aria-label={`Delete measurement from ${m.measured_on}`}
                  >
                    ×
                  </button>
                </div>
              ))}
            </div>
          </div>
        )}

        <footer className="border-t border-[var(--border-subtle)] pt-6 pb-4">
          <p className="text-xs text-[var(--text-muted)] text-center">
            Decision-support, not medical advice. Guideline lines are general population references,
            not personalised targets, and the diet-event overlay shows timing only — not cause and
            effect.
          </p>
        </footer>
      </main>
    </div>
  );
}

const inputCls =
  "w-full rounded-lg border border-[var(--border-card)] bg-[var(--bg-elevated)] text-[var(--text-primary)] text-sm px-3 py-1.5 focus:outline-none focus:border-blue-500";

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="flex flex-col gap-1">
      <span className="text-[11px] uppercase tracking-wide text-[var(--text-muted)]">{label}</span>
      {children}
    </label>
  );
}
