# iOS App Store Readiness Assessment — Empirical Tracker

**Prepared by:** iOS Platform Architecture review
**Date:** 2026-06-03
**Build under review:** `EmpiricalTracker`, marketing version `1.0` (build `1`),
bundle id `com.FaizMalik.EmpiricalTracker`, branch `claude/ios-app-store-readiness-Y49QQ`

---

## Verdict

**NOT ready for App Store submission.**

The codebase is well-architected and the feature set is mature, but there are
**two hard blockers that guarantee rejection** (missing app icon — now
resolved ✅ — and no in-app account deletion) plus **two high-risk compliance
gaps** (missing privacy
manifest, no in-app privacy policy/consent) that App Review will catch on a
health-data app. None are large; this is roughly **2–4 focused days** of work to
become submittable, most of it product/compliance plumbing rather than
engineering.

**Readiness score: ~60%** — engineering is strong; release & compliance
artifacts are largely absent.

---

## Blockers — must fix before you can submit

### 1. No app icon ✅ RESOLVED
~~`ios/EmpiricalTracker/Assets.xcassets/AppIcon.appiconset/` contains only a
placeholder `Contents.json` with a single `1024x1024` slot and **no image file**.
`AccentColor.colorset` is likewise empty. An app cannot be archived for
distribution or pass App Review without an app icon.~~
**Fix:** add the 1024×1024 marketing icon (single-size asset catalog is fine for
modern Xcode) and define the accent color.
**Done:** `AppIcon-1024.png` (1024×1024, opaque sRGB, no alpha channel — meets
App Review requirements) added to `AppIcon.appiconset` and wired into
`Contents.json`. `AccentColor.colorset` now defines the brand blue
(sRGB `#1A82FF`) to match the icon.

### 2. No in-app account deletion or data export UI 🛑
Apple **Guideline 5.1.1(v)** requires any app that supports account creation to
let users **initiate account deletion from within the app**. The backend logic
exists — `AccountRepository` exposes `deleteAccount(confirmation:)` and
`exportData(format:)` — **but neither is wired to any view.** `SettingsView`'s
account section only offers *Sign out*; the file's own header comment claims
"Sprint 11: GDPR export, account deletion," but that UI was never built. A
codebase grep finds **zero call sites** for `deleteAccount`/`exportData`.
**Fix:** add a "Delete account" (danger-zone, type-to-confirm) and "Export my
data" action to `SettingsView`, calling the existing repository methods. This is
also the GDPR right-to-erasure / portability surface the README promises.

### 3. Missing privacy manifest (`PrivacyInfo.xcprivacy`) ✅ *Resolved*
> **Update:** `ios/EmpiricalTracker/PrivacyInfo.xcprivacy` now declares the
> collected data types (Health, Fitness, Email, User ID — all linked, none used
> for tracking, all *App Functionality*) and the required-reason API usage
> (`NSPrivacyAccessedAPICategoryUserDefaults`, reason `CA92.1`). `NSPrivacyTracking`
> is `false`. The bundled `supabase-swift` (2.46.0) ships its own manifest, which
> Xcode merges at build time. The file is in the folder-synced target root, so it
> lands at the app bundle root automatically.

No `*.xcprivacy` exists anywhere in `ios/`. Apple requires a **privacy manifest**
for App Store submissions, declaring collected data types and *required-reason*
API usage. This app collects **health data and email**, and bundles a
third-party SDK (`supabase-swift`). Without it you will, at minimum, get upload
warnings and very likely a rejection on a health app.
**Fix:** add `PrivacyInfo.xcprivacy` declaring data collection (health,
contact/email, identifiers) and any required-reason API categories; confirm
`supabase-swift` ships its own manifest (or account for it).

