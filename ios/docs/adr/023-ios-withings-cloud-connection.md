# ADR-023: iOS Withings Cloud connection (Path B)

**Status:** Accepted
**Date:** 2026-06-02
**Author:** iOS team
**Sprint:** 10 (iOS)

---

## Context

The migration plan (`IOS_MIGRATION_PLAN.md` §1.2) commits to a **two-path** Withings
strategy. Sprint 9 shipped **Path A**, the Apple HealthKit bridge ([ADR-022](022-ios-healthkit-withings-sync.md)):
weight + blood pressure that the user's Health Mate app writes into Apple Health, read
back on-device and folded into the body-metrics surface.

**Path B — the Withings Cloud API (Sprint 10)** — connects the user's Withings account
**server-to-server** so the backend can import the *full history* on connect and receive
*server-pushed* updates via `Notify` webhooks, independent of HealthKit and of whether
Health Mate is installed. This ADR records the **iOS** half of Sprint 10 and, as with
ADR-022, **where the scope line is drawn** given the backend endpoints are new work.

### The constraint that shapes scope

Almost all of Sprint 10 is **backend (FastAPI)** work (migration plan §4.4): the OAuth2
token exchange (`/withings/callback`), encrypted token storage + refresh scheduler, the
`getmeas` history pull, the `Notify` webhook subscription, and dedupe by Withings `grpid`
(plus the `external_id` column from §4.2 and the `withings_measures` table from §4.3).
**None of that lives in this iOS repository**, and it is not yet deployed.

What genuinely originates on-device is the **connection ceremony**: starting the OAuth
consent flow, reading connection status, triggering a manual pull, and disconnecting.
That is what iOS Sprint 10 ships — built against the documented endpoint contract, and
**self-gated** so it stays invisible until the backend can serve it.

---

## Decision

### 1. The app starts the connection; the backend owns the tokens

`WithingsCloudService` (in the `HealthSync` package, `Core`-only — no HealthKit) wraps
four calls:

| Call | Purpose |
|---|---|
| `GET /withings/authorize` | Backend returns the Withings consent URL (scopes `user.info,user.metrics,user.activity`, `redirect_uri` → `/withings/callback`) + a CSRF `state`. |
| `GET /withings/connection` | Current status: `connected`, `last_sync_at`, `connected_at`. |
| `POST /withings/sync` | Ask the backend to pull new measurements now (the reliable fallback to webhooks). |
| `DELETE /withings/connection` | Revoke server-side; imported rows are kept. |

The app **never sees a Withings credential or token**. It carries only its Supabase JWT;
the backend (Supabase Frankfurt, EU) holds the encrypted Withings tokens and runs the
webhooks. This mirrors the whole-app principle — clinical/secret-bearing work stays in
the backend; iOS is presentation + the native ceremony only.

### 2. `ASWebAuthenticationSession` behind a protocol seam

The consent page opens in `ASWebAuthenticationSession` with `callbackURLScheme =
"empiricaltracker"` (registered in `Info.plist` `CFBundleURLTypes`). Withings redirects
to the backend `/withings/callback`, which exchanges the code for tokens and then 302s to
`empiricaltracker://withings` — the redirect the session captures. The session is hidden
behind a `WithingsWebAuthenticating` protocol so `WithingsCloudState` drives the flow
without importing UIKit and so it's swappable in previews/tests; the production
conformer also vends the `ASWebAuthenticationPresentationContextProviding` anchor.

`WithingsCloudService.isSuccessCallback(_:)` discriminates the backend's success redirect
from a user cancel — a small, pure, unit-tested function (the rest of the session needs a
device and is in the Sprint 12 QA matrix).

### 3. Self-gating on backend capability — the feature hides until the backend ships

Unlike every prior iOS sprint (which consumed endpoints the web app already exercised),
the `/withings/*` endpoints are net-new and may not be deployed when this build ships.
Rather than present a button that 404s, `WithingsCloudState` starts `.unavailable` and
only reveals the feature once `GET /withings/connection` answers; a `404` (or any error
before availability is ever confirmed) keeps it hidden. **The UI therefore lights up
automatically the moment the backend deploys — no client release required — and stays
invisible until then.** This keeps the ADR-022 discipline: don't ship UI the backend
can't support.

### 4. One shared state, mirroring the Apple Health pattern

A single `WithingsCloudState` (`@MainActor @Observable`) lives on `AppEnvironment`, so the
Body-tab `WithingsCloudSection` card and the `WithingsCloudSettingsView` detail show one
connection. It sits directly below the Apple Health card on Body and gets its own row in
Settings ▸ Devices. After connect/sync it reloads `BodyMetricsRepository` — the backend
remains the source of truth, so Withings rows (tagged `source: withings`, already handled
by the Sprint 8 model and history badge) flow into the same charts and overlays as manual
and HealthKit rows.

### 5. Scope: weight + BP now; richer signals + reconciliation deferred to the backend

The connection imports what the existing `body_metrics` columns hold — **weight + blood
pressure**. Body-composition (body-fat %, lean mass, resting HR, SpO2) and activity/sleep
summaries still wait on the `withings_measures` table (§4.3), exactly as in ADR-022; the
"About" copy says so. **HealthKit ↔ Cloud reconciliation** (avoiding a reading counted via
both paths) needs the server `external_id` dedupe (§4.2) and is a backend concern; until it
lands, a user who connects *both* paths could double-count — acceptable and documented,
matching ADR-022's trade-off note.

---

## Consequences

- **Good:** The full on-device connection ceremony (authorize → consent → status → sync →
  disconnect) is built, localized EN/NO, and ready; it activates automatically when the
  backend deploys, with no further app release.
- **Good:** No Withings secrets on the device; the package stays `Core`-only and the OAuth
  session sits behind a testable seam, so the DTO contracts and callback discrimination are
  unit-tested without a backend or device.
- **Good:** Withings rows reuse the Sprint 8 `source: withings` model and history badge and
  the shared diet-event chart overlay — zero new charting work.
- **Trade-off / deferred:** Richer body-composition + activity/sleep signals wait on the
  §4.3 table; the surface has an obvious extension point.
- **Trade-off:** Cross-path dedupe needs the §4.2 server `external_id`; double-counting is
  possible if both HealthKit and Cloud are connected before that lands.
- **Limitation:** The OAuth web flow and server pull need the live backend; they are
  validated on-device in the Sprint 12 QA matrix, not in CI.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Ship a visible "Connect Withings" button regardless of backend state | It would 404 until the (separate) backend deploys; self-gating on `GET /withings/connection` avoids a dead control and needs no follow-up release. |
| Do the OAuth token exchange on-device | Puts the Withings client secret in the app binary and tokens in the client; the backend already must hold tokens for webhooks/refresh, so server-side exchange is both safer and necessary. |
| Have Withings redirect straight to the app scheme with the `code` | The app would then need the client secret to exchange it; routing the redirect through `/withings/callback` keeps the secret server-side. |
| A new `WithingsCloud` Swift package | The migration plan (§1.3) defines a single `HealthSync` domain module; the Cloud client is `Core`-only and small, so it lives there beside the HealthKit bridge rather than adding package + dependency wiring. |
| Surface body-fat / lean mass / resting HR now | Nowhere to store them until §4.3 (same constraint as ADR-022); we import only what the existing columns hold. |

---

> Numbering note: ADR-023 uses **iOS** sprint numbering (Sprint 10), continuing from
> ADR-022. It realises migration plan §1.2 Path B and depends on the body-metrics surface
> (ADR-017 / ADR-021) and the backend work items in §4.2–§4.4, which are tracked there as
> outstanding.
