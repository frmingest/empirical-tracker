# Empirical Tracker — iOS Feature Wishlist

> Forward-looking feature/improvement proposals for the native iOS app, written
> from a senior-iOS-architect review of the codebase (branch
> `claude/ios-architecture-review`). These are **proposals**, not committed
> scope. The goal: make the app more useful and engaging for the end user
> (carnivore / low-carb / fasting self-trackers) while leaning on the native
> platform that the iOS rewrite exists to exploit.
>
> Cross-cutting rule (unchanged): every new number is **decision-support, not
> medical advice**. New surfaces keep the "visual correlation, not causation"
> and "general guideline, not personalised" disclaimers the app already uses.

---

## Where the app stands today (orientation)

A clean, modular SwiftUI client over the existing FastAPI + Supabase backend —
**not** a backend rewrite. Strong foundations are already in place:

- **Modular SPM architecture** — one package per domain (`Core`, `Auth`,
  `Biomarkers`, `DietEvents`, `FoodDiary`, `MealPlans`, `BodyMetrics`,
  `HealthSync`, `Account`), MVVM, with `AppEnvironment` as a single
  `@Observable` composition root owning the repositories and shared `APIClient`.
- **Typed actor-based networking** — `APIClient` with retry/backoff,
  Keychain-stored JWT, snake_case + flexible-date coding.
- **Native upgrades already shipped** — VisionKit barcode scanning, `.xlsx`
  document-picker import, Swift Charts throughout, a HealthKit bridge
  (weight + BP, `HKObserverQuery` background delivery, UUID dedupe), and a
  self-gating Withings Cloud connect flow.
- **Clinical logic ported to Swift** — `MarkerSignals`, `DietProfiles`,
  `BiomarkerCategories` (Watch / in-range / out-of-range assessment, trend
  signals, clinical targets).

**Items shipped since this wishlist was written:**

