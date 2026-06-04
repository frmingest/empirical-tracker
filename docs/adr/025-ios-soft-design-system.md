# ADR-025: iOS soft, rounded design system

**Status:** Accepted
**Date:** 2026-06-04
**Author:** iOS team
**Sprint:** — (design-system consolidation)

---

## Context

The iOS app grew screen-by-screen (dashboard, diary, plan, body metrics,
recipes). Shared styling existed — semantic colours (`AppColors`), a type scale
(`AppTypography`), and a handful of components (`CardView`, `StatusBadgeView`,
`EmptyStateView`, `LoadingView`) mirroring the web dashboard (ADR-006) — but the
*layout* language drifted: tight bordered cards, the opaque system `TabView`,
ad-hoc filter chips defined privately inside individual feature files
(`FilterChip` in `DietFilterView`), and inline `Font.system(size:)` / one-off
backgrounds.

A redesign (PR #68) introduced a softer, rounded, "floating cards on a light
page" visual language and three new shared primitives. Merged alongside it was
the Recipes catalogue (PR #69, ADR-024), which added a sixth primary tab. The
two collided in the app shell, and — more importantly — the project had no
written rule that *future* work must build on the shared layer rather than
re-inventing styling per screen.

This ADR records (a) the adoption of the soft design language, (b) the shared
component layer it standardises on, and (c) the requirement that future
development go through that layer.

## Decision

### 1. Visual language

Adopt a soft, rounded aesthetic: a light page (`bgBase`) carrying large,
generously-rounded, borderless white cards on a diffuse shadow; tinted circular
icon badges; capsule pills with a tinted-wash selected state; and a translucent
floating capsule tab bar. Full token/usage reference lives in
[`docs/DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md).

### 2. Shared component layer

Three new `public` primitives are added to
`Core/DesignSystem/Components/SoftCard.swift`:

- **`SoftCard`** — the primary surface (radius 24, borderless soft shadow).
  `CardView` (radius 12, hairline border) is **retained** for dense data grids
  where the airy card would waste space.
- **`PillChip`** — replaces per-feature private filter chips.
- **`CircleIconBadge`** — the tinted leading glyph for rows, headers and heroes.

Colour tints and SF-Symbol mappings for categories/meals stay **view-layer**
(e.g. a private `BiomarkerCategory` extension), keeping domain models free of
presentation concerns.

### 3. App shell

Replace the system `TabView` with a custom `FloatingTabBar` driven by an
`AppTab` enum (single declaration of title + icon per destination). Screens are
kept alive in a `ZStack` (opacity-toggled) to preserve scroll position and
view-model state across switches — the behaviour `TabView` gave for free. The
Recipes tab (ADR-024) is folded into `AppTab` as a first-class case.

### 4. Process

Future screens and reskins **must** be built from the design-system tokens and
components. New primitives are added to `Core/DesignSystem/` (with a `#Preview`)
and documented in `DESIGN_SYSTEM.md` *before* use — no one-off styling in
feature views. This is also stated in `CLAUDE.md` so it is picked up by every
contributor and agent session.

## Rationale

- **One source of truth.** Centralising surfaces, chips and badges means a
  palette or radius change touches one file, not every screen — the same
  argument that drove the web theme system (ADR-006).
- **Keep `CardView` too.** The dense biomarker grid genuinely needs a tighter
  card; forcing `SoftCard` everywhere would waste vertical space. Two surfaces
  with a documented "when to use which" beats one ill-fitting card.
- **Custom shell, deliberately.** A floating capsule can't be achieved with the
  stock bar, and the `ZStack` keep-alive replaces the one `TabView` feature we'd
  otherwise lose.
- **Accessibility preserved.** Every colour-coded state keeps an icon/label,
  decorative badges are hidden from VoiceOver, and selection traits are carried
  by the components themselves (ADR-006's colour-blind rule).

## Consequences

- **Good:** consistent, modern look across Home / Diary / Plan and a clear path
  for new screens; private chip duplicates removed.
- **Trade-off:** the floating capsule has **no automatic "More" overflow**. It
  now carries six tabs; ~6 is the practical ceiling with short labels. A seventh
  primary destination requires revisiting the shell (e.g. a grouped sheet)
  rather than widening the capsule. Documented in `DESIGN_SYSTEM.md` §3.
- **Trade-off:** two card primitives (`SoftCard` / `CardView`) — mitigated by a
  documented decision rule.
- **Follow-up:** screens not yet reskinned (Body metrics, Settings, Recipes
  detail) should migrate to the soft language opportunistically; they remain
  functional in the meantime.

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Restyle `CardView` in place (no `SoftCard`) | Dense grid still needs the tight card; one card can't serve both |
| Keep the system `TabView` | Can't produce the floating translucent capsule look |
| Drop a tab to fit five | Loses a primary destination (Recipes / Body); functionality over chrome |
| Leave styling per-feature | The drift this ADR exists to stop; no single source of truth |
