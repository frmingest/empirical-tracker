# EmpiricalTracker — iOS

Native SwiftUI client for the Empirical Tracker health-data platform.  
Tracks biomarkers, food diary, body metrics, and Withings device data.

## Stack

- **Language / UI:** Swift 6 + SwiftUI (iOS 17+)
- **Backend:** Existing FastAPI + Supabase (shared with the web app — not rewritten)
- **Charts:** Swift Charts
- **Auth:** `supabase-swift` + Keychain
- **Health data:** Apple HealthKit (Withings bridge) + Withings Cloud API

## Documentation

| Document | Purpose |
|----------|---------|
| [`docs/SOLUTION.md`](docs/SOLUTION.md) | Solution overview — what the app is, architecture in brief, clinical-feedback roadmap |
| [`EmpiricalTracker/IOS_MIGRATION_PLAN.md`](EmpiricalTracker/IOS_MIGRATION_PLAN.md) | Full sprint plan — architecture decisions, screen mapping, Withings integration |
| [`SPRINT4.md`](SPRINT4.md) | Sprint 4 feature spec (Excel import, panel timeline) |
| [`docs/CONFIGURATION.md`](docs/CONFIGURATION.md) | Build configuration — `Config.xcconfig` → Supabase wiring, troubleshooting |
| [`docs/DIET_BIOMARKERS.md`](docs/DIET_BIOMARKERS.md) | Clinical rationale for diet-focus biomarker filtering |
| [`docs/NUTRITION_DATA.md`](docs/NUTRITION_DATA.md) | Food diary data sources, accuracy caveats, attribution |
| [`docs/adr/`](docs/adr/) | **Canonical** architecture decision records. ADRs 001–018 are web-origin, kept as the historical record of each decision; ADRs 019–023 cover the iOS build and use iOS paths. `EmpiricalTracker/adr/` mirrors these byte-for-byte. |

## Sprint status

| Sprint | Focus | Status |
|--------|-------|--------|
| 0 | Project scaffolding | Complete |
| 1 | Auth + app shell | Complete |
| 2 | Dashboard & biomarker grid | Complete |
| 3 | Biomarker detail + charts + signals + manual entry | Complete |
| 4 | Excel import + panel timeline | Complete |
| 5 | Diet events (full CRUD overlay) | Complete |
| 6 | Food diary + multi-source search + barcode scan | Complete |
| 7 | Meal plans & calendar | Complete |
| 8 | Body metrics (log + 3 overlaid charts) | Complete |
| 9 | Withings via Apple HealthKit (weight + BP sync) | Complete |
| 10 | Withings Cloud API + webhooks | In progress — iOS connect flow shipped (ADR-023); backend OAuth/webhooks outstanding |
| 11–12 | GDPR/i18n/offline → App Store release | Planned |

## Key design principles

- **Reuse the backend** — iOS is a pure presentation + native-device client; all clinical logic lives in FastAPI.
- **No medical advice** — the app is decision-support. Every marker, correlation, and diet note carries a clinician-review disclaimer.
- **Privacy-first** — HealthKit data stays on-device unless the user explicitly opts into backend sync; EU data residency via Supabase Frankfurt.
