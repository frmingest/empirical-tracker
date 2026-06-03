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

### 3. Missing privacy manifest (`PrivacyInfo.xcprivacy`) 🛑/⚠️
No `*.xcprivacy` exists anywhere in `ios/`. Apple requires a **privacy manifest**
for App Store submissions, declaring collected data types and *required-reason*
API usage. This app collects **health data and email**, and bundles a
third-party SDK (`supabase-swift`). Without it you will, at minimum, get upload
warnings and very likely a rejection on a health app.
**Fix:** add `PrivacyInfo.xcprivacy` declaring data collection (health,
contact/email, identifiers) and any required-reason API categories; confirm
`supabase-swift` ships its own manifest (or account for it).

### 4. No privacy policy / consent surface in the app 🛑/⚠️
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

### 5. Deployment target is iOS 26.4 ⚠️
`IPHONEOS_DEPLOYMENT_TARGET = 26.4` restricts installation to devices on the
**latest point release only**, drastically shrinking both your addressable
audience and your TestFlight tester pool. Unless a hard API dependency forces it,
lower this (e.g. iOS 17/18) to a sensible floor.

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

| # | Item | Notes |
|---|------|-------|
| 8 | **CI doesn't build/test iOS** | `.github/workflows/ci.yml` runs only Python API lint + pytest. There is no `xcodebuild`/test lane and no SwiftLint. Add an iOS build+test job so regressions are caught. |
| 9 | **Config.xcconfig committed despite being git-ignored** | `ios/Config.xcconfig` is tracked (`git ls-files`) even though it's listed in `.gitignore:39`. It holds the Supabase URL + **anon key**, which are public-by-design (RLS-protected), so not a security breach — but it defeats the intended "secrets never land in git" pattern documented in `AppConfig.swift`. No service-role key is present anywhere in `ios/` (verified). Consider `git rm --cached`. |
| 10 | **App Store metadata absent** | No screenshots, description, keywords, age rating, or support/marketing URLs in the repo. Health/decision-support app needs an accurate age rating and a visible "not medical advice" disclaimer (the feature ADRs carry this framing — surface it in-app and in the listing). |
| 11 | **Empty `application-groups` entitlement** | `com.apple.security.application-groups` is an empty array — harmless, but remove if unused so the entitlement set matches the provisioning profile. |
| 12 | **Signing / team** | `DEVELOPMENT_TEAM = QA6NUTFPU6`, automatic signing, personal-style bundle id `com.FaizMalik.*`. Confirm this is the intended distribution team and that the App Store Connect record, HealthKit capability, and `empiricaltracker://` URL scheme all match the distribution provisioning profile. |
| 13 | **Custom URL scheme** | `empiricaltracker://` is registered for the Withings OAuth callback — fine; just ensure the redirect is validated server-side. |

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
8. Add an iOS build+test (and SwiftLint) CI lane.
9. Untrack `Config.xcconfig`; finalize signing/team; prepare listing metadata,
   screenshots, age rating, and the in-app medical disclaimer.

Once Phase 1 lands the app is *submittable*; Phase 2 makes it *likely to pass
first review*.
