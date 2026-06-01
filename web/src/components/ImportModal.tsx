"use client";

import { useCallback, useId, useRef, useState } from "react";
import Link from "next/link";
import { useModalA11y } from "@/lib/useModalA11y";

interface ImportResult {
  panels_created: number;
  results_inserted: number;
}

interface Props {
  onClose: () => void;
  token: string | null;
  onSuccess?: () => void;
}

export function ImportModal({ onClose, token, onSuccess }: Props) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [dragging, setDragging] = useState(false);
  const [file, setFile] = useState<File | null>(null);
  const [status, setStatus] = useState<"idle" | "uploading" | "success" | "error">("idle");
  const [result, setResult] = useState<ImportResult | null>(null);
  const [errorMsg, setErrorMsg] = useState<string>("");
  const [confirmDelete, setConfirmDelete] = useState(false);
  const dialogRef = useModalA11y<HTMLDivElement>(onClose);
  const titleId = useId();

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
    if (!file) return;
    if (!token) {
      setErrorMsg("You need to sign in before importing data.");
      setStatus("error");
      return;
    }
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
      onSuccess?.();
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
      onSuccess?.();
      onClose();
    } catch {
      setErrorMsg("Delete failed — check your connection.");
      setStatus("error");
      setConfirmDelete(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
      onClick={(e) => e.target === e.currentTarget && onClose()}
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="w-full max-w-md rounded-2xl border border-[var(--border-card)] bg-[var(--bg-surface)] shadow-2xl focus:outline-none"
      >
        {/* Header */}
        <div className="flex items-center justify-between px-6 pt-6 pb-4 border-b border-[var(--border-subtle)]">
          <h2 id={titleId} className="text-base font-semibold text-[var(--text-primary)]">
            Import blood test data
          </h2>
          <button
            onClick={onClose}
            aria-label="Close"
            className="text-[var(--text-muted)] hover:text-[var(--text-primary)] transition-colors text-xl leading-none"
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
                to import your data.
              </p>
            </div>
          )}

          {/* Drop zone */}
          <div
            onDragOver={(e) => { e.preventDefault(); setDragging(true); }}
            onDragLeave={() => setDragging(false)}
            onDrop={onDrop}
            onClick={() => fileRef.current?.click()}
            className={`cursor-pointer rounded-xl border-2 border-dashed p-8 text-center transition-colors ${
              dragging
                ? "border-blue-500 bg-blue-500/5"
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
            {file ? (
              <>
                <p className="text-emerald-600 text-sm font-mono">{file.name}</p>
                <p className="text-[var(--text-muted)] text-xs mt-1">
                  {(file.size / 1024).toFixed(1)} KB — click to change
                </p>
              </>
            ) : (
              <>
                <p className="text-[var(--text-secondary)] text-sm">
                  Drop your{" "}
                  <span className="font-mono text-[var(--text-primary)]">.xlsx</span> file here
                </p>
                <p className="text-[var(--text-muted)] text-xs mt-1">or click to browse</p>
              </>
            )}
          </div>

          {/* Result */}
          {status === "success" && result && (
            <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/20 px-4 py-3">
              <p className="text-emerald-600 text-sm font-mono">
                ✓ {result.panels_created} panels · {result.results_inserted} results imported
              </p>
            </div>
          )}
          {status === "error" && (
            <div className="rounded-lg bg-rose-500/10 border border-rose-500/20 px-4 py-3">
              <p className="text-rose-500 text-sm">{errorMsg}</p>
            </div>
          )}

          <button
            onClick={handleUpload}
            disabled={!file || !token || status === "uploading"}
            className="w-full rounded-lg bg-[var(--btn-accent)] hover:bg-[var(--btn-accent-hover)] disabled:bg-[var(--bg-elevated)] disabled:text-[var(--text-muted)] text-[var(--btn-accent-text)] text-sm font-semibold py-2.5 transition-colors"
          >
            {status === "uploading" ? "Uploading…" : "Import file"}
          </button>

          {token && (
            <div className="border-t border-[var(--border-subtle)] pt-4">
              {!confirmDelete ? (
                <button
                  onClick={() => setConfirmDelete(true)}
                  className="w-full text-xs text-[var(--text-muted)] hover:text-rose-500 transition-colors py-1"
                >
                  Delete all imported data
                </button>
              ) : (
                <div className="rounded-lg border border-rose-500/30 bg-rose-500/5 p-3">
                  <p className="text-xs text-rose-500 mb-3 text-center">
                    Permanently deletes all panels and results.
                  </p>
                  <div className="flex gap-2">
                    <button
                      onClick={() => setConfirmDelete(false)}
                      className="flex-1 text-xs py-1.5 rounded border border-[var(--border-card)] text-[var(--text-secondary)] hover:text-[var(--text-primary)] transition-colors"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleDeleteAll}
                      className="flex-1 text-xs py-1.5 rounded border border-rose-500/50 text-rose-500 hover:bg-rose-500/10 transition-colors"
                    >
                      Delete all
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
