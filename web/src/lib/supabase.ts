import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

// createClient throws if URL is falsy, so fall back to a valid placeholder during
// build time or when env vars aren't set. Auth calls will fail gracefully at runtime.
export const supabase = createClient(
  url ?? "https://placeholder.supabase.co",
  anonKey ?? "placeholder-anon-key"
);

/** True only when real credentials are configured. */
export const isSupabaseConfigured = Boolean(url && anonKey);