- ✅ **Doctor PDF report** (#5) — client-side selectable A4 report (`ReportShare/`).
- ✅ **Onboarding / first-run** (#12) — profile-setup screen (height, weight, waist, units, or Apple Health sync).
- ✅ **Body map glanceability** — anatomical silhouette with status pins + health-stats overlay is now the default Home view (ADR-030).

**Still-open gaps:**

- No offline cache (every read hits the network; SwiftData deferred past Sprint 11).
- No notifications/reminders, no widgets, no Siri/Shortcuts, no Apple Watch, no
  Live Activities.
- Deferred clinical value: derived ratios TG/HDL & AST:ALT, daily targets + protein
  g/kg (body weight now stored — the blocker is removed), body-metric overlay on
  biomarker charts; HealthKit covers only weight + BP (not body-fat / resting HR / sleep).

---

## Tier 1 — Native iOS features that create daily engagement

A blood-test app is opened rarely; these turn it into something glanceable and
timely, which is the whole point of being native.

### 1. Home Screen & Lock Screen widgets (WidgetKit) — 📐 Planned ([ADR-031](adr/031-ios-home-lock-screen-widgets.md))
- A **latest-panel** widget (e.g. LDL / HbA1c trend + Watch-marker count), a
  **today's macros vs target** diary widget, and a **weight-trend** widget.
- Biggest single retention lever — keeps the app present between the rare
  panel imports.
- Builds on existing data shapes (`BiomarkerWithSeries`, diary daily totals);
  needs an **App Group** + a shared read cache.
- **Plan ([ADR-031](adr/031-ios-home-lock-screen-widgets.md)):** instead of waiting
  on the SwiftData cache (#9), the app write-throughs a tiny `WidgetSnapshot` JSON to
  a shared **App Group** container that the extension reads with **no network/auth**.
  First widgets: **Latest panel** + **Weight trend**. Lock Screen is **status-only**
  by default (special-category data), with an opt-in "Show values in widgets" toggle.

### 2. Smart reminders & insight notifications (UserNotifications)
- "Time to log dinner" / "log your morning weight" (diet-event aware).
- "Your new Withings reading synced."
- "It's been ~3 months — consider booking your next panel" (lab-cadence nudge).
- **New-result insight:** "Your LDL moved into Watch on your latest panel" —
  turns the existing `MarkerSignals` assessment into a push the moment data
  arrives.

### 3. Apple Watch companion + complications
- Quick-log weight/BP from the wrist, a next-panel countdown, and a macro-ring
  complication. Withings users already live in HealthKit — a watch
  complication closes the loop.

### 4. Siri Shortcuts / App Intents
- "Log my weight," "What's my latest HbA1c?", "Add ribeye to my diary."
- App Intents also feed Spotlight and user-built Shortcuts automations — low
  friction, high "smart device" appeal.

---

## Tier 2 — Complete the deferred clinical value (differentiators)

### 5. Doctor / clinician PDF report ✅ Shipped
~~The headline missing feature.~~ Shipped as a client-side selectable A4 PDF
(`ReportShare/`): user picks categories and/or individual markers, chooses latest
values / trend graphs / both, and shares via the system share sheet. Rendered via
SwiftUI `ImageRenderer` → `CGContext`. Carries disclaimers on every page.

### 6. Daily targets & protein g/kg (Sprint 9 follow-up)
- Now that `body_metrics` stores weight, wire intake-vs-target rings into the
  diary: energy, **protein in g/kg body weight** (renal-load concern), carbs,
  saturated fat, sodium.
- Makes the diary **actionable** rather than just a log; pairs with the widget
  in #1.

### 7. Derived ratios (Sprint 8 follow-up)
- **TG/HDL** (insulin-resistance surrogate) and **AST:ALT**, in a "Derived —
  calculated, not measured" section. Pure client-side computation over existing
  series; high signal for this audience.

### 8. Body-metric overlay on biomarker charts (Sprint 10 follow-up)
- Weight behind LDL, BP behind sodium intake. The overlay machinery and data
  already exist — presentation work that delivers the app's core "does my diet
  move my numbers?" promise.

---

## Tier 3 — Depth & polish

### 9. Offline-first cache (SwiftData)
- Deferred past Sprint 11 (every read still hits the network). Instant cold-start,
  flaky-network tolerance, and a **prerequisite for widgets (#1)** to have data
  without a round-trip. High leverage — unblocks multiple Tier 1 items at once.

### 10. Richer HealthKit signals
- Extend beyond weight + BP to body-fat %, lean mass, resting HR, sleep, steps —
  optional charts. Needs the deferred `withings_measures` backend table, so it's
  a paired front/back item.

### 11. Photo / PDF lab import via Vision OCR
- Many users get results as a PDF or photo, not `.xlsx`. On-device `VisionKit`
  text recognition to pre-fill results would widen adoption substantially — the
  current `.xlsx`-only path is a real ceiling.

### 12. Onboarding ◐ Partially shipped
- **Profile setup** (height, weight, waist, units choice, optional Apple Health
  sync) shipped as the first-run gate (`Onboarding/`). Still outstanding: a
  **sample-data tour** so a brand-new user sees a populated dashboard before their
  first panel import — currently new accounts land on an empty state.

---

## Suggested starting point

With #5 (doctor PDF) and first-run onboarding (#12 partial) shipped, the next
highest-leverage items are:

**#9 (SwiftData offline cache)** first — it unblocks widgets, speeds cold-start,
and removes the network dependency for every feature. It is self-contained backend
work that touches no external API.

Then **#1 (WidgetKit)** + **#2 (notifications/reminders)** — they cover the "daily
glanceability" gap that the body-map dashboard partially addressed for in-app use,
and extend it to the Home Screen. Both build on the cache from #9.

**#7 (derived ratios TG/HDL + AST:ALT)** is the highest-clinical-value item that
requires no backend work and no cache — pure client-side computation over data the
app already holds.
