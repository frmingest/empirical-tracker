# Empirical Tracker — Claude Code Instructions

## Git workflow

**Never commit directly to `main`.** Always:

1. Create a feature branch before any changes:
   ```
   git checkout -b sprint-N/<slug>
   git checkout -b fix/<slug>
   git checkout -b feat/<slug>
   git checkout -b chore/<slug>
   ```
2. Commit all work to the feature branch
3. Open a PR with `gh pr create` and let the user merge
4. Never run `git push origin main` or commit on `main` directly

This applies to all changes — code, docs, migrations, single-file edits.

## Sprint order

0 ✅ → 1 ✅ → 2 ✅ → 3 ✅ → 4 ✅ → 5 ✅ → 6

See `docs/SOLUTION.md` for full sprint descriptions.

## Stack

- **Backend:** Python + FastAPI (`api/`)
- **Frontend:** Next.js 14 App Router, TypeScript strict, Tailwind v4 (`web/`)
- **DB/Auth:** Supabase (Postgres + RLS) — EU region (Frankfurt)
- **Deploy:** Railway (auto-deploys on push to `main`)

## Key conventions

- All frontend colors use CSS custom properties (`var(--bg-card)`, `var(--text-primary)`, etc.) — never hardcode zinc/slate Tailwind classes
- TypeScript strict mode — no `any`
- DB migrations live in `api/supabase/migrations/` — numbered sequentially, run manually in Supabase SQL editor
- Tests: `cd api && pytest -v` (all must pass) — Sprints 3 & 4 added diet-event and food-diary suites
- Frontend checks: `cd web && npx tsc --noEmit && npx eslint src && npm run build` must all pass
- External data (Open Food Facts) is reached through an authenticated backend proxy that sets a `User-Agent`; never call third-party APIs directly from the browser
