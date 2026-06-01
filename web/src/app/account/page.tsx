"use client";

import { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useAuth } from "@/contexts/AuthContext";
import { deleteAccount, exportAccountData } from "@/lib/api";

const CONFIRM_PHRASE = "DELETE";

function triggerDownload(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

function todayStamp(): string {
  return new Date().toISOString().slice(0, 10).replace(/-/g, "");
}

export default function AccountPage() {
  const { session, loading, signOut } = useAuth();
  const router = useRouter();
  const token = session?.access_token ?? null;

  const [busy, setBusy] = useState<null | "json" | "csv" | "delete">(null);
  const [error, setError] = useState<string | null>(null);
  const [confirm, setConfirm] = useState("");

  const onExport = async (format: "json" | "csv") => {
    if (!token) return;
    setError(null);
    setBusy(format);
    try {
      const blob = await exportAccountData(token, format);
      const ext = format === "csv" ? "zip" : "json";
      triggerDownload(blob, `empirical-export-${todayStamp()}.${ext}`);
    } catch {
      setError("Export failed. Please try again.");
    } finally {
      setBusy(null);
    }
  };

  const onDelete = async () => {
    if (!token || confirm !== CONFIRM_PHRASE) return;
    setError(null);
    setBusy("delete");
    try {
      await deleteAccount(token);
      await signOut();
      router.push("/login");
    } catch {
      setError("Account deletion failed. Please try again.");
      setBusy(null);
    }
  };

  if (loading) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center">
        <div className="w-5 h-5 border-2 border-[var(--border-card)] border-t-blue-400 rounded-full animate-spin" />
      </div>
    );
  }

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
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">
            Account
          </span>
        </div>
      </header>

      <main className="max-w-3xl mx-auto px-4 sm:px-6 py-8 space-y-8">
        <div className="space-y-1">
          <h1 className="text-2xl font-bold tracking-tight text-[var(--text-primary)]">
            Account &amp; data
          </h1>
          <p className="text-[var(--text-secondary)] text-sm">
            Export or permanently delete the health data stored for your account.
          </p>
        </div>

        {!session ? (
          <div className="rounded-xl border border-blue-500/20 bg-blue-500/5 px-4 py-3">
            <p className="text-sm text-[var(--text-secondary)]">
              <Link href="/login" className="text-[var(--color-accent)] hover:underline">
                Sign in
              </Link>{" "}
              to export or delete your data.
            </p>
          </div>
        ) : (
          <>
            {error && (
              <div className="rounded-lg border border-red-500/30 bg-red-500/5 px-4 py-3 text-sm text-red-400">
                {error}
              </div>
            )}

            <section className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-5 space-y-3">
              <div className="flex items-center justify-between gap-2">
                <span className="text-sm text-[var(--text-muted)]">Signed in as</span>
                <span className="text-sm text-[var(--text-primary)] truncate">
                  {session.user.email}
                </span>
              </div>
            </section>

            {/* Export */}
            <section className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] p-5 space-y-3">
              <div className="space-y-1">
                <h2 className="text-base font-semibold text-[var(--text-primary)]">
                  Export your data
                </h2>
                <p className="text-sm text-[var(--text-secondary)]">
                  Download everything stored for your account — blood panels,
                  results, diet events, food diary and meal plans. JSON is one
                  machine-readable file; CSV is a zip with one spreadsheet per table.
                </p>
              </div>
              <div className="flex flex-wrap gap-2 pt-1">
                <button
                  onClick={() => onExport("json")}
                  disabled={busy !== null}
                  className="text-sm font-medium bg-blue-600 hover:bg-blue-500 disabled:opacity-50 text-white px-4 py-2 rounded-lg transition-colors"
                >
                  {busy === "json" ? "Preparing…" : "Download JSON"}
                </button>
                <button
                  onClick={() => onExport("csv")}
                  disabled={busy !== null}
                  className="text-sm font-medium border border-[var(--border-card)] hover:bg-[var(--bg-hover)] disabled:opacity-50 text-[var(--text-primary)] px-4 py-2 rounded-lg transition-colors"
                >
                  {busy === "csv" ? "Preparing…" : "Download CSV (zip)"}
                </button>
              </div>
            </section>

            {/* Danger zone */}
            <section className="rounded-xl border border-red-500/30 bg-red-500/5 p-5 space-y-3">
              <div className="space-y-1">
                <h2 className="text-base font-semibold text-red-400">
                  Delete account
                </h2>
                <p className="text-sm text-[var(--text-secondary)]">
                  Permanently erase your account and all associated health data.
                  This cannot be undone. Consider exporting your data first. Type{" "}
                  <span className="font-mono font-semibold text-[var(--text-primary)]">
                    {CONFIRM_PHRASE}
                  </span>{" "}
                  to confirm.
                </p>
              </div>
              <input
                type="text"
                value={confirm}
                onChange={(e) => setConfirm(e.target.value)}
                placeholder={CONFIRM_PHRASE}
                aria-label={`Type ${CONFIRM_PHRASE} to confirm`}
                className="w-full sm:w-48 rounded-lg border border-[var(--border-card)] bg-[var(--bg-base)] px-3 py-2 text-sm text-[var(--text-primary)] outline-none focus:border-red-500/60"
              />
              <div>
                <button
                  onClick={onDelete}
                  disabled={busy !== null || confirm !== CONFIRM_PHRASE}
                  className="text-sm font-medium bg-red-600 hover:bg-red-500 disabled:opacity-40 disabled:cursor-not-allowed text-white px-4 py-2 rounded-lg transition-colors"
                >
                  {busy === "delete" ? "Deleting…" : "Delete my account"}
                </button>
              </div>
            </section>
          </>
        )}
      </main>
    </div>
  );
}
