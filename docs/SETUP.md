# One-time setup (GitHub, Supabase, Railway)

These steps need your accounts/credentials, so they're done by you (the CLI is already
installed: `gh`, `railway`). Run them once.

## 1. GitHub

```bash
# from the repo root
git add -A
git commit -m "Sprint 0: project foundations"
gh auth login            # if not already authenticated
gh repo create empirical-tracker --private --source . --push
```

## 2. Supabase (database + auth)

1. Create a project at https://supabase.com — **choose an EU region** (GDPR).
2. From Project Settings → API, copy:
   - Project URL → `SUPABASE_URL` (api) and `NEXT_PUBLIC_SUPABASE_URL` (web)
   - `anon` public key → `NEXT_PUBLIC_SUPABASE_ANON_KEY` (web)
   - `service_role` secret key → `SUPABASE_SERVICE_KEY` (api, server-only)
3. Enable email auth under Authentication → Providers.

Schema (biomarker tables + RLS) lands in Sprint 1.

## 3. Railway (hosting)

Create **two services** in one Railway project, both pointing at this GitHub repo:

| Service | Root directory | Env vars to set |
|---------|---------------|-----------------|
| `api`   | `api`         | `ENVIRONMENT=production`, `CORS_ORIGINS=<web public URL>`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` |
| `web`   | `web`         | `NEXT_PUBLIC_API_URL=<api public URL>`, `NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` |

Steps in the Railway dashboard:
1. New Project → Deploy from GitHub repo → select this repo.
2. Add service `api`: Settings → root directory `api`. It picks up `api/railway.json`.
3. Add service `web`: Settings → root directory `web`. It picks up `web/railway.json`.
4. Set the env vars above on each service. Set the region to **EU** (GDPR).
5. Each service gets a public domain under Settings → Networking → Generate Domain.
6. After both have URLs, update `CORS_ORIGINS` (api) and `NEXT_PUBLIC_API_URL` (web)
   to the real domains and redeploy.

`api` exposes `/health`, which Railway uses as the healthcheck.

## Sprint 0 done when
- `git push` triggers GitHub Actions CI (api + web jobs pass).
- Both Railway services deploy; visiting the web URL shows **API status: connected**.
