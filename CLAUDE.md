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

0 ✅ → 1 ✅ → 2 ✅ → 3 ✅ → 4 ✅ → 5 ✅ → 6 ◐ → 7 ✅ → 8 ◐ → 9 ◐ → 10 ✅

(◐ = partially shipped: the Sprint 6 doctor-PDF report shipped on iOS (selectable
categories/markers, latest values and/or trend graphs, shared via the system sheet);
Sprint 8 Medium markers / derived ratios, and Sprint 9 daily targets remain — see
`docs/SOLUTION.md`. The
Sprint 9 whole-foods source shipped (Matvaretabellen + USDA, macros — ADR-018);
its micronutrient phase is deferred to a future ADR. Sprint 10 shipped
weight/waist/BP tracking; the *optional* body-metric-on-biomarker-timeline
overlay is a noted follow-up.)

Sprints 7–10 come from a clinical review of the app; see "Clinical-feedback
roadmap (Sprints 7–10)" in `docs/SOLUTION.md`.

See `docs/SOLUTION.md` for full sprint descriptions.

## Stack

- **iOS app:** Swift / SwiftUI, Xcode 15+ (`ios/`)
- **Backend:** Python + FastAPI (`api/`)
- **DB/Auth:** Supabase (Postgres + RLS) — EU region (Frankfurt)
- **Deploy:** Railway (auto-deploys on push to `main`)

## Key conventions

- DB migrations live in `api/supabase/migrations/` — numbered sequentially, run manually in Supabase SQL editor
- Tests: `cd api && pytest -v` (all must pass)
- External data (Open Food Facts) is reached through an authenticated backend proxy that sets a `User-Agent`; never call third-party APIs directly from the iOS app
- Xcode project uses folder synchronization (Xcode 15) — new `.swift` files added to `ios/EmpiricalTracker/` subdirectories are picked up automatically, no `.pbxproj` edits needed
