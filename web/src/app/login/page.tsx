"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase, isSupabaseConfigured } from "@/lib/supabase";

// ── Config error screen shown when env vars weren't set at build time ─────────
function NotConfigured() {
  return (
    <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center px-4">
      <div className="w-full max-w-md space-y-5">
        <div className="text-center">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </h1>
        </div>
        <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-6 space-y-4">
          <div className="flex items-start gap-3">
            <span className="text-amber-500 text-lg mt-0.5">⚠</span>
            <div>
              <h2 className="text-sm font-semibold text-amber-600 mb-1">
                Supabase not configured
              </h2>
              <p className="text-xs text-[var(--text-secondary)] leading-relaxed">
                The Supabase environment variables were not set when this app was
                built. Add them in Railway and redeploy.
              </p>
            </div>
          </div>

          <div className="rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-subtle)] p-4 space-y-2 font-mono text-xs">
            <p className="text-[var(--text-muted)] mb-2"># Railway → Web service → Variables</p>
            <p>
              <span className="text-blue-500">NEXT_PUBLIC_SUPABASE_URL</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">https://xxxx.supabase.co</span>
            </p>
            <p>
              <span className="text-blue-500">NEXT_PUBLIC_SUPABASE_ANON_KEY</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">eyJhbGciOiJIUzI1NiIs…</span>
            </p>
            <p>
              <span className="text-blue-500">NEXT_PUBLIC_API_URL</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">https://api-xxx.up.railway.app</span>
            </p>
          </div>

          <div className="rounded-lg bg-[var(--bg-elevated)] border border-[var(--border-subtle)] p-4 space-y-2 font-mono text-xs">
            <p className="text-[var(--text-muted)] mb-2"># Railway → API service → Variables</p>
            <p>
              <span className="text-blue-500">SUPABASE_URL</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">https://xxxx.supabase.co</span>
            </p>
            <p>
              <span className="text-blue-500">SUPABASE_SERVICE_KEY</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">eyJhbGciOiJIUzI1NiIs…</span>
            </p>
            <p>
              <span className="text-blue-500">CORS_ORIGINS</span>
              <span className="text-[var(--text-muted)]"> = </span>
              <span className="text-emerald-600">https://web-xxx.up.railway.app</span>
            </p>
          </div>

          <p className="text-xs text-[var(--text-secondary)]">
            After adding variables, click{" "}
            <span className="text-[var(--text-primary)] font-mono">Deploy</span> in Railway to
            rebuild with the new values.{" "}
            <span className="text-[var(--text-muted)]">
              Next.js bakes NEXT_PUBLIC_* at build time.
            </span>
          </p>
        </div>
      </div>
    </div>
  );
}

// ── Login / signup form ───────────────────────────────────────────────────────
export default function LoginPage() {
  if (!isSupabaseConfigured) return <NotConfigured />;

  return <AuthForm />;
}

function AuthForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [mode, setMode] = useState<"login" | "signup">("login");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const [signupDone, setSignupDone] = useState(false);
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    try {
      if (mode === "login") {
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) throw error;
        router.push("/");
        router.refresh();
      } else {
        const { error } = await supabase.auth.signUp({ email, password });
        if (error) throw error;
        setSignupDone(true);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : "Authentication failed";
      // Log full error so it appears in Railway/browser console for debugging
      console.error("[Auth error]", err);
      setError(
        msg.toLowerCase().includes("failed to fetch") || msg.toLowerCase().includes("networkerror") || msg.includes("Invalid path")
          ? `Cannot reach Supabase (network error). Open DevTools → Network tab and retry to see the raw request. Detail: ${msg}`
          : msg
      );
    } finally {
      setLoading(false);
    }
  };

  if (signupDone) {
    return (
      <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center px-4">
        <div className="w-full max-w-sm text-center space-y-4">
          <div className="w-12 h-12 rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center mx-auto text-emerald-600 text-xl">
            ✓
          </div>
          <h2 className="text-base font-semibold text-[var(--text-primary)]">Check your email</h2>
          <p className="text-sm text-[var(--text-secondary)]">
            Confirmation link sent to{" "}
            <span className="text-[var(--text-primary)]">{email}</span>. Click it to activate
            your account, then sign in here.
          </p>
          <button
            onClick={() => { setMode("login"); setSignupDone(false); }}
            className="text-sm text-blue-500 hover:text-blue-400 transition-colors"
          >
            Back to sign in →
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[var(--bg-base)] flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </h1>
          <p className="text-[var(--text-muted)] text-sm mt-1">Blood biomarkers over time</p>
        </div>

        <div className="rounded-2xl border border-[var(--border-card)] bg-[var(--bg-card)] p-6 shadow-sm">
          <h2 className="text-sm font-semibold text-[var(--text-primary)] mb-5">
            {mode === "login" ? "Sign in to your account" : "Create an account"}
          </h2>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs text-[var(--text-secondary)] mb-1.5">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                placeholder="you@example.com"
                className="w-full bg-[var(--bg-elevated)] border border-[var(--border-card)] rounded-lg px-3 py-2.5 text-sm text-[var(--text-primary)] placeholder-[var(--text-muted)] focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            <div>
              <label className="block text-xs text-[var(--text-secondary)] mb-1.5">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                autoComplete={mode === "login" ? "current-password" : "new-password"}
                placeholder="••••••••"
                className="w-full bg-[var(--bg-elevated)] border border-[var(--border-card)] rounded-lg px-3 py-2.5 text-sm text-[var(--text-primary)] placeholder-[var(--text-muted)] focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            {error && (
              <div className="rounded-lg bg-rose-500/10 border border-rose-500/20 px-3 py-2.5">
                <p className="text-rose-500 text-xs leading-relaxed">{error}</p>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-lg bg-blue-600 hover:bg-blue-500 disabled:bg-[var(--bg-elevated)] disabled:text-[var(--text-muted)] text-white font-semibold py-2.5 text-sm transition-colors"
            >
              {loading
                ? "…"
                : mode === "login"
                  ? "Sign in"
                  : "Create account"}
            </button>
          </form>

          <p className="text-center text-xs text-[var(--text-muted)] mt-4">
            {mode === "login" ? (
              <>
                No account?{" "}
                <button
                  onClick={() => { setMode("signup"); setError(""); }}
                  className="text-blue-500 hover:text-blue-400 transition-colors"
                >
                  Create one
                </button>
              </>
            ) : (
              <>
                Already have an account?{" "}
                <button
                  onClick={() => { setMode("login"); setError(""); }}
                  className="text-blue-500 hover:text-blue-400 transition-colors"
                >
                  Sign in
                </button>
              </>
            )}
          </p>
        </div>

        <p className="text-center text-xs text-[var(--text-muted)] mt-5">
          Health data stored in EU · GDPR special-category
        </p>
      </div>
    </div>
  );
}
