# ADR-001: Technology Stack Selection

**Status:** Accepted — partially superseded (see update below)  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

> **⚠️ 2026-06-05 update — two decisions changed after MVP:**
>
> 1. **Frontend: Next.js was retired.** The Next.js / React web client was removed from the
>    repository after the iOS rewrite was complete (`chore: retire Next.js web app`). The
>    iOS app is now the only client. The backend (FastAPI + Supabase) is unchanged and
>    continues to serve it. See `SOLUTION.md` and `IOS_MIGRATION_PLAN.md`.
>
> 2. **Mobile path: React Native was never built — the iOS app is Swift / SwiftUI.**
>    The original plan anticipated a React Native mobile client that would share React
>    patterns with the web frontend. Instead the mobile client was built as a fully native
>    **Swift / SwiftUI** app (Xcode 15+, Swift Package Manager modules, Swift Charts).
>    The rationale at the time was that native tooling gives better access to HealthKit,
>    VisionKit barcode scanning, and `ASWebAuthenticationSession` (Withings OAuth) than
>    a cross-platform bridge, and that the backend does all the hard clinical logic anyway
>    so the client layer is primarily presentation. See [ADR-019](019-ios-food-diary-barcode-scanning.md)
>    onward for iOS-native decisions, and [ADR-025](025-ios-soft-design-system.md) for the
>    iOS design system.
>
> Everything else in this ADR (Python + FastAPI, Supabase, Railway, RLS boundary) remains
> accurate and in force.

---

## Context

Building a personal health tracker that ingests blood-test results from Norwegian lab reports
and correlates them with elimination-diet adherence. The app is the user's own primary tool,
but the architecture must support sharing with doctors and a future iOS/Android client.

Key constraints:
- Solo developer — minimal operational overhead
- EU/Norway — health data is GDPR special-category (Article 9); must be EU-resident
- The blood-test ingestion is the core differentiator; everything else is secondary
- Future mobile app must share the same data model and API

---

## Decision

**Backend:** Python + FastAPI  
**Frontend (web):** ~~Next.js (TypeScript, App Router)~~ *→ retired; see update banner above*  
**Database / Auth:** Supabase (Postgres + Auth + RLS)  
**Hosting:** Railway  
**Mobile client (primary):** ~~React Native~~ → **Swift / SwiftUI** (native iOS) *→ see update banner above*

---

## Rationale

### Python + FastAPI (not Node/Go/Rust)
The blood-test parsing pipeline needs openpyxl for Excel ingestion and will eventually need
NumPy/Pandas/scikit-learn for biomarker trend analysis and diet correlation. Python is the
only first-class language for this stack. FastAPI specifically over Django/Flask: async-first,
Pydantic validation, automatic OpenAPI docs, and fast enough for the expected load.

### Next.js (not plain React, not SvelteKit)
App Router enables server-component data fetching without a separate BFF layer. TypeScript
types can be shared or mirrored with the API response shapes. The React skill carries over
directly to the planned React Native mobile client — a SvelteKit frontend would not.

### Supabase (not raw Postgres + Auth0 + S3)
A solo developer cannot responsibly maintain separate auth, database, storage, and row-level
security systems. Supabase bundles all four with a generous free tier and a compliant EU region
(Frankfurt). RLS policies enforce at the database layer that users can only see their own data —
this is the GDPR isolation boundary. The alternative (building auth middleware + service-level
tenant isolation) would take weeks and be harder to audit.

### Railway (not Vercel/Render/Fly.io)
Railway deploys both the FastAPI and Next.js services from a single GitHub repo without a
complex monorepo build config. Automatic preview deployments, straightforward environment
variable management, and no cold-start latency on paid plans.

---

## Consequences

- **Good:** Managed services mean ~0 infra maintenance; auth, SSL, backups all handled
- **Good:** Python backend can evolve into biomarker analytics / ML without a rewrite
- **Good:** RLS means even a compromised service-role token can only access data via correct
  user_id scoping
- **Trade-off:** Supabase is a vendor lock-in. Mitigation: all data is in standard Postgres;
  an export path is a first-class Sprint 6 feature
- **Trade-off:** Railway costs money at scale. At single-user load this is negligible

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Node.js backend | No path to biomarker ML/stats without rewriting to Python later |
| Django | Too much ceremony for an API-only service; FastAPI's type system is better |
| PlanetScale/Neon | No built-in auth or RLS; would need separate Auth0/Clerk |
| Vercel | Can't run FastAPI (Python long-running process) on the same platform |
| Self-hosted Postgres | Too much ops for a solo developer handling health data |