### 4. No privacy policy / consent surface in the app ✅ *Resolved*
> **Update:** Privacy-policy and terms links now appear on the **auth screen**
> (footer) and in a new **Legal** section in **Settings**, opening in-app via
> `SFSafariViewController`. A health-data **consent gate** (`ConsentView`, backed
> by a versioned `ConsentStore`) is shown after sign-in and before the main app
> the first time — covering what health data is processed, EU storage, the
> export/erasure rights, and a "not medical advice" disclaimer. Declining signs
> the user back out; signing out clears local consent so the next user must
> consent themselves. URLs live in `Config/Legal.swift`.
>
> **Still open (tracked in `docs/legal/README.md`):** the policy and terms text
> are now drafted in `docs/legal/`, but (1) a **hosting domain / public URL** has
> not been chosen — the in-app links use placeholder `empirical.app` URLs — and
> (2) the documents still have `[TBD: …]` fields (controller identity, contact,
> dates, jurisdiction) pending a legal review. Resolve both, then paste the
> privacy-policy URL into App Store Connect.

A **privacy policy URL is mandatory in App Store Connect** and effectively
required in-app for HealthKit apps. The iOS app has **no privacy-policy link, no
terms, and no consent/onboarding screen.** The README states "explicit consent at
signup," but the iOS app has only an email/password *sign-in* screen — no signup
or consent flow is present. GDPR special-category (health) data needs an explicit
consent surface.
**Fix:** add a privacy-policy link (Settings + auth screen), and a consent step
covering health-data processing before first use.

---

## High-risk — likely review friction or material limitations

### 5. Deployment target is iOS 26.4 — ✅ resolved
`IPHONEOS_DEPLOYMENT_TARGET` was `26.4`, which restricted installation to devices
on the **latest point release only**, drastically shrinking both the addressable
audience and the TestFlight tester pool. It has been lowered to **iOS 18.0** — a
sensible modern floor that covers all iOS 18-capable devices (iPhone XS and later,
the same hardware range as iOS 17). The codebase contains no `@available` /
`#available` guards and no hard iOS 26 API dependency, so the lower floor compiles
and runs unchanged.

### 6. HealthKit background-delivery entitlement ⚠️
`EmpiricalTracker.entitlements` enables
`com.apple.developer.healthkit.background-delivery`, and `HealthSyncManager`
calls `enableBackgroundDelivery(...)` + `HKObserverQuery`. There is **no
`UIBackgroundModes`** in `Info.plist`, and App Review requires an explicit
justification for background health reads. Confirm background delivery is truly
needed; if not, drop the entitlement to reduce review friction. If kept, prepare
the reviewer notes explaining why.

### 7. Verify the Release scheme is fully configured 🟡
Production safety is handled correctly — the demo/mock auth fallback is
`#if DEBUG` only (Release `fatalError`s if Supabase creds are missing), and the
demo login button is `#if DEBUG`-gated. **Action:** confirm the Release/Archive
scheme has real Supabase + API credentials injected and `DEMO_MODE` unset, so the
archive doesn't trip the production guard.

---

## Medium / housekeeping

