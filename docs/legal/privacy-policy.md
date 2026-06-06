# Privacy Policy — Empirical Tracker

**Last updated:** 4 June 2026
**Applies to:** the Empirical Tracker iOS app and its backend services.

Empirical Tracker ("the app", "we", "us") helps you track how your diet relates
to your blood biomarkers and body metrics. Because the app processes **health
data**, which is special-category data under the GDPR, we treat your privacy as a
first-class concern. This policy explains what we collect, why, how we protect
it, and the rights you have over it.

## 1. Who is responsible for your data

The data controller for the purposes of the GDPR is:

> Faiz Malik
> Contact: frmingest@gmail.com

If we ever appoint a Data Protection Officer or EU representative, their details
will be added here.

## 2. What data we collect

We only collect what the app needs to work. We do **not** sell your data, and we
do **not** use it for advertising.

| Category | Examples | Why we hold it |
|---|---|---|
| **Account** | Email address, authentication identifiers (Supabase user id) | To create and secure your account |
| **Health & body data** | Blood biomarkers you import or enter, weight, waist, blood pressure | The core function: charting your results over time |
| **Diet data** | Food diary entries, meal plans, diet events | To correlate diet with your biomarkers |
| **Apple Health (optional)** | Weight and blood-pressure readings you choose to share | To chart them alongside your biomarkers — **read-only**, we never write to Apple Health |
| **Connected devices (optional)** | Withings measurements, if you connect Withings Cloud | To import body metrics automatically |
| **Technical** | Minimal logs needed to operate and secure the service | Security, debugging, and abuse prevention |

We do **not** use third-party advertising or analytics SDKs on your health data.

## 3. Legal basis for processing

- **Health and body data (special category):** your **explicit consent** under
  GDPR Article 9(2)(a), captured in the app before processing begins. You can
  withdraw it at any time (see Section 8).
- **Account and technical data:** performance of our agreement with you and our
  legitimate interest in operating a secure service (Article 6(1)(b) and (f)).

## 4. How your data is stored and protected

- **EU data residency.** Your personal health and account data is stored in the
  EU (Supabase, Frankfurt / `eu-central-1`).
- **Isolation by design.** Every record is scoped to your account with
  PostgreSQL Row-Level Security, enforced by the database itself, so one user can
  never read another's data.
- **Authenticated access.** Every API request is validated against a live
  authentication token before any data is touched.
- **Encryption in transit.** All traffic uses HTTPS/TLS.
- **Apple Health stays on-device** under iOS's HealthKit protections; we only
  read the specific types you enable.

## 5. Who we share data with (sub-processors)

We use a small number of service providers strictly to run the app. They process
data on our behalf and only as needed:

| Provider | Purpose | Location | Transfer mechanism |
|---|---|---|---|
| Supabase | Database, authentication, storage | EU (Frankfurt) | Within EEA — no transfer |
| Railway | Backend API hosting | US (East) | Standard Contractual Clauses |
| Anthropic | Nutrition-label OCR parsing (food diary feature) | US | Standard Contractual Clauses |
| Apple (HealthKit) | On-device health data you choose to share | Your device | Within EEA — on-device only |
| Withings (optional) | Device measurements, only if you connect it | EU (France) | Within EEA — no transfer |

**Anthropic note:** when you use the barcode/label scanner, the OCR text from the
nutrition-facts panel is sent to Anthropic's API to extract structured nutrient
values. No other personal data is sent. We have a Data Processing Agreement and
rely on Standard Contractual Clauses for this transfer.

Reference nutrition data (e.g. Open Food Facts, the Norwegian Matvaretabellen,
and USDA) is fetched through our backend; your personal data is **not** sent to
those sources.

We do not sell or rent your personal data, and we only disclose it where legally
required.

## 6. How long we keep it

We keep your data for as long as your account is active. When you delete your
account (Section 8), we erase your health, diet, body, and account data from our
systems. Minimal security logs may persist for a short period as required for
fraud prevention and legal compliance.

**Items you choose to share to the common catalogue** — custom foods and recipes
you mark as public — are kept as **anonymised facts** (e.g. a product's name,
brand, and nutrition values, or a recipe's ingredients and steps) for the benefit
of all users. When you share such an item we make this anonymised copy, stripped
of any link to you (no user identifier, no timestamps tied to your activity, and
never a scanned-label image or photo). Because that copy is no longer personal
data, it is retained even after you delete the item or your account. Anything you
keep **private** is never copied and is fully erased.

## 7. International transfers

Where data is transferred outside the EU/EEA (to Railway for API processing and
to Anthropic for label parsing), we rely on Standard Contractual Clauses (SCCs)
as the transfer mechanism. Your stored health data remains in the EU at all times.

## 8. Your rights

Under the GDPR you can, at any time:

- **Access** the data we hold about you.
- **Export / portability** — download your data in JSON or CSV from
  **Settings ▸ Account** in the app.
- **Erasure** — delete your account and data from **Settings ▸ Account**.
- **Rectify** inaccurate data.
- **Withdraw consent** to health-data processing (deleting your account
  withdraws it and removes the data).
- **Object to or restrict** certain processing.
- **Lodge a complaint** with your supervisory authority. In Norway this is the
  Norwegian Data Protection Authority (Datatilsynet); in other EU/EEA countries,
  your national authority.

To exercise rights that aren't self-service, contact us at frmingest@gmail.com.

## 9. Children

Empirical Tracker is not intended for children. You must be at least **16 years
old** to use it.

## 10. Not medical advice

Empirical Tracker is a personal decision-support tool. It shows **correlations,
not causes**, and is **not** a medical device or a substitute for professional
medical advice, diagnosis, or treatment. Always consult a qualified clinician
about your health.

## 11. Changes to this policy

We may update this policy. Material changes will be reflected by the "Last
updated" date above and, where appropriate, surfaced in the app.

## 12. Contact

Questions about this policy or your data: frmingest@gmail.com
