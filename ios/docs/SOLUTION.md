# Empirical Tracker — Solution Overview

> The "why" behind the product and the map of major design decisions. For the
> engineering execution plan see
> [`EmpiricalTracker/IOS_MIGRATION_PLAN.md`](../EmpiricalTracker/IOS_MIGRATION_PLAN.md);
> for individual decisions see [`docs/adr/`](adr/) (the canonical ADR set).

---

## What the app is

Empirical Tracker is a **decision-support** tool for people running deliberate
dietary regimens — carnivore, low-carb, fasting — who want to see how those
regimens move their **blood biomarkers** and **body's headline signals** over
time. It is explicitly **not** medical advice: every marker, correlation, and
diet note carries a clinician-review disclaimer, and the app never interprets a
value or sets a clinical recommendation on the user's behalf.

The product has three data surfaces, all correlated on a shared timeline:

1. **Biomarkers** — imported from lab `.xlsx` files, categorized, charted with
   reference bands, clinical-target lines, and within-range trend signals.
2. **Food diary** — daily logging from three nutrition databases, with macros,
   sodium, and saturated fat.
3. **Body metrics** — weight, waist, and blood pressure (and, on iOS, Withings
   data via Apple HealthKit and the Withings Cloud API).

**Diet events** annotate every chart so the user can see *visual correlation*
(never claimed causation) between a regimen change and a marker's movement.

## Architecture in one paragraph

A platform-agnostic **FastAPI + Supabase** backend owns all clinical logic,
parsing, the multi-source food proxy, and GDPR export/erasure, with row-level
security on `user_id`. The original client is a Next.js web app; the **iOS app**
(this repository) is a native SwiftUI client of the *same* backend — it
re-implements only the presentation layer, navigation, charts, and native-device
features (barcode scanning, HealthKit), and adds Withings capture. See the
migration plan for the reuse rationale and sprint breakdown.

---

## Clinical-feedback roadmap

A clinical review of the app surfaced a cluster of findings: the product treated
the lab **reference range** as if it meant **healthy**, omitted several of the
*most* informative markers and nutrients for its target diets, and tracked some
diet-confounded markers without that caveat. The findings were triaged by
severity and addressed across a sequence of ADRs. Each row links the finding to
the decision record that resolves it.

| # | Finding | Severity | Decision record | Status |
|---|---------|----------|-----------------|--------|
| 1 | "In range" hides "above clinical target" (e.g. LDL green at 4.1 mmol/L); "in range" also hides a sharp within-range trend (e.g. ALT 25→55 U/L). | High | [ADR-014](adr/014-clinical-targets-trend-signals.md) — clinical-target layer + trend signals | Shipped |
| 2 | High-yield markers absent (refeeding electrolytes, etc.); two diet profiles list markers they don't carry; some tracked markers are diet-confounded yet shown without a caveat. | High | [ADR-015](adr/015-panel-expansion-confounder-notes.md) — panel expansion + confounder notes | Shipped (High slice); derived ratios deferred |
| 3 | The diary omitted the two nutrients the biomarker side cares about most — **sodium** (electrolytes / blood pressure) and **saturated fat** (LDL response); energy showed "—" when only kJ was published. | High / Low | [ADR-016](adr/016-food-diary-sodium-saturated-fat.md) — sodium & saturated fat + kJ→kcal fallback | Shipped |
| 4 | Open Food Facts is a branded/barcode database and is weakest on the **whole foods** these diets live on; no micronutrients to meet the Nutrients panel. | Medium | [ADR-018](adr/018-whole-foods-data-sources.md) — Matvaretabellen + USDA whole-food sources | Shipped (macros, Phases 1–2); micronutrients deferred |
| 5 | For diet tracking, **weight, waist, and blood pressure** respond faster and often matter more than most labs, yet the app held no body metrics. | Medium | [ADR-017](adr/017-body-metrics.md) — body metrics + longitudinal context | Shipped |

### Deferred follow-ups (tracked, not yet built)

- **Derived ratios** — TG/HDL and AST:ALT in a dedicated "Derived" section,
  marked *calculated, not measured* (ADR-015).
- **Further markers** — fasting insulin / C-peptide, fasting glucose, hs-CRP,
  AST/ASAT (ADR-015).
- **Daily intake targets / needs**, including **protein in g/kg body weight** —
  unblocked now that body weight is stored (ADR-016 / ADR-017).
- **Whole-food micronutrients** — carry the `micronutrients` map through to
  storage and intake totals, then wire selected micronutrients to their biomarker
  counterparts (iron→ferritin, B12, vitamin D, magnesium). This closes the app's
  core diet ⇄ biomarker loop and is its own sprint (ADR-018, Phase 3).

---

## iOS delivery status

The iOS client is being built sprint-by-sprint against the migration plan. Live
status lives in the [README](../README.md#sprint-status). As of this writing the
read path, biomarker detail, Excel import, diet events, the **food diary
(Sprint 6, [ADR-019](adr/019-ios-food-diary-barcode-scanning.md))**, **meal
plans & calendar (Sprint 7, [ADR-020](adr/020-ios-meal-plans-calendar.md))**,
**body metrics (Sprint 8, [ADR-021](adr/021-ios-body-metrics.md))** — log plus
three diet-event-overlaid trend charts — and the **Apple HealthKit Withings bridge
(Sprint 9, [ADR-022](adr/022-ios-healthkit-withings-sync.md))** are complete. The
HealthKit path imports **weight and blood pressure** that Withings devices write to
Apple Health via Health Mate, tagging them `source: healthkit` and deduping by sample
UUID.

**Sprint 10 (Withings Cloud API — Path B,
[ADR-023](adr/023-ios-withings-cloud-connection.md))** is in progress: the **iOS
connection flow** is shipped — "Connect Withings account" opens the OAuth consent page in
`ASWebAuthenticationSession`, with connection status, "Sync now", and disconnect surfaced
on the Body tab and in Settings. No Withings tokens touch the device; the backend owns the
token exchange and webhooks. The client **self-hides until the backend exposes the
`/withings/*` endpoints**, so it activates automatically when that work deploys. Richer
body-composition signals (body-fat %, lean mass, resting HR) and the server-side OAuth
token exchange, history pull, and `Notify` webhooks remain outstanding **backend** work,
pending the `withings_measures` table and OAuth/webhook endpoints (migration plan
§4.2–§4.4).

> ADR sprint numbers: ADRs 011–018 were authored against the **web** app and
> carry its sprint numbering; the iOS work re-sequences the same surface per the
> migration plan (e.g. the food diary is iOS Sprint 6). ADR-019 onward use iOS
> numbering (ADR-021 = iOS Sprint 8 body metrics, realising the chart design from
> the web-numbered ADR-017).
