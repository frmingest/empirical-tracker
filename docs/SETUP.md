# One-time setup (GitHub, Supabase, Railway)

These steps need your accounts/credentials, so they're done by you. Run them once.
The product is a **FastAPI + Supabase backend** (deployed on Railway) with a **native
iOS client** — there is no longer a web service to deploy.

## 1. GitHub

```bash
# from the repo root
git add -A
git commit -m "Project foundations"
gh auth login            # if not already authenticated
gh repo create empirical-tracker --private --source . --push
```

## 2. Supabase (database + auth)

1. Create a project at https://supabase.com — **choose an EU region** (GDPR).
2. From Project Settings → API, copy:
   - Project URL → `SUPABASE_URL` (backend) and the `SupabaseURL` key in the iOS
     `EmpiricalTracker/Info.plist`.
   - `anon` public key → the `SupabaseAnonKey` key in the iOS `Info.plist`
     (public client key, safe to ship) **and** `SUPABASE_ANON_KEY` on the
     backend — the API uses it to build per-request, JWT-scoped clients so user
     data is queried under RLS, not as the service role (ADR-026).
   - `service_role` secret key → `SUPABASE_SERVICE_KEY` (backend only — **never**
     ship this in the app; used only for account erasure).
   - JWT secret (Project Settings → API → JWT Settings) → `SUPABASE_JWT_SECRET`
     (backend only, optional). When set, the API verifies access tokens locally
     instead of calling Supabase Auth on every request (ADR-026 F5).
3. Enable email auth under Authentication → Providers.
4. Run the SQL migrations in `api/supabase/migrations/` (in order) in the Supabase
   SQL editor to create the tables + RLS policies.

> The iOS app's backend wiring (and how to point it at staging vs production) is
> documented in [`CONFIGURATION.md`](CONFIGURATION.md).

## 3. Railway (hosting the API)

Create **one service** in a Railway project, pointing at this GitHub repo:

| Service | Root directory | Env vars to set |
|---------|---------------|-----------------|
| `api`   | `api`         | `ENVIRONMENT=production`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_KEY`, `SUPABASE_JWT_SECRET` (optional — enables local token verification, ADR-026 F5), `USDA_FDC_API_KEY` (optional — enables the USDA whole-food source) |

Steps in the Railway dashboard:
1. New Project → Deploy from GitHub repo → select this repo.
2. Add service `api`: Settings → root directory `api`. It picks up `api/railway.json`.
3. Set the env vars above. Set the region to **EU** (GDPR).
4. Generate a public domain under Settings → Networking. This is the API base URL the
   iOS app talks to (see [`CONFIGURATION.md`](CONFIGURATION.md)).

`api` exposes `/health`, which Railway uses as the healthcheck. The API auto-redeploys
on every push to `main`.

## Done when

- `git push` triggers GitHub Actions CI (the API lint + pytest job passes).
- The Railway `api` service deploys and `/health` responds.
- The iOS app, built with the Supabase + API coordinates set, signs in and loads real
  biomarker data (not the demo grid) — verify against the checklist in
  [`CONFIGURATION.md`](CONFIGURATION.md).
