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
    <div className="min-h-screen bg-[#09090b]">
      <header className="sticky top-0 z-40 border-b border-zinc-900 bg-[#09090b]/90 backdrop-blur-md">
        <div className="max-w-2xl mx-auto px-4 sm:px-6 h-14 flex items-center gap-3">
          <Link href="/" className="text-zinc-500 hover:text-zinc-300 transition-colors text-sm">
            ← Dashboard
          </Link>
          <span className="text-zinc-800">·</span>
          <span className="text-xs text-zinc-600 uppercase tracking-wide">Import</span>
        </div>
      </header>

      <main className="max-w-2xl mx-auto px-4 sm:px-6 py-10 space-y-8">
        <div>
          <h1 className="text-xl font-semibold text-zinc-100 mb-1">
            Import blood test data
          </h1>
          <p className="text-sm text-zinc-500">
            Upload your lab results spreadsheet. Supports the Norwegian blood panel
            format with bilingual names and reference ranges.
          </p>
        </div>

        {/* Auth gate */}
        {!token && (
          <div className="rounded-xl border border-amber-500/20 bg-amber-500/5 px-5 py-4">
            <p className="text-amber-300 text-sm">
              You need to{" "}
              <Link href="/login" className="underline underline-offset-2 hover:text-amber-200">
                sign in
              </Link>{" "}
              before you can import data.
            </p>
          </div>
        )}

        {/* Format hint */}
        <div className="rounded-xl border border-zinc-800 bg-zinc-900/50 px-5 py-4">
          <p className="text-xs text-zinc-500 uppercase tracking-wider mb-3">Expected format</p>
          <ul className="space-y-1.5 text-sm text-zinc-400">
            <li className="flex gap-2">
              <span className="text-zinc-700">·</span>
              Row 1: col A = biomarker name, col B = reference range, cols C+ = test dates
            </li>
            <li className="flex gap-2">
              <span className="text-zinc-700">·</span>
              Dates as <span className="font-mono text-zinc-300">DD.MM.YYYY</span>
            </li>
            <li className="flex gap-2">
              <span className="text-zinc-700">·</span>
              Norwegian decimal commas (<span className="font-mono text-zinc-300">4,5</span>) handled automatically
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
                ? "border-emerald-600 bg-emerald-500/5"
                : "border-zinc-800 hover:border-zinc-700 bg-zinc-900/30"
          }`}
        >
          <input
            ref={fileRef}
            type="file"
            accept=".xlsx"
            onChange={(e) => { const f = e.target.files?.[0]; if (f) handleFile(f); }}
            className="hidden"
          />
          <div className="text-3xl mb-3 text-zinc-700">↑</div>
          {file ? (
            <>
              <p className="text-emerald-400 font-mono text-sm">{file.name}</p>
              <p className="text-zinc-600 text-xs mt-1">
                {(file.size / 1024).toFixed(1)} KB — click to change
              </p>
            </>
          ) : (
            <>
              <p className="text-zinc-400 text-sm">
                Drop your <span className="font-mono text-zinc-200">.xlsx</span> file here
              </p>
              <p className="text-zinc-700 text-xs mt-1">or click to browse</p>
            </>
          )}
        </div>

        {status === "success" && result && (
          <div className="rounded-xl border border-emerald-500/20 bg-emerald-500/5 px-5 py-4">
            <p className="text-emerald-400 font-semibold text-sm mb-1">Import complete</p>
            <p className="text-emerald-300/70 text-sm font-mono">
              {result.panels_created} panels · {result.results_inserted} results
            </p>
          </div>
        )}

        {status === "error" && (
          <div className="rounded-xl border border-rose-500/20 bg-rose-500/5 px-5 py-4">
            <p className="text-rose-400 text-sm">{errorMsg}</p>
          </div>
        )}

        <button
          onClick={handleUpload}
          disabled={!file || !token || status === "uploading"}
          className="w-full rounded-xl bg-blue-600 hover:bg-blue-500 disabled:bg-zinc-800 disabled:text-zinc-600 text-white font-semibold py-3 text-sm transition-colors"
        >
          {!token
            ? "Sign in to import"
            : status === "uploading"
              ? "Uploading…"
              : "Import file"}
        </button>

        {token && (
          <div className="border-t border-zinc-900 pt-6">
            <p className="text-xs text-zinc-700 uppercase tracking-wider mb-3">Danger zone</p>
            {!confirmDelete ? (
              <button
                onClick={() => setConfirmDelete(true)}
                className="text-sm text-zinc-600 hover:text-rose-400 transition-colors border border-zinc-800 hover:border-rose-500/30 rounded-lg px-4 py-2"
              >
                Delete all imported data
              </button>
            ) : (
              <div className="rounded-xl border border-rose-500/30 bg-rose-500/5 p-5 space-y-3">
                <p className="text-rose-300 text-sm">
                  Permanently deletes all your panels and results. Cannot be undone.
                </p>
                <div className="flex gap-3">
                  <button
                    onClick={() => setConfirmDelete(false)}
                    className="flex-1 text-sm py-2 rounded-lg border border-zinc-700 text-zinc-400 hover:text-zinc-200 transition-colors"
                  >
                    Cancel
                  </button>
                  <button
                    onClick={handleDeleteAll}
                    className="flex-1 text-sm py-2 rounded-lg border border-rose-500/50 text-rose-400 hover:bg-rose-500/10 transition-colors"
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
