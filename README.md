# Empirical Tracker

Health tracker for elimination diets (carnivore / low-carb). The core differentiator
is ingesting **blood-test results** and tracking biometrics over time, correlated with
diet adherence.

## Architecture

| Part | Stack | Dir |
|------|-------|-----|
| iOS app | Swift / SwiftUI (Xcode 15+) | [`ios/`](ios/) |
| Backend API | Python 3.11 + FastAPI | [`api/`](api/) |
| Database / Auth | Supabase (Postgres + Auth + RLS) — EU Frankfurt | managed |
| Hosting | Railway | — |

## Local development

### Backend (`api/`)
```bash
cd api
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env          # fill in values
uvicorn app.main:app --reload --port 8000
# health check: http://localhost:8000/health
pytest
```

### iOS (`ios/`)
Open `ios/EmpiricalTracker.xcodeproj` in Xcode 15+, set the active scheme to
`EmpiricalTracker`, and run on a simulator or device. Copy
`ios/Config.xcconfig.example` to `ios/Config.xcconfig` and fill in your
Supabase URL and anon key before building.

## Deployment

The API deploys to Railway automatically on push to `main`. See
[`docs/SETUP.md`](docs/SETUP.md) for one-time account setup.

## Compliance

EU/Norway. Lab results are GDPR special-category data: explicit consent at signup,
EU data region, and clean export/delete by `user_id`.
