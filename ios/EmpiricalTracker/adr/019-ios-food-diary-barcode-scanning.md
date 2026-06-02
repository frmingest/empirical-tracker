# ADR-019: iOS food diary — native barcode scanning & multi-source client

**Status:** Accepted
**Date:** 2026-06-02
**Author:** iOS team
**Sprint:** 6 (iOS)

---

## Context

The backend already exposes a complete, multi-source food diary: Open Food Facts
for branded/barcode products, plus the Matvaretabellen and USDA whole-food
composition tables (ADR-018), with sodium and saturated fat on every entry
(ADR-016). Until this sprint the iOS app had only a **scaffolded repository** and
a placeholder Diary tab — the Core DTOs still carried the original four macros
and no provenance, and there was no UI.

iOS Sprint 6 (see `EmpiricalTracker/IOS_MIGRATION_PLAN.md` §3) brings the diary to
feature parity with the web client **and** adds the one thing a phone can do that
the browser cannot: scan a barcode with the camera. No backend changes are
required — this is a pure presentation + native-device sprint, consistent with
the migration plan's "reuse the backend" principle (§1.1).

> Numbering note: ADR-016 and ADR-018 carry the **web** sprint numbers (their
> Sprint 9 / 9-follow-up) because they were authored against the web app. This
> ADR uses the **iOS** sprint numbering from the migration plan, where the food
> diary is Sprint 6.

---

## Decision

### 1. Bring the Core DTOs to contract parity

Extend the shared `Core` models so the iOS client speaks the same shape the
backend already returns (`Packages/Core/Sources/Core/Models/FoodModels.swift`):

- `FoodItem` and `FoodEntry` gain `saturatedFat100g` / `saturatedFatG` (grams),
  `sodium100g` / `sodiumMg` (milligrams), and a `source`.
- `FoodEntryPayload` carries the new nutrients and `source`, and `DailyTotals`
  sums sodium and saturated fat alongside the macros.
- A new `FoodSource` enum (`off` / `mvt` / `usda`) models provenance; a separate
  `FoodSearchSource` adds `all` for the fan-out search selector.

`FoodItem.source` decodes **defaulting to `.off`** when absent, so older cached
payloads still decode. Nutrient scaling stays linear-by-mass and **never invents
a missing value** — absent fields decode to `nil` and render as "—", preserving
the as-published honesty contract (ADR-011, `docs/NUTRITION_DATA.md`).

### 2. Multi-source search via the existing proxy

The repository calls `GET /food-diary/search?q=…&source=…` (ADR-018 §2) with a
**segmented source selector** — *NO* (Matvaretabellen) / *US* (USDA) / *Branded*
(OFF) / *All*. It defaults to **Matvaretabellen**, honouring the app's
Norwegian-first framing. Search is **debounced ~400 ms** and stale responses are
dropped via task cancellation, mirroring the web client and staying within OFF's
rate limits (ADR-011). Every result row and every stored entry shows a small
**source badge** (text, not colour alone, so it survives colour-blindness).

### 3. Native barcode scanning via VisionKit

Barcode scanning uses **VisionKit's `DataScannerViewController`** wrapped in a
`UIViewControllerRepresentable`. A scanned code is looked up through the existing
OFF-only `GET /food-diary/barcode/{code}` endpoint and pre-fills the log sheet.
The scanner is offered only when the selected source supports barcodes
(`off` / `all`) — whole-food tables have no barcodes. `NSCameraUsageDescription`
is added to `Info.plist`. When scanning is unavailable (Simulator, no camera,
permission denied) the UI degrades to a clear message and the user falls back to
name search.

### 4. Free-text fallback

When nothing matches, the user can log a free-text entry (name + meal + quantity,
with **optional** manual nutrition). Blank fields stay `nil` → "—"; we still never
estimate. Free-text entries carry no `source` (provenance is genuinely unknown).

### 5. UX & parity details

- Per-day navigator (prev / next / jump-to-today), meals grouped
  (breakfast / lunch / dinner / snack / other), swipe-to-delete, pull-to-refresh.
- A daily-totals card surfaces energy + carbs/protein/fat **plus sodium and
  saturated fat**, closing the loop with the electrolyte/lipid emphasis on the
  biomarker side (ADR-016).
- Source attribution footer credits Matvaretabellen (NLOD / CC BY), USDA
  (public domain) and Open Food Facts (ODbL), per ADR-018 §6.
- Full EN/NO localisation via the String Catalog; demo/preview mock entries.

---

## Why VisionKit `DataScannerViewController` (not raw AVFoundation)

| Option | Why / why not |
|--------|---------------|
| **VisionKit `DataScannerViewController`** (chosen) | High-level, iOS 16+; built-in camera preview, region-of-interest highlighting, and guidance; a few dozen lines via a representable. Returns decoded payloads directly. |
| `AVCaptureSession` + `AVCaptureMetadataOutput` | Works back to iOS 11 but is substantially more boilerplate (session, queue, preview layer, orientation) for no benefit at our iOS 17 floor. |
| Third-party scanner SDK | Unnecessary dependency and licensing for a capability the platform ships natively. |

Trade-off: `DataScannerViewController` does not run in the Simulator and needs a
physical camera, so the flow is **device-tested** and guarded by an availability
check with a graceful fallback — the same posture the migration plan takes for
HealthKit (§7).

---

## Consequences

- **Good:** Full web parity for the diary plus a headline native upgrade
  (scanning); the iOS client now records and displays provenance and the two
  clinically-relevant nutrients the labs side cares about.
- **Good:** No backend work — the proxy, schema, and GDPR export/erasure are
  unchanged (the `source`/`sodium_mg`/`saturated_fat_g` columns already flow
  through `select("*")`, per ADR-016 / ADR-018).
- **Trade-off:** Barcode scanning can't be exercised in CI/Simulator; covered by
  device QA and the unsupported-state fallback.
- **Trade-off:** Provenance is per-entry metadata, not a live link — consistent
  with the "store consumed amounts" durability decision (ADR-011).

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Keep OFF-only search on iOS | Backend already multi-source (ADR-018); whole foods are the staple of the target diets and exactly where OFF is weakest. |
| Manual barcode text field (web parity) | Wastes the device's headline advantage; scanning is faster and less error-prone. |
| Compute totals server-side | The diary stores consumed amounts already; summing client-side adds zero network round-trips and matches the web math. |
| Default the source selector to *All* | *All* fans out to every source and is noisier; Matvaretabellen is the right regional default for the Norwegian-first user (ADR-018 §6). |
