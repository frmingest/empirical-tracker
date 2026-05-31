"use client";

import Link from "next/link";
import { useCallback, useRef, useState } from "react";
import { useAuth } from "@/contexts/AuthContext";

interface ImportResult {
  panels_created: number;
  results_inserted: number;
}

export default function ImportPage() {
  const { session } = useAuth();
  const token = session?.access_token ?? null;

  const fileRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [status, setStatus] = useState<"idle" | "uploading" | "success" | "error">("idle");
  const [result, setResult] = useState<ImportResult | null>(null);
  const [errorMsg, setErrorMsg] = useState("");
  const [confirmDelete, setConfirmDelete] = useState(false);

  const handleFile = useCallback((f: File) => {
    if (!f.name.toLowerCase().endsWith(".xlsx")) {
      setErrorMsg("Only .xlsx files are supported.");
      setStatus("error");
      return;
    }
    setFile(f);
    setStatus("idle");
    setErrorMsg("");
  }, []);

  const onDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault();
      setDragging(false);
      const f = e.dataTransfer.files[0];
      if (f) handleFile(f);
    },
    [handleFile]
  );

  const handleUpload = async () => {
    if (!file || !token) return;
    setStatus("uploading");
    try {
      const form = new FormData();
      form.append("file", file);
      const res = await fetch(
        `${process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000"}/biomarkers/import`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${token}` },
          body: form,
        }
      );
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const data = (await res.json()) as ImportResult;
      setResult(data);
      setStatus("success");
    } catch (err) {
      setErrorMsg(err instanceof Error ? err.message : "Upload failed");
      setStatus("error");
    }
  };

  const handleDeleteAll = async () => {
    if (!token) return;
    try {
      await fetch(
        `${process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8000"}/biomarkers/import`,
        {
          method: "DELETE",
          headers: { Authorization: `Bearer ${token}` },
        }
      );
      setConfirmDelete(false);
      setFile(null);
      setResult(null);
      setStatus("idle");
    } catch {
      setErrorMsg("Delete failed — check your connection.");
      setStatus("error");
      setConfirmDelete(false);
    }
  };

  return (
    <div className="min-h-screen bg-[var(--bg-base)]">
      <header className="sticky top-0 z-40 border-b border-[var(--border-subtle)] bg-[var(--bg-base)]/90 backdrop-blur-md">
        <div className="max-w-2xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link href="/" className="text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors text-sm">
            ← Dashboard
          </Link>
          <span className="text-[var(--border-card)]">·</span>
          <span className="text-xs text-[var(--text-muted)] uppercase tracking-wide">Import</span>
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-4 sm:px-6 py-10 space-y-8">
        <div>
          <h1 className="text-xl font-semibold text-[var(--text-primary)] mb-1">
            Import blood test data
          </h1>
          <p className="text-sm text-[var(--text-secondary)]">
            Upload your lab results spreadsheet. Supports the Norwegian blood panel
            format with bilingual names and reference ranges.
          </p>
        </div>

        {/* Auth gate */}
        {!token && (
          <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 px-5 py-4">
            <p className="text-amber-600 text-sm">
              You need to{" "}
              <Link href="/login" className="underline underline-offset-2 hover:text-amber-500">
                sign in
              </Link>{" "}
              before you can import data.
            </p>
          </div>
        )}

        {/* Format hint */}
        <div className="rounded-xl border border-[var(--border-card)] bg-[var(--bg-card)] px-5 py-4 shadow-sm">
          <p className="text-xs text-[var(--text-muted)] uppercase tracking-wider mb-3">Expected format</p>
          <ul className="space-y-1.5 text-sm text-[var(--text-secondary)]">
            <li className="flex gap-2">
              <span className="text-[var(--text-muted)]">·</span>
              Row 1: col A = biomarker name, col B = reference range, cols C+ = test dates
            </li>
            <li className="flex gap-2">
              <span className="text-[var(--text-muted)]">·</span>
              Dates as <span className="font-mono text-[var(--text-primary)]">DD.MM.YYYY</span>
            </li>
            <li className="flex gap-2">
              <span className="text-[var(--text-muted)]">·</span>
              Norwegian decimal commas (<span className="font-mono text-[var(--text-primary)]">4,5</span>) handled automatically
            </li>
          </ul>
        </div>

        {/* Drop zone */}
        <div
          onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
          onDragLeave={() => setDragging(false)}
          onDrop={onDrop}
          onClick={() => fileRef.current?.click()}
          className={`cursor-pointer rounded-2xl border-2 border-dashed p-10 text-center transition-all duration-200 ${
            dragging
              ? "border-blue-500 bg-blue-500/5 scale-[1.01]"
              : file
                ? "border-emerald-500 bg-emerald-500/5"
                : "border-[var(--border-card)] hover:border-[var(--border-subtle)] bg-[var(--bg-elevated)]"
          }`}
        >
          <input
            ref={fileRef}
            type="file"
            accept=".xlsx"
            onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); }}
            className="hidden"
          />
          <div className="text-3xl mb-3 text-[var(--text-muted)]">↑</div>
          {file ? (
            <>
              <p className="text-emerald-600 font-mono text-sm">{file.name}</p>
              <p className="text-[var(--text-muted)] text-xs mt-1">
                {(file.size / 1024).toFixed(1)} KB — click to change
              </p>
            </>
          ) : (
            <>
              <p className="text-[var(--text-secondary)] text-sm">
                Drop your <span className="font-mono text-[var(--text-primary)]">.xlsx</span> file here
              </p>
              <p className="text-[var(--text-muted)] text-xs mt-1">or click to browse</p>
            </>
          )}
        </div>

        {status === "success" && result && (
          <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 px-5 py-4">
            <p className="text-emerald-600 font-semibold text-sm mb-1">Import complete</p>
            <p className="text-emerald-600/70 text-sm font-mono">
              {result.panels_created} panels · {result.results_inserted} results
            </p>
          </div>
        )}

        {status === "error" && (
          <div className="rounded-xl border border-rose-500/20 bg-rose-500/5 px-5 py-4">
            <p className="text-rose-500 text-sm">{errorMsg}</p>
          </div>
        )}

        <button
          onClick={handleUpload}
          disabled={!file || !token || status === "uploading"}
          className="w-full rounded-xl bg-blue-600 hover:bg-blue-500 disabled:bg-[var(--bg-elevated)] disabled:text-[var(--text-muted)] text-white font-semibold py-3 text-sm transition-colors"
        >
          {!token
            ? "Sign in to import"
            : status === "uploading"
              ? "Uploading…"
              : "Import file"}
        </button>

        {token && (
          <div className="border-t border-[var(--border-subtle)] pt-6">
            <p className="text-xs text-[var(--text-muted)] uppercase tracking-wider mb-3">Danger zone</p>
            {!confirmDelete ? (
              <button
                onClick={() => setConfirmDelete(true)}
                className="text-sm text-[var(--text-muted)] hover:text-rose-500 transition-colors border border-[var(--border-card)] hover:border-rose-500/30 rounded-lg px-4 py-2"
              >
                Delete all imported data
              </button>
            ) : (
              <div className="rounded-xl border border-rose-500/30 bg-rose-500/5 p-5 space-y-3">
                <p className="text-rose-500 text-sm">
                  Permanently deletes all your panels and results. Cannot be undone.
                </p>
                <div className="flex gap-3">
                  <button
                    onClick={() => setConfirmDelete(false)}
                    className="flex-1 text-sm py-2 rounded-lg border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleDeleteAll}
                    className="flex-1 text-sm py-2 rounded-lg border border-rose-500/50 text-rose-500 hover:bg-rose-500/10 transition-colors"
                  >
                    Delete everything
                  </button>
                </div>
              </div>
            )}
          </div>
        )}
      </main>
    </div>
  );
}
