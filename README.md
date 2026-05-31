# Empirical Tracker

Health tracker for elimination diets (carnivore / low-carb). The core differentiator
is ingesting **blood-test results** and tracking biometrics over time, correlated with
diet adherence.

## Architecture

API-first monorepo so future iOS/Android clients (React Native) reuse the same backend.

| Part | Stack | Dir |
|------|-------|-----|
| Backend API | Python 3.11 + FastAPI | [`api/`](api/) |
| Web client | Next.js (TypeScript, App Router) | [`web/`](web/) |
| Database / Auth | Supabase (Postgres + Auth + RLS) | managed |
| Hosting | Railway | — |

## Local development

### Backend (`api/`)
```bash
cd api
python -m venv .venv
.venv\Scripts\activate        # Windows
pip install -r requirements.txt
cp .env.example .env          # fill in values
uvicorn app.main:app --reload --port 8000
# health check: http://localhost:8000/health
pytest
```

### Web (`web/`)
```bash
cd web
npm install
cp .env.example .env.local    # fill in values
npm run dev                   # http://localhost:3000
```

## Deployment

Both services deploy to Railway from this GitHub repo. See [`docs/SETUP.md`](docs/SETUP.md)
for the one-time account setup (GitHub, Supabase, Railway).

## Compliance

EU/Norway. Lab results are GDPR special-category data: explicit consent at signup,
EU data region, and clean export/delete by `user_id`.
