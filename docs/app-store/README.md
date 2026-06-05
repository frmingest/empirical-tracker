# App Store listing — source of truth

This folder holds the **App Store Connect listing copy** for Empirical Tracker so
the metadata lives in version control instead of only in the App Store Connect
web UI. Paste these values into App Store Connect ▸ *App Information* /
*Version* when preparing a submission (or wire them up with `fastlane deliver`
later — the field names below match its `metadata/en-US/*.txt` convention).

## What's here

- [`SUBMISSION_CHECKLIST.md`](SUBMISSION_CHECKLIST.md) — the **go/no-go gate**:
  source-verified blockers, high-risk items, governance exposures, and the
  sign-off row. Start here before any submission.
- [`listing.md`](listing.md) — name, subtitle, promotional text, full
  description, keywords, what's-new, category, URLs, age-rating answers, App
  Privacy nutrition-label summary, and App Review notes.

## Still needed before submission (cannot be produced from the repo)

| Item | Status | Owner action |
|------|--------|--------------|
| **Screenshots** (6.7", 6.5", and iPad if shipping universal) | ❌ Missing | Capture on device/simulator — Dashboard, a biomarker trend, Food diary, Body metrics, the doctor-PDF report. Min. one set per required display size. |
| **App preview video** | Optional | Skip for v1. |
| **Privacy-policy URL** | ⚠️ Placeholder | Host `docs/legal/privacy-policy.md`, then put the public URL here **and** in App Store Connect ▸ App Privacy. Currently `https://empirical.app/privacy` (unconfirmed domain — see `docs/legal/README.md`). |
| **Support & Marketing URL** | ⚠️ Placeholder | Same unconfirmed `empirical.app` domain. A support URL is **required**. |
| **Age-rating questionnaire** | ⚠️ Draft answers | Confirm the answers in `listing.md` against the live questionnaire — health/decision-support content affects the rating. |
| **Export-compliance answer** | ❓ Confirm | App uses only standard HTTPS/TLS → typically "uses encryption" but **exempt**. Confirm at upload. |

## Hard constraints to remember at submission time

- A **privacy-policy URL is mandatory** for any app, and doubly enforced for a
  HealthKit app — submission is blocked without it.
- The listing and the in-app copy must both carry the **"not medical advice"**
  framing (decision-support, correlation-not-causation). It is already in the
  feature design; keep it visible in the description below.
- App Review needs a **working demo account** (or the reviewer cannot get past
  the sign-in wall). See the review notes in `listing.md`.
