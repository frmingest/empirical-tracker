# iOS Hardening Proposal — Empirical Tracker

**Prepared by:** iOS platform / UX review
**Date:** 2026-06-04
**Scope:** the native iOS client (`ios/`) — stability, robustness, and efficiency.
**Companion docs:** [`IOS_APP_STORE_READINESS.md`](IOS_APP_STORE_READINESS.md) (submission
blockers — out of scope here), [`SOLUTION.md`](SOLUTION.md) (architecture),
[`WISHLIST.md`](WISHLIST.md) (forward-looking features).

---

## Summary

The codebase is genuinely well-architected — 9 SwiftPM domain packages behind a thin
app target, an actor-based typed `APIClient`, ported clinical logic, `@Observable`
MVVM, RLS + EU data region on the backend, and clean hygiene (no `print`, no `try!`,
one intentional `fatalError` guarding misconfigured Release builds). This proposal is
therefore **not** a rewrite; it is a set of targeted fixes to the handful of places
where the app can **lose or duplicate user data, bounce the user out of a valid
session, or do unnecessary work on launch**.

The findings cluster into seven themes. The three that move the needle most:

1. **Idempotency-unaware retries** can silently duplicate health rows (manual lab
   results, diet events, food logs) on a flaky connection.
2. **No 401 → refresh → retry path** turns a routine token expiry into a
   "session expired" bounce, contradicting the "silent refresh" promise.
3. **All six tabs load eagerly on launch** — a cold-start thundering herd and a
   standing memory cost — and **there is no offline cache**, so a longitudinal
   health tracker shows empty/error states the moment the network is slow.

Severity legend: **P0** ship-blocker-class data/security risk · **P1** material
robustness/efficiency · **P2** polish / defence-in-depth.

---

## Theme 1 — Networking resilience

### 1.1 Retries are not idempotency-aware (P1, data-integrity)

`perform(_:decoding:retriesLeft:)` and `performData` retry on any `networkError` or
5xx for **every** HTTP method
(`ios/Packages/Core/Sources/Core/Networking/APIClient.swift:106-146`). A timeout that
fires *after* the server has already committed a write — the classic "response lost,
request succeeded" case — will replay a `POST`/`PUT`/`PATCH` and create a duplicate.

The blast radius is real for the mutating endpoints that have **no** server-side
dedupe: manual lab results, diet events, food-diary entries, planned meals. (The
`.xlsx` import is protected by a server `409` on duplicate panel date, and HealthKit
body-metrics by sample-UUID dedupe — but those are the exceptions.)

**Fix.** Gate retries on `Endpoint.method`. Retry only idempotent verbs (`GET`,
`DELETE`, and `PUT` where the body is a full replace); never auto-retry `POST`/`PATCH`.
`Endpoint` already carries `method`, so this is a few lines in the two `perform`
helpers. Where a `POST` *must* be safely retryable, add an `Idempotency-Key` header
the backend can dedupe on.

### 1.2 `DELETE` gets no retry at all (P2, inconsistency)

`requestEmpty(_:)` — the path used for deletes — does a single `session.data(for:)`
with no backoff loop (`APIClient.swift:66-70`), while `request`/`requestData` retry up
to three times. So a `GET` survives a transient blip but deleting a panel or food
entry fails outright on the first hiccup. **Fix.** Route all three public methods
through one shared `perform` that applies the (now idempotency-aware) retry policy.

### 1.3 No 401 → refresh → retry (P1, session UX)

On `401` the client throws `.unauthorized` immediately (`APIClient.swift:154`), and
`TokenProvider` only exposes `currentToken()`
(`Core/Networking/TokenProvider.swift`, `Auth/.../AuthTokenProvider.swift:17`), which
just reads the in-memory access token. `supabase-swift` refreshes in the background,
but if a request fires while the cached token is stale, the user is bounced with
"Session expired — please sign in again" — directly contradicting the "silent refresh"
claim in `SOLUTION.md`.

**Fix.** Add `func refreshToken() async -> String?` to `TokenProvider`
(implemented via `client.auth.session`, which force-refreshes). In the client, on the
*first* `401` of a request, refresh once and retry; only surface `.unauthorized` if the
refreshed call also 401s. This is the single highest-leverage stability fix for daily
use.

### 1.4 No 429 / `Retry-After` handling (P2)

`429` falls into the `default` branch → `serverError`, and `isRetryable` only covers
`>= 500` (`APIError.swift:26-30`). The multi-source food proxy fronts rate-limited
upstreams (OFF/USDA), so 429s are plausible. **Fix.** Treat `429` as retryable and
honour the `Retry-After` header for the backoff delay.

