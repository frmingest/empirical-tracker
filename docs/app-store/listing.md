# App Store listing — Empirical Tracker

> Draft copy for App Store Connect. Character limits noted in brackets are
> Apple's hard caps. Placeholder URLs use the unconfirmed `empirical.app`
> domain — replace before submission (see `README.md`).

## App information

- **Bundle ID:** `com.FaizMalik.EmpiricalTracker`
- **Primary category:** Health & Fitness
- **Secondary category:** Medical *(optional — review the stricter Medical-app
  expectations before selecting)*
- **Primary language:** English (U.S.). Norwegian (NO) localization also ships.

## Name `[≤30]`

```
Empirical Tracker
```

## Subtitle `[≤30]`

```
Biomarkers, diet & body data
```

## Promotional text `[≤170]`

```
See how your diet and habits move your blood biomarkers over time. Log labs, meals, weight and BP in one place — and share a clean PDF with your doctor.
```

## Description `[≤4000]`

```
Empirical Tracker helps you connect the dots between what you do and what your
body shows. Log your blood biomarkers, food, and body metrics in one private
place, then watch how they trend together over weeks and months.

WHAT YOU CAN TRACK
• Blood biomarkers — enter lab results and see each marker trend against its
  reference range, grouped by category (lipids, metabolic, liver, and more).
• Food diary — search whole foods and packaged products, or scan a barcode, to
  log meals and macros.
• Body metrics — weight, waist, and blood pressure, manually or read from Apple
  Health (including readings your Withings devices write there via Health Mate).
• Diet events — mark when you start or change a way of eating, so you can see
  what happened to your markers afterward.

MADE FOR REFLECTION, NOT DIAGNOSIS
Empirical Tracker is a decision-support and journaling tool — not a medical
device, and not a substitute for professional care. It shows you correlations
in your own data; correlation is not causation. Always discuss changes to diet,
medication, or treatment with a qualified clinician.

SHARE WITH YOUR DOCTOR
Generate a clean PDF report of the categories and markers you choose — latest
values and/or trend graphs — and share it through the standard iOS share sheet
before your next appointment.

YOUR DATA, YOUR CONTROL
• Apple Health is read-only — the app never writes to Health, and only reads the
  data types you enable.
• Data is stored in the EU (Frankfurt).
• Export your data or delete your account at any time, from inside the app.

Available in English and Norwegian.
```

## Keywords `[≤100, comma-separated, no spaces after commas]`

```
biomarker,blood test,lab results,cholesterol,health log,diet tracker,macros,blood pressure,weight,labs
```

## What's New (v1.0) `[≤4000]`

```
First release. Track blood biomarkers, food, and body metrics in one place,
see how they trend together, and share a PDF summary with your doctor.
```

## URLs

| Field | Value | Status |
|-------|-------|--------|
| **Support URL** *(required)* | `https://frmingest.github.io/empirical-tracker/support` | ✅ GitHub Pages |
| **Marketing URL** *(optional)* | `https://frmingest.github.io/empirical-tracker/` | ✅ GitHub Pages |
| **Privacy Policy URL** *(required)* | `https://frmingest.github.io/empirical-tracker/privacy` | ✅ matches `Legal.swift` — enable GitHub Pages first |

## Age rating (questionnaire — confirm against the live form)

- **Medical/Treatment Information:** *Infrequent/Mild* — the app surfaces
  reference ranges and decision-support framing, explicitly **not** diagnosis.
- All other categories (violence, sexual content, gambling, etc.): **None**.
- **Unrestricted web access:** No (in-app links open the privacy policy/terms
  only, via SFSafariViewController).
- Expected resulting rating: **17+** if "Medical/Treatment Information" is
  flagged at all; confirm at submission.

## App Privacy ("nutrition label") summary

Mirror of `ios/EmpiricalTracker/PrivacyInfo.xcprivacy`. All data is used for
**App Functionality only**, **linked** to the user's identity, and **not** used
for tracking.

| Data type | Collected | Linked | Tracking | Purpose |
|-----------|-----------|--------|----------|---------|
| Health & Fitness | Yes | Yes | No | App Functionality |
| Email address | Yes | Yes | No | App Functionality (account) |
| User ID | Yes | Yes | No | App Functionality (account) |

## App Review notes

```
ACCOUNT REQUIRED
The app is behind an email/password sign-in. Demo credentials for review:
  • Email: [TBD — provision a reviewer account]
  • Password: [TBD]

HEALTHKIT
The app reads (never writes) weight and blood pressure from Apple Health to chart
them alongside blood biomarkers. See NSHealthShareUsageDescription. The
HealthKit background-delivery entitlement is used to refresh new readings; if you
need the justification, it is: keep imported body metrics current without the
user reopening the app.

NOT A MEDICAL DEVICE
The app is decision-support/journaling only and presents reference ranges and
correlation-not-causation caveats throughout. It does not diagnose or treat.

ACCOUNT DELETION
Users can delete their account and export their data from Settings (Guideline
5.1.1(v)).
```
