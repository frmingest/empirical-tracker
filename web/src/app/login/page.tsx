"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabase, isSupabaseConfigured } from "@/lib/supabase";

// ── Config error screen shown when env vars weren't set at build time ─────────
function NotConfigured() {
  return (
    <div className="min-h-screen bg-[#09090b] flex items-center justify-center px-4">
      <div className="w-full max-w-md space-y-5">
        <div className="text-center">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </h1>
        </div>
        <div className="rounded-2xl border border-amber-500/20 bg-amber-500/5 p-6 space-y-4">
          <div className="flex items-start gap-3">
            <span className="text-amber-400 text-lg mt-0.5">⚠</span>
            <div>
              <h2 className="text-sm font-semibold text-amber-300 mb-1">
                Supabase not configured
              </h2>
              <p className="text-xs text-zinc-400 leading-relaxed">
                The Supabase environment variables were not set when this app was
                built. Add them in Railway and redeploy.
              </p>
            </div>
          </div>

          <div className="rounded-lg bg-zinc-950 border border-zinc-800 p-4 space-y-2 font-mono text-xs">
            <p className="text-zinc-500 mb-2"># Railway → Web service → Variables</p>
            <p>
              <span className="text-blue-400">NEXT_PUBLIC_SUPABASE_URL</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">https://xxxx.supabase.co</span>
            </p>
            <p>
              <span className="text-blue-400">NEXT_PUBLIC_SUPABASE_ANON_KEY</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">eyJhbGciOiJIUzI1NiIs…</span>
            </p>
            <p>
              <span className="text-blue-400">NEXT_PUBLIC_API_URL</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">https://api-xxx.up.railway.app</span>
            </p>
          </div>

          <div className="rounded-lg bg-zinc-950 border border-zinc-800 p-4 space-y-2 font-mono text-xs">
            <p className="text-zinc-500 mb-2"># Railway → API service → Variables</p>
            <p>
              <span className="text-blue-400">SUPABASE_URL</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">https://xxxx.supabase.co</span>
            </p>
            <p>
              <span className="text-blue-400">SUPABASE_SERVICE_KEY</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">eyJhbGciOiJIUzI1NiIs…</span>
            </p>
            <p>
              <span className="text-blue-400">CORS_ORIGINS</span>
              <span className="text-zinc-600"> = </span>
              <span className="text-emerald-400">https://web-xxx.up.railway.app</span>
            </p>
          </div>

          <p className="text-xs text-zinc-500">
            After adding variables, click{" "}
            <span className="text-zinc-300 font-mono">Deploy</span> in Railway to
            rebuild with the new values.{" "}
            <span className="text-zinc-600">
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
      // Surface a clearer message for the "Invalid path" Supabase error
      setError(
        msg.includes("Invalid path") || msg.includes("fetch")
          ? "Cannot reach Supabase — check NEXT_PUBLIC_SUPABASE_URL is set correctly and redeploy."
          : msg
      );
    } finally {
      setLoading(false);
    }
  };

  if (signupDone) {
    return (
      <div className="min-h-screen bg-[#09090b] flex items-center justify-center px-4">
        <div className="w-full max-w-sm text-center space-y-4">
          <div className="w-12 h-12 rounded-full bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center mx-auto text-emerald-400 text-xl">
            ✓
          </div>
          <h2 className="text-base font-semibold text-zinc-100">Check your email</h2>
          <p className="text-sm text-zinc-500">
            Confirmation link sent to{" "}
            <span className="text-zinc-300">{email}</span>. Click it to activate
            your account, then sign in here.
          </p>
          <button
            onClick={() => { setMode("login"); setSignupDone(false); }}
            className="text-sm text-blue-400 hover:text-blue-300 transition-colors"
          >
            Back to sign in →
          </button>
        </div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-[#09090b] flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold bg-gradient-to-r from-blue-400 to-emerald-400 bg-clip-text text-transparent">
            Empirical
          </h1>
          <p className="text-zinc-600 text-sm mt-1">Blood biomarkers over time</p>
        </div>

        <div className="rounded-2xl border border-zinc-800 bg-zinc-900 p-6">
          <h2 className="text-sm font-semibold text-zinc-300 mb-5">
            {mode === "login" ? "Sign in to your account" : "Create an account"}
          </h2>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="block text-xs text-zinc-500 mb-1.5">Email</label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                placeholder="you@example.com"
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2.5 text-sm text-zinc-100 placeholder-zinc-700 focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            <div>
              <label className="block text-xs text-zinc-500 mb-1.5">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                autoComplete={mode === "login" ? "current-password" : "new-password"}
                placeholder="••••••••"
                className="w-full bg-zinc-950 border border-zinc-800 rounded-lg px-3 py-2.5 text-sm text-zinc-100 placeholder-zinc-700 focus:outline-none focus:border-blue-500 transition-colors"
              />
            </div>

            {error && (
              <div className="rounded-lg bg-rose-500/10 border border-rose-500/20 px-3 py-2.5">
                <p className="text-rose-400 text-xs leading-relaxed">{error}</p>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full rounded-lg bg-blue-600 hover:bg-blue-500 disabled:bg-zinc-800 disabled:text-zinc-600 text-white font-semibold py-2.5 text-sm transition-colors"
            >
              {loading
                ? "…"
                : mode === "login"
                  ? "Sign in"
                  : "Create account"}
            </button>
          </form>

          <p className="text-center text-xs text-zinc-600 mt-4">
            {mode === "login" ? (
              <>
                No account?{" "}
                <button
                  onClick={() => { setMode("signup"); setError(""); }}
                  className="text-blue-400 hover:text-blue-300 transition-colors"
                >
                  Create one
                </button>
              </>
            ) : (
              <>
                Already have an account?{" "}
                <button
                  onClick={() => { setMode("login"); setError(""); }}
                  className="text-blue-400 hover:text-blue-300 transition-colors"
                >
                  Sign in
                </button>
              </>
            )}
          </p>
        </div>

        <p className="text-center text-xs text-zinc-700 mt-5">
          Health data stored in EU · GDPR special-category
        </p>
      </div>
    </div>
  );
}