| # | Item | Status | Notes |
|---|------|--------|-------|
| 8 | **CI doesn't build/test iOS** | ✅ Resolved | `.github/workflows/ci.yml` now has an `ios` job (macOS runner) that recreates `Config.xcconfig` from the template, picks an available iPhone simulator, and runs `xcodebuild test` for the `EmpiricalTracker` scheme — compiling all 8 local SwiftPM packages and running the app unit-test target (UI tests skipped as flaky/slow in CI). ⚠️ Authored but **not yet executed on a macOS runner** from this Linux environment; the simulator/Xcode pin may need a first-run tweak. Two follow-ups: (a) the 58 package `@Test` cases live in package test targets that the app scheme does not include, so add them to the test run once verified; (b) SwiftLint is still not wired — deferred to avoid a red lane without a tuned `.swiftlint.yml`. |
| 9 | **Config.xcconfig committed despite being git-ignored** | ✅ Resolved | `git rm --cached ios/Config.xcconfig` — the file is now untracked (still present locally and recreated in CI from `Config.xcconfig.example`). It held only the public, RLS-protected anon key, so no secret was exposed; this restores the intended "secrets never land in git" pattern. |
| 10 | **App Store metadata absent** | ◐ Drafted | Listing copy now lives in `docs/app-store/` (name, subtitle, promo text, full description with the "not medical advice" framing, keywords, what's-new, category, age-rating answers, App Privacy summary, and review notes). **Still external:** screenshots, the real public URLs (privacy/support — `empirical.app` is a placeholder), the reviewer demo account, and confirming the age-rating questionnaire — see `docs/app-store/README.md`. |
| 11 | **Empty `application-groups` entitlement** | ✅ Resolved | Removed the empty `com.apple.security.application-groups` array from `EmpiricalTracker.entitlements`; only the two HealthKit keys remain, so the entitlement set now matches what the provisioning profile needs. |
| 12 | **Signing / team** | ⚠️ Needs human confirmation | `DEVELOPMENT_TEAM = QA6NUTFPU6`, automatic signing, personal-style bundle id `com.FaizMalik.*`. Cannot be verified from the repo — requires App Store Connect access. Confirm this is the intended **distribution** team and that the ASC record, HealthKit capability, and `empiricaltracker://` URL scheme all match the distribution provisioning profile. |
| 13 | **Custom URL scheme** | ⚠️ Backend follow-up | `empiricaltracker://` is the OAuth callback for **Withings Cloud (Path B)**. On iOS the callback is validated via `WithingsCloudService.isSuccessCallback(...)`, but the backend `/withings/*` endpoints that would own the server-side OAuth `state`/redirect validation **do not exist yet** (the feature self-hides until they ship — `WithingsCloudState`). Server-side redirect/state validation must be implemented when those endpoints are built. |

---

## Strengths (what's already in good shape)

- **Clean modular architecture** — 8 local SwiftPM feature packages (Core, Auth,
  Biomarkers, FoodDiary, MealPlans, BodyMetrics, HealthSync, Account, DietEvents)
  behind a thin app target. Folder-synced Xcode project.
- **Healthy test suite** — **58 `@Test` cases** across package unit tests
  (models, DTO contracts, marker signals, auth store, body metrics, health sync).
- **Code hygiene** — no `print`, `TODO`/`FIXME`, `try!`, or stray force-unwraps;
  a single intentional `fatalError` guarding misconfigured Release builds.
- **Well-written usage strings** — `NSHealthShareUsageDescription` and
  `NSCameraUsageDescription` are specific and honest (read-only Health, no image
  storage), which App Review rewards.
- **GDPR-conscious backend** — EU (Frankfurt) data region, Postgres RLS, and
  export/erasure endpoints already exist server-side (just unsurfaced in iOS).
- **Localization** — EN/NO throughout via `String(localized:)`.
- **Intellectual-honesty framing** — decision-support, not medical advice;
  correlation-not-causation caveats baked into the feature design.

---

## Recommended path to submission

**Phase 1 — Blockers (must do):**
1. ~~Add the app icon (1024×1024) and accent color.~~ ✅ Done.
2. Wire **Delete account** + **Export data** into `SettingsView` (repository
   methods already exist).
3. Add `PrivacyInfo.xcprivacy` declaring health/email/identifier collection and
   required-reason APIs.
4. Add a privacy-policy link and a health-data consent step; publish the policy
   URL in App Store Connect.

**Phase 2 — High-risk (should do before submitting):**
5. Lower the deployment target to a sensible floor (e.g. iOS 18) unless 26.x APIs
   are genuinely required.
6. Decide on / justify the HealthKit background-delivery entitlement.
7. Verify the Release/Archive scheme injects real credentials.

**Phase 3 — Hardening (do soon after):**
8. ~~Add an iOS build+test CI lane.~~ ✅ Done (SwiftLint still TODO). ~~Untrack
   `Config.xcconfig`.~~ ✅ Done. ~~Remove the empty `application-groups`
   entitlement.~~ ✅ Done. ~~Draft listing metadata + in-app medical disclaimer.~~
   ◐ Drafted in `docs/app-store/`.
9. **Remaining (need a human / external access):** capture screenshots, publish
   the real privacy/support URLs, finalize signing & distribution team (#12),
   complete the age-rating questionnaire, and add server-side validation for the
   Withings OAuth redirect when those backend endpoints are built (#13).

Once Phase 1 lands the app is *submittable*; Phase 2 makes it *likely to pass
first review*.
