# Backend Configuration — Railway + Supabase

> The iOS app is a **pure client** of the existing FastAPI + Supabase backend.
> Nothing works end-to-end until these coordinates are set. This doc is the
> checklist to verify the app is wired to the right backend. (The original
> Next.js web client has been retired — iOS is now the only client of this backend.)

## Why this matters (two symptoms it explains)

| Symptom | Root cause |
|---|---|
| "I log in but only see `demo@empirical.app`, not my own profile." | Supabase keys are **not set**, so `AppConfig` silently falls back to `MockAuthService`, which accepts any login and returns a hardcoded demo session. |
| "Import fails with *Requested resource not found*." | That's an HTTP **404** from the configured API base URL — the Railway URL is wrong/not deployed, or the `POST /biomarkers/import` route isn't reachable at that base. |

## How configuration flows

```
Info.plist (SupabaseURL / SupabaseAnonKey, literal values)  ──►  AppConfig  ──►  SupabaseAuthService
EMPIRICAL_API_URL (Run-scheme env; absent in Archive)  ──►  APIClient.Configuration.resolved()  ──►  all REST calls
                                                            └─ fallback ─►  https://api-production-42c5.up.railway.app
```

- **Supabase** (auth): `Info.plist` keys `SupabaseURL` / `SupabaseAnonKey` hold the
  real project coordinates as **literal** values, committed to the repo. The anon
  key is a public client key, safe to ship; the service-role key must never appear
  in the app. Committing the literals keeps Release/Archive builds self-contained
  (see [Release / Archive readiness](#release--archive-readiness) below). They are
  *not* substituted from `Config.xcconfig` at build time — to retarget a build, edit
  `Info.plist` directly.
- **Railway API** (data): `APIClient` reads `EMPIRICAL_API_URL` from the process
  environment (set in the Run scheme for local dev), falling back to the hardcoded
  production URL `https://api-production-42c5.up.railway.app`. An archived app has no
  scheme environment, so it always uses this fallback — which is the production URL.

## Setup

The committed defaults already point at the production Supabase project and Railway
API, so a fresh checkout builds and runs against production out of the box. Override
only when you need a different backend (e.g. staging, or a local API):

1. **Supabase:** the production `SupabaseURL` / `SupabaseAnonKey` are committed in
   `EmpiricalTracker/Info.plist`. To target a different project, edit those two keys
   in `Info.plist` directly.
2. **Railway API for local dev:** `cp Config.xcconfig.example Config.xcconfig`, fill
   in `EMPIRICAL_API_URL`, and add it as an environment variable in the **Run scheme**
   (Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Arguments) — `APIClient` reads it from the
   process environment. Without an override the app uses the hardcoded production URL.
3. Clean build folder (⇧⌘K), rebuild on device.

> `Config.xcconfig` is git-ignored. The Supabase **anon** key is a public client
> key and is safe to ship; the **service-role** key must never appear in the app.

---

## Release / Archive readiness

For TestFlight / App Store the build is **Release**, archived from the
`EmpiricalTracker` scheme (`ArchiveAction` ▸ `buildConfiguration = Release`). In
Release the demo/mock-auth fallback is compiled out (`#if DEBUG`), so a missing or
unresolved Supabase credential triggers a hard `fatalError` at launch *by design*.
The checklist below is what keeps an archive from tripping that guard — all of it is
verified in the current project:

- **Supabase creds resolve.** `Info.plist` carries literal `SupabaseURL` /
  `SupabaseAnonKey` values (not `$(…)` placeholders), and the app target uses that
  file for both Debug and Release (`INFOPLIST_FILE`, `GENERATE_INFOPLIST_FILE = NO`).
  `AppConfig.resolvedSupabaseCredentials()` therefore returns non-nil and
  `SupabaseAuthService` is used — the `#else fatalError` branch is never reached.
  Because the values are literals, this holds even on a machine/CI runner without the
  git-ignored `Config.xcconfig`. ⚠️ Do **not** rewrite these keys to `$(SUPABASE_URL)`
  placeholders unless you also commit a build-time default — otherwise archives built
  without `Config.xcconfig` will crash on launch.
- **API URL resolves.** An archived app has no Run-scheme environment, so
  `APIClient.Configuration.resolved()` falls back to the hardcoded production URL
  `https://api-production-42c5.up.railway.app`.
- **`DEMO_MODE` is unset.** It is read from the process environment only and is not
  set in the scheme, the `.pbxproj`, or `Config.xcconfig`. An archive has no scheme
  env, so the mock-auth shortcut is never taken.
- **Demo affordances are DEBUG-only.** The demo-login button (`AuthView`) and the
  mock-auth fallback (`AppConfig`) are both `#if DEBUG`, so they are absent from a
  Release archive entirely.

To re-verify after any config change: `grep -n SupabaseURL EmpiricalTracker/Info.plist`
(expect literal values, no `$(`), and confirm no `DEMO_MODE` appears in the scheme or
`Config.xcconfig`.

---

## Control questions (verify your setup)

### A. Supabase (auth / profile)
1. In the Supabase dashboard ▸ Settings ▸ API, what is the **Project URL**? Does it
   exactly match `SupabaseURL` in `EmpiricalTracker/Info.plist` (including `https://`
   and `.supabase.co`)?
2. Is the key in `SUPABASE_ANON_KEY` the **anon/public** key — not the service-role key?
3. Is this the **same** Supabase project the backend points at? (During a port or
   environment split, people sometimes spin up a new project and the data lives in
   the old one.)
4. Does your user account actually exist in **this** project's `auth.users`? Check
   in the Supabase dashboard (Authentication ▸ Users) to confirm.
5. After building with keys set, does the **Settings tab still show the orange
   "Demo mode — backend not configured" banner**? If yes, the keys aren't resolving
   (check that `SupabaseURL` / `SupabaseAnonKey` in `Info.plist` are real values and
   not `$(…)` placeholders, then clean-build). In a Release archive this same
   condition is a hard `fatalError` rather than a banner — see
   [Release / Archive readiness](#release--archive-readiness).
6. Does Settings show **your** email after login, not `demo@empirical.app`?

### B. Railway (REST API / import + data)
7. What is the **public Railway URL** of the FastAPI service, and is it currently
   deployed and healthy (open it in a browser — `/docs` or `/health` should respond)?
8. Does `EMPIRICAL_API_URL` exactly match that URL? Is the default
   `https://api-production-42c5.up.railway.app` even correct for your deployment?
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
