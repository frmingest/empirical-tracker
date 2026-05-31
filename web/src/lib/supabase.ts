import { createClient } from "@supabase/supabase-js";

// Browser Supabase client. The anon key is safe to expose; row-level security
// on the database enforces that users only read/write their own data.
// Wired up for use in Sprint 1+ (auth, biomarker data).
const url = process.env.NEXT_PUBLIC_SUPABASE_URL ?? "";
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

export const supabase = createClient(url, anonKey);