### 1.5 Untuned `URLSession` (P2)

Both the shared client and the import service use a default/`.shared` session with no
`waitsForConnectivity`, no `timeoutIntervalForResource`, and no cache policy
(`APIClient.swift:48`, `BiomarkersImportService.swift`). **Fix.** Build one
`URLSessionConfiguration` with `waitsForConnectivity = true` and a sane resource
timeout (e.g. 60s) so brief connectivity gaps wait rather than fail, and reuse it
across the client.

---

## Theme 2 — Auth & data-at-rest security

### 2.1 Keychain items aren't device-only (P1, privacy)

`KeychainService.write` sets no `kSecAttrAccessible`
(`Auth/.../KeychainService.swift:42-56`), so items default to
`kSecAttrAccessibleWhenUnlocked` — **eligible for iCloud Keychain sync and
device-transfer/encrypted-backup restore**. For an app whose session token unlocks
GDPR special-category health data, the JWT, user id, and email should never leave the
device. **Fix.** Add `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
(or `WhenUnlockedThisDeviceOnly`) to the write and read queries.

### 2.2 Keychain writes fail silently (P2)

`save(session:)` ignores the `OSStatus` from `SecItemUpdate`/`SecItemAdd`
(`KeychainService.swift:42-56`). A failed write looks fine for the current launch but
the user is silently signed out on the next cold start, with nothing logged. **Fix.**
Check the status, return a `Bool`/throw, and `Logger`-log failures.

### 2.3 Auth-error mapping by localized-string matching (P2, brittleness)

`SupabaseAuthService.mapError` lowercases `error.localizedDescription` and substring-
matches `"invalid"`, `"network"`, etc. (`SupabaseAuthService.swift:67-77`). This is
locale-dependent (a Norwegian-locale device may never match) and breaks across
`supabase-swift` versions. **Fix.** Switch on the typed `AuthError`/HTTP status that
`supabase-swift` surfaces rather than its human-readable message.

---

## Theme 3 — Concurrency & state correctness

### 3.1 Shared `isLoading` flips early under concurrent loads (P2)

In `BiomarkersRepository`, `loadResults()` and `loadPanels()` write the *same*
`isLoading` flag (`Biomarkers/.../BiomarkersRepository.swift:24-48`). `importXLSX`
runs them back-to-back and the dashboard runs `loadResults` concurrently with settings;
whichever finishes first sets `isLoading = false` while the other is still in flight —
producing spinner flicker and brief "empty" flashes. **Fix.** Use an in-flight counter
(or distinct per-operation flags) so loading is false only when *no* load is running.

### 3.2 Optimistic settings writes swallow failures (P2)

`setFocus`/`setCustomMarkers`/`forkToCustom` mutate local `settings` then `try?` the
save (`Dashboard/DashboardViewModel.swift:64-95`). A failed save leaves the UI showing
a diet focus the server never stored, which then disagrees with the next device or
cold launch. **Fix.** On save failure, roll back the optimistic change and surface a
non-blocking error, matching how `FoodDiaryViewModel` already reports `errorMessage`.

---

## Theme 4 — Launch performance & memory

### 4.1 All six tabs load eagerly and stay resident (P1, efficiency)

`MainTabView` layers all six destinations in a `ZStack`, toggling visibility by opacity
to preserve state (`App/RootView.swift:66-95`). Because hidden screens stay in the view
hierarchy, **every tab's `.task` fires on launch** — a cold start kicks off ~6
concurrent network loads (dashboard, diary, plan, recipes, body, settings) and holds
all six feature trees (charts, scanners, calendars) in memory for the whole session.

**Fix.** Lazily instantiate a tab's content the first time it is selected, then keep it
resident (preserving the "state survives tab switch" behaviour for *visited* tabs only).
A small `visitedTabs: Set<AppTab>` guard around each `screen(...)` builder is enough.
This cuts launch network/CPU to the one visible tab and trims baseline memory.

### 4.2 Import body built fully in memory (P2)

`BiomarkersImportService.upload` does `Data(contentsOf: fileURL)` then concatenates the
whole multipart body in memory. Typical lab `.xlsx` files are tiny, so this is low-risk,
but there is no upfront size guard. **Fix.** Add a max-size check before reading, and
consider `URLSession.upload(for:fromFile:)` to stream the body for safety.

---

## Theme 5 — Offline robustness

### 5.1 No persistence layer (P1, robustness)

Every repository is in-memory only — `BiomarkersRepository.swift:7` even notes
*"Sprint 11 adds SwiftData offline cache."* On a cold launch with no/slow network the
app shows empty or error states for data the user saw seconds earlier. For a
**longitudinal** health tracker this is the most user-visible robustness gap.

**Fix.** Add a read-through cache for the read-heavy, slow-changing surfaces
(biomarker results, diet events, body metrics): render cached data instantly on launch,
then refresh in the background and reconcile. SwiftData is the documented intent; a
small `Codable`-to-disk cache per repository is a lighter first step that delivers most
of the benefit. Pairs naturally with fixing 4.1 (load-on-first-visit) and 1.5
(`waitsForConnectivity`).

---

## Theme 6 — Design-system consistency

### 6.1 Inline `Font.system(size:)` in feature views (P2)

`CLAUDE.md` and `DESIGN_SYSTEM.md` state plainly: *"Never call `Font.system(size:)`
inline in a feature view."* Yet it appears in the app shell and eight feature views —
`App/RootView.swift` (the floating tab bar), and `Recipes`, `Import`, `DietEvents`,
`Consent`, `BodyMap`, `Auth`, `NutritionLabelCapture`. **Fix.** Replace with semantic
`Font.*` tokens from `AppTypography.swift` (add a token if a size is genuinely missing).
Clearing these also unblocks turning SwiftLint from non-blocking to `--strict` (readiness
doc item #8).

---

## Theme 7 — Observability & test/CI coverage

### 7.1 Package `@Test` suites don't run in CI (P2)

The CI `ios` job runs the app unit-test target but `-skip`s UI tests, and the ~58
package `@Test` cases live in package test targets the app scheme doesn't include
(`.github/workflows/ci.yml`; readiness doc #8). The bulk of the logic tests therefore
don't gate merges. **Fix.** Add a `swift test` pass per package (or include the package
test targets in the scheme) so marker-signal, DTO-contract, auth, and health-sync logic
is actually verified on every PR.

### 7.2 No field diagnosability (P2)

Beyond `AppConfig`'s logger there is no structured logging of network failures and no
crash/error breadcrumbs. A health app rightly avoids invasive analytics, but
privacy-safe `OSLog`/signpost breadcrumbs around API failures, and a lightweight crash
reporter, would make TestFlight/production issues diagnosable without collecting health
data. **Fix.** Add a small `Logger`-based breadcrumb in the `APIClient` error paths
(status code + endpoint path only — never bodies).

---

## What's already strong (leave alone)

- **Clean hygiene** — no `print`, no `try!`, production force-unwraps confined to
  static URLs/tests; a single intentional Release `fatalError` guarding misconfigured
  credentials (`AppConfig.swift:58`).
- **Actor isolation done right** — `APIClient` and `HealthSyncManager` are actors;
  HealthKit's non-`Sendable` types are correctly mapped *inside* the query continuation
  before crossing the boundary (`HealthSyncManager.swift:226-250`).
- **Sound dedupe where it exists** — server `409` on duplicate panel date, HealthKit
  sample-UUID dedupe via `SyncedSampleStore`, observer `completion()` always called.
- **Debounced search with cancellation** — `FoodDiaryViewModel.scheduleSearch` cancels
  stale tasks correctly (`FoodDiaryViewModel.swift:87-96`).
- **Honest error UX** — `ImportViewModel.message(for:)` distinguishes 4xx (your file)
  from 5xx (our server) with actionable copy.
- **Safe Release posture** — demo/mock auth is `#if DEBUG`-only; Release fatals if
  Supabase creds are missing.

---

## Recommended sequencing

**Phase A — data integrity & session (do first; small, high-impact):**
1.1 idempotency-aware retries · 1.3 401→refresh→retry · 1.2 unify the retry surface ·
2.1 device-only Keychain.

**Phase B — robustness & efficiency:**
4.1 lazy tab loading · 5.1 read-through offline cache · 1.5 `waitsForConnectivity` ·
3.1 in-flight loading counter.

**Phase C — defence-in-depth & polish:**
1.4 429/`Retry-After` · 2.2/2.3 Keychain status + typed auth errors · 3.2 settings
rollback · 4.2 import size guard · 6.1 design-system tokens · 7.1 package tests in CI ·
7.2 logging breadcrumbs.

Phase A is roughly a day and removes the only paths that can **duplicate or lose**
health data or eject a valid session. Phases B and C are independent and can land
incrementally behind the existing test suite.
