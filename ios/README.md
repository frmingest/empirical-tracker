# EmpiricalTracker — iOS

Native SwiftUI client for the Empirical Tracker health-data platform.  
Tracks biomarkers, food diary, body metrics, and Withings device data.

## Stack

- **Language / UI:** Swift 6 + SwiftUI (iOS 17+)
- **Backend:** Shared FastAPI + Supabase backend in [`../api/`](../api/) — reused, not
  rewritten. (The original Next.js web client has been retired; iOS is the only client.)
- **Charts:** Swift Charts
- **Auth:** `supabase-swift` + Keychain
- **Health data:** Apple HealthKit (Withings bridge) + Withings Cloud API

## Documentation

All product/architecture documentation is consolidated in the repo-root
[`../docs/`](../docs/) — the single canonical set.

| Document | Purpose |
|----------|---------|
| [`../docs/SOLUTION.md`](../docs/SOLUTION.md) | Solution overview — what the app is, architecture, feature surfaces, clinical-feedback roadmap, iOS delivery status |
| [`../docs/IOS_MIGRATION_PLAN.md`](../docs/IOS_MIGRATION_PLAN.md) | Web→iOS migration strategy + status (historical) |
| [`../docs/CONFIGURATION.md`](../docs/CONFIGURATION.md) | Build configuration — Supabase / API wiring, troubleshooting, Release/Archive readiness |
| [`../docs/IOS_APP_STORE_READINESS.md`](../docs/IOS_APP_STORE_READINESS.md) | App Store submission-blocker assessment |
| [`../docs/DIET_BIOMARKERS.md`](../docs/DIET_BIOMARKERS.md) | Clinical rationale for diet-focus biomarker filtering |
| [`../docs/NUTRITION_DATA.md`](../docs/NUTRITION_DATA.md) | Food-diary data sources, accuracy caveats, attribution |
| [`../docs/WISHLIST.md`](../docs/WISHLIST.md) | Forward-looking native iOS feature proposals |
| [`../docs/adr/`](../docs/adr/) | **Canonical** Architecture Decision Records. ADRs 001–018 are web-origin, kept as the historical record of each decision (with iOS-note banners where the native client re-sequences/re-implements that surface); ADRs 019–023 cover the iOS build. |

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

The doctor PDF report (Sprint 6 follow-up) also shipped. See
[`../docs/IOS_APP_STORE_READINESS.md`](../docs/IOS_APP_STORE_READINESS.md) for the
remaining path to submission.

## Key design principles

- **Reuse the backend** — iOS is a pure presentation + native-device client; all clinical logic lives in FastAPI (and is mirrored in Swift for offline assessment).
- **No medical advice** — the app is decision-support. Every marker, correlation, and diet note carries a clinician-review disclaimer.
- **Privacy-first** — HealthKit data stays on-device unless the user explicitly opts into backend sync; EU data residency via Supabase Frankfurt.
