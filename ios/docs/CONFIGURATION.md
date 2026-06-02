# Backend Configuration — Railway + Supabase

> The iOS app is a **pure client** of the existing FastAPI + Supabase backend.
> Nothing works end-to-end until these coordinates are set. This doc is the
> checklist to verify the app is wired to the right backend after the web→iOS port.

## Why this matters (two symptoms it explains)

| Symptom | Root cause |
|---|---|
| "I log in but only see `demo@empirical.app`, not my own profile." | Supabase keys are **not set**, so `AppConfig` silently falls back to `MockAuthService`, which accepts any login and returns a hardcoded demo session. |
| "Import fails with *Requested resource not found*." | That's an HTTP **404** from the configured API base URL — the Railway URL is wrong/not deployed, or the `POST /biomarkers/import` route isn't reachable at that base. |

## How configuration flows

```
Config.xcconfig  ──►  build settings  ──►  Info.plist ($(SUPABASE_URL) …)  ──►  AppConfig  ──►  SupabaseAuthService
EMPIRICAL_API_URL (scheme env / Info.plist)  ──►  APIClient.Configuration.resolved()  ──►  all REST calls
```

- **Supabase** (auth): `Info.plist` keys `SupabaseURL` / `SupabaseAnonKey`, fed from
  `SUPABASE_URL` / `SUPABASE_ANON_KEY` build settings.
- **Railway API** (data): `APIClient` reads `EMPIRICAL_API_URL` from the process
  environment, falling back to the hardcoded `https://api-empirical.up.railway.app`.

## Setup

1. `cp Config.xcconfig.example Config.xcconfig`
2. Fill in `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `EMPIRICAL_API_URL`.
3. Xcode ▸ project ▸ **Info ▸ Configurations** ▸ set `Config.xcconfig` for the
   `EmpiricalTracker` target (Debug **and** Release).
4. For `EMPIRICAL_API_URL`: add it as an environment variable in the **Run scheme**
   (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments), since `APIClient` currently
   reads it from the process environment rather than `Info.plist`.
5. Clean build folder (⇧⌘K), rebuild on device.

> `Config.xcconfig` is git-ignored. The Supabase **anon** key is a public client
> key and is safe to ship; the **service-role** key must never appear in the app.

---

## Control questions (verify your setup)

### A. Supabase (auth / profile)
1. In the Supabase dashboard ▸ Settings ▸ API, what is the **Project URL**? Does it
   exactly match `SUPABASE_URL` in `Config.xcconfig` (including `https://` and `.supabase.co`)?
2. Is the key in `SUPABASE_ANON_KEY` the **anon/public** key — not the service-role key?
3. Is this the **same** Supabase project the web app uses? (After a port, people
   sometimes spin up a new project and the data lives in the old one.)
4. Does your user account actually exist in **this** project's `auth.users`? Try
   signing in on the web app pointed at the same project to confirm.
5. After building with keys set, does the **Settings tab still show the orange
   "Demo mode — backend not configured" banner**? If yes, the keys aren't resolving
   (check that `Config.xcconfig` is actually assigned to the target, then clean-build).
6. Does Settings show **your** email after login, not `demo@empirical.app`?

### B. Railway (REST API / import + data)
7. What is the **public Railway URL** of the FastAPI service, and is it currently
   deployed and healthy (open it in a browser — `/docs` or `/health` should respond)?
8. Does `EMPIRICAL_API_URL` exactly match that URL? Is the default
   `https://api-empirical.up.railway.app` even correct for your deployment?
9. Do the FastAPI routes live at the **root** (`/biomarkers/import`) or under a
   **prefix** (e.g. `/api/biomarkers/import`)? A 404 on import almost always means a
   prefix mismatch. Confirm via the service's `/docs` (OpenAPI) page.
10. Does the backend accept the Supabase JWT from **this** project? (If the API
    validates tokens against a different Supabase project, auth'd calls 401/404.)
11. Is **CORS / host** config on Railway permitting the app's requests? (Less common
    for native clients, but worth checking if you see odd failures.)
12. Are the Railway service's own env vars (its `SUPABASE_URL`, service key, DB URL)
    pointing at the **same** Supabase project as step 3?

### C. Cross-checks
13. With keys set, does the **Dashboard load real biomarker data** (not the mock grid)?
14. Does a known-good Norwegian `.xlsx` import succeed end-to-end? If it 404s, revisit
    questions 8–9; if it 401s, revisit 2/4/10.
15. Is the build **Release** for TestFlight? (In Release, missing Supabase keys cause a
    hard `fatalError` by design — so a crash on launch means keys aren't wired for Release.)
