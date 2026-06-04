# App Store Submission — Go / No-Go Checklist

**Owner:** Release & Compliance
**Last reviewed:** 2026-06-04
**Build under review:** marketing `1.0` (build `1`), bundle `com.FaizMalik.EmpiricalTracker`
**Current verdict:** 🔴 **NO-GO** — engineering is ready; legal/release artifacts and
one CI failure are outstanding.

This is the single go/no-go gate for an App Store Connect submission. Each row was
**verified against source** (code, entitlements, `PrivacyInfo.xcprivacy`, the legal
drafts, and the test suite), not taken from prior write-ups. Sources cross-checked:
`docs/IOS_APP_STORE_READINESS.md`, `docs/adr/026-security-risk-compliance.md`,
`docs/app-store/listing.md`, `docs/legal/README.md`.

**Legend:** ✅ done · ◐ partial · ⚠️ needs human/external action · 🔴 hard blocker · — n/a

---

## Decision rule

**GO only when every 🔴 row is ✅ and the test suite is green.** The 🔴 rows are
either Apple submission-blockers (no upload possible) or guaranteed-rejection items
(reviewer can't use the app, invalid privacy policy). The 🟠 rows are strong
recommendations to clear before first review; the governance rows are GDPR exposures
to close before scaling.

---

## A. Hard blockers — must be ✅ to submit 🔴

| # | Item | Status | Evidence / action |
|---|------|--------|-------------------|
| A1 | **Privacy-policy URL is real & reachable** | 🔴 Open | `Config/Legal.swift` ships placeholder `https://empirical.app/privacy`. Choose hosting, publish `docs/legal/privacy-policy.md`, update `Legal.swift`, paste URL into ASC ▸ App Privacy. Mandatory for any app; doubly enforced for HealthKit. |
| A2 | **Legal docs have no `[TBD]` left + legal review** | 🔴 Open | 10 `[TBD]` in `privacy-policy.md`, 5 in `terms-of-service.md`: controller legal identity, contact email, effective date, minimum age, governing jurisdiction. A policy with no named controller/contact is not GDPR-valid. |
| A3 | **Support URL is real & reachable** | 🔴 Open | `listing.md` placeholder `https://empirical.app/support`. A support URL is required in ASC. |
| A4 | **Reviewer demo account provisioned** | 🔴 Open | `listing.md` review notes: `Email/Password: [TBD]`. App is behind a sign-in wall with no in-app signup flow — without working creds App Review cannot enter → automatic rejection. |
| A5 | **Screenshots captured (per required display size)** | 🔴 Open | None in repo. Capture Dashboard, a biomarker trend, Food diary, Body metrics, doctor-PDF report. |
| A6 | **Test suite green** | ✅ Done | `pytest -q` now green (181 passed / 7 skipped). The failing `test_auth_jwt.py` case asserted a fail-closed `401` for an unverifiable ES256 token; the documented, internally-consistent design defers to the authoritative network check (mirrors the HS256 no-secret path). Test corrected to assert `is None` (renamed `test_es256_no_jwks_falls_back_to_network`) with the security rationale. |

---

## B. High-risk — clear before / at first review 🟠

| # | Item | Status | Evidence / action |
|---|------|--------|-------------------|
| B1 | **Anthropic (US) disclosed as sub-processor** | ◐ Drafted | `privacy-policy.md` §5 now lists Anthropic (US) and a label-scanner explainer, and §7 (International transfers) discloses the US transfer instead of asserting "None." **Still ⚠️:** execute the Anthropic DPA + confirm the SCC safeguard (`[TBD]` in policy + `docs/legal/README.md`). (ADR-026 F8) |
| B2 | **Stop logging OCR text / parsed fields** | ✅ Done | `label_parser.py` no longer logs OCR text, the model response, or parsed values — only sizes/counts/outcomes (ADR-026 F10). |
| B3 | **Signing & distribution team confirmed** | ⚠️ Human | `DEVELOPMENT_TEAM = QA6NUTFPU6`, automatic signing, personal-style bundle id. Confirm intended *distribution* team and that ASC record, HealthKit capability, and URL scheme match the distribution profile. Needs ASC access. |
| B4 | **HealthKit background-delivery justified or dropped** | ⚠️ Decide | Entitlement enabled and used (`HKObserverQuery` + `enableBackgroundDelivery`). Keep + supply reviewer justification (drafted in `listing.md`) or drop to reduce friction. |
| B5 | **Release/Archive scheme injects real creds, `DEMO_MODE` unset** | ⚠️ Human | Release `fatalError`s if Supabase creds missing and the demo login is `#if DEBUG`-gated (verified). Confirm the archive scheme has real Supabase + API credentials. |
| B6 | **Age-rating questionnaire confirmed** | ⚠️ Open | `listing.md` drafts "Medical/Treatment Information: Infrequent/Mild" → expected 17+. Confirm against the live ASC form. |
| B7 | **Export-compliance answer confirmed** | ⚠️ Open | Standard HTTPS/TLS only → typically "uses encryption, exempt." Confirm at upload. |

---

## C. Governance — GDPR exposures to close before scaling 🟡

| # | Item | Status | Evidence / action |
|---|------|--------|-------------------|
| C1 | **Server-side consent record (demonstrable Art. 9)** | Open | `ConsentStore` is local `UserDefaults` only — no auditable who/when/which-version record. Add a `consents` table. (ADR-026 F7 / P2) |
| C2 | **Audit logging + breach runbook (Art. 33/34)** | Open | No access logging for health data; no documented breach-response runbook. (ADR-026 F10 / P2) |
| C3 | **Data-retention / minimization policy documented** | Open | Referenced as missing in ADR-026 compliance closeout. |
| C4 | **Service-key rotation documented** | Open | Single high-value secret (service role); rotation procedure undocumented. |
| C5 | **Withings OAuth server-side `state`/redirect validation** | Deferred | `empiricaltracker://` callback; backend `/withings/*` endpoints not built — feature self-hides. Not a v1 blocker; do not enable the user-facing path until server-side `state` validation ships. (ADR-026 / readiness #13) |

---

## D. Confirmed ready — no action ✅

Verified present in source; listed so reviewers don't re-litigate them.

| Item | Evidence |
|------|----------|
| App icon (1024² opaque) + accent color | `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` wired in `Contents.json` |
| In-app account deletion (Guideline 5.1.1(v)) | `Features/Settings/DeleteAccountView.swift` → `deleteAccount(confirmation:)`, presented from `SettingsView` |
| In-app data export (GDPR Art. 20) | `SettingsView` JSON/CSV → `exportData(format:)` |
| Privacy manifest | `PrivacyInfo.xcprivacy`: Health/Fitness/Email/UserID (linked, no tracking, App Functionality); `CA92.1`; `NSPrivacyTracking=false` |
| Health-data consent gate (Art. 9) | `ConsentView` enforced in `App/RootView.swift`; versioned `ConsentStore` |
| In-app privacy/terms links | `SettingsView` Legal section + auth footer via `SFSafariViewController` |
| Deployment floor | `IPHONEOS_DEPLOYMENT_TARGET = 18.0` (was 26.4) |
| Entitlements minimal | Only the two HealthKit keys; empty `application-groups` removed |
| RLS enforced on live API path (Art. 25) | ADR-026 F1: fail-closed `get_supabase()`; service role reserved for account erasure |
| Security hardening | F2 rate limits, F3 upload caps + magic-byte/zip-bomb checks, F4 OCR length cap, F5 local JWT verify, F6 device-only Keychain, F9 de-wildcarded CORS |
| Listing copy drafted | `docs/app-store/listing.md` (name, subtitle, description, keywords, review notes) |

---

## Sign-off

| Role | Name | Date | Decision |
|------|------|------|----------|
| Engineering lead | | | ☐ Ready |
| Compliance / DPO | | | ☐ Ready |
| Release owner | | | ☐ GO / ☐ NO-GO |

**A submission may proceed only when Section A is fully ✅ and the sign-off row reads GO.**
