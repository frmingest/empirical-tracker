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

**Gaps that shape this wishlist:**

- No offline cache yet (SwiftData planned for Sprint 11 — every read currently
  hits the network).
- No notifications/reminders, no widgets, no Siri/Shortcuts, no Apple Watch, no
  Live Activities.
- Deferred clinical value: doctor PDF report (Sprint 6), derived ratios TG/HDL &
  AST:ALT (Sprint 8), daily targets + protein g/kg (Sprint 9),
  body-metric-on-biomarker-timeline overlay (Sprint 10); HealthKit covers only
  weight + BP (not body-fat / resting HR / sleep).

---

## Tier 1 — Native iOS features that create daily engagement

A blood-test app is opened rarely; these turn it into something glanceable and
timely, which is the whole point of being native.

### 1. Home Screen & Lock Screen widgets (WidgetKit)
- A **latest-panel** widget (e.g. LDL / HbA1c trend + Watch-marker count), a
  **today's macros vs target** diary widget, and a **weight-trend** widget.
- Biggest single retention lever — keeps the app present between the rare
  panel imports.
- Builds on existing data shapes (`BiomarkerWithSeries`, diary daily totals);
  needs an **App Group** + a shared read cache (see #9).

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

### 5. Doctor / clinician PDF report (Sprint 6 follow-up)
- The headline missing feature. A native `PDFKit` report: latest-panel table
  (value, range, target, Watch state) + trend thumbnails + active diet events,
  shared via the share sheet.
- Highly appealing to the target user who wants to bring numbers to their
  doctor. Can be **100% client-side** (no backend dependency) — the data and
  charts already render.

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

### 9. Offline-first cache (SwiftData — already planned Sprint 11)
- Worth pulling forward: instant cold-start, tolerant of flaky networks. Also
  the prerequisite for widgets (#1) to have data without a network round-trip.

### 10. Richer HealthKit signals
- Extend beyond weight + BP to body-fat %, lean mass, resting HR, sleep, steps —
  optional charts. Needs the deferred `withings_measures` backend table, so it's
  a paired front/back item.

### 11. Photo / PDF lab import via Vision OCR
- Many users get results as a PDF or photo, not `.xlsx`. On-device `VisionKit`
  text recognition to pre-fill results would widen adoption substantially — the
  current `.xlsx`-only path is a real ceiling.

### 12. Onboarding + sample-data tour
- A guided first-run (the demo/mock data already exists) so a new user sees a
  populated dashboard before they have their own panel — reduces empty-state
  drop-off.

---

## Suggested starting point

**#1 (widgets) + #2 (notifications) + #5 (doctor PDF)** together cover the three
things this audience wants most — daily glanceability, timely nudges, and
something to hand their clinician — and lean on infrastructure that already
exists without requiring backend work. The **doctor PDF report (#5)** is the
most self-contained place to start (fully client-side) and would make a clean
first ADR + sprint.
