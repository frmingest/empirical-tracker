# Empirical Tracker — iOS Design System

**Status:** Living document · **Last updated:** 2026-06-04

This is the single source of truth for the look and feel of the iOS app. Every
new screen and every reskin **must** be built from the tokens and components
described here. If you need something that isn't here, add it to the design
system first (and update this doc), rather than hand-rolling one-off styling in
a feature view.

The architecture decision behind this layer is recorded in
[ADR-025](adr/025-ios-soft-design-system.md). The colour palette mirrors the
web dashboard's CSS custom properties (ADR-006), so the two clients stay in
visual lock-step.

---

## 1. Design language

The app uses a **soft, rounded, "floating cards on a light page"** aesthetic:

- A light page background (`Color.bgBase`) with content laid out as large,
  generously-rounded white cards (`SoftCard`) that float on a diffuse shadow.
- Tinted **circular icon badges** lead list rows and section headers; colour is
  always paired with an SF Symbol, never used as the only signal.
- **Capsule pills** for filters and chips; selection is a tinted wash + ring,
  not a hard solid fill, so rows stay airy.
- A **translucent floating capsule tab bar** instead of the opaque system bar.
- Numeric, clinical values use the monospaced numeric type scale so columns of
  results align.

Everything below is implemented in
`ios/Packages/Core/Sources/Core/DesignSystem/`. Import `Core` to use it.

---

## 2. Tokens

### 2.1 Colour — `AppColors.swift`

Never hardcode hex or use system colours for app chrome. Use the semantic
`Color` extensions; every token has a light/dark variant in
`Assets.xcassets/Colors/`.

| Token | Use |
|-------|-----|
| `.bgBase` | Page background behind cards |
| `.bgCard` | Card / surface fill |
| `.bgElevated` | Inputs, modals, popovers |
| `.textPrimary` | Headlines, primary values |
| `.textSecondary` | Supporting text |
| `.textMuted` | Captions, hints, placeholders, disabled |
| `.textTertiary` | Lowest-contrast captions |
| `.borderCard` | Card borders / hairlines |
| `.borderSubtle` | Dividers |
| `.accent` | Primary interactive accent (blue) |
| `.inRange` | In-range / success (emerald) |
| `.outRange` | Out-of-range / error (rose) |
| `.mealBreakfast` `.mealLunch` `.mealDinner` `.mealSnack` `.mealOther` | Per-category accent tints (see §5) |

**Rule:** colour is supplementary. Any colour-coded state (in/out of range, meal
slot, category) must also carry an icon or text label so it survives colour
blindness and greyscale (ADR-006).

### 2.2 Typography — `AppTypography.swift`

All sizes respect Dynamic Type. Use the named scale; do not call
`Font.system(size:)` inline in feature views.

| Group | Tokens |
|-------|--------|
| Display | `.displayLarge` (34) · `.displayMedium` (28) |
| Headline | `.headlineLarge` (22) · `.headlineMedium` (17) · `.headlineSmall` (15) |
| Body | `.bodyLarge` (17) · `.bodyMedium` (15) · `.bodySmall` (13) |
| Numeric (monospaced) | `.numericLarge` (28) · `.numericMedium` (20) · `.numericSmall` (13) |
| Label | `.labelLarge` (13) · `.labelMedium` (11) · `.labelSmall` (10, small-caps) |

Use the **numeric** scale for biomarker readings, energy and macro values so
digits are monospaced and align in columns.

### 2.3 Shape & spacing

| Surface | Corner radius | Notes |
|---------|---------------|-------|
| `SoftCard` (primary surfaces) | 24 (default), 18 for dense items | Borderless, soft shadow |
| `CardView` (dense grid) | 12 | Hairline border + tight shadow |
| Pills / chips / badges | Capsule / circle | — |
| Buttons (`PrimaryButtonStyle`) | 10 | Accent fill, white label |

Always use `RoundedRectangle(cornerRadius:style: .continuous)` — the iOS
"squircle" — never the default circular-arc corner. Standard screen gutter is
**16 pt**; inter-card spacing on a scrolling page is **16 pt**; section spacing
on the dashboard is **28 pt**.

---

## 3. Components

Import `Core`. Prefer composing these over bespoke styling.

### `SoftCard` — primary surface
The large, softly-shadowed white card that defines Home / Diary / Plan.
```swift
SoftCard {                       // default: radius 24, 18-pt padding, .bgCard
    VStack(alignment: .leading) { /* … */ }
}
SoftCard(cornerRadius: 18, padding: .init(top: 14, leading: 14, bottom: 14, trailing: 14)) {
    /* denser item, e.g. a biomarker card */
}
```

### `CardView` — dense / bordered surface
The original tight (12-pt radius, hairline-bordered) card. Keep it for **dense
data grids** where the airy `SoftCard` would waste space (e.g. the small
biomarker tiles inside a category section, category-graph panels). New top-level
screens should default to `SoftCard`.

### `PillChip` — filter / selector capsule
```swift
PillChip("Lipids", isSelected: selected == .lipids, tint: .accent) {
    selected = .lipids
}
```
Selected state = `tint.opacity(0.12)` wash + coloured ring + coloured text.
Adds `.isSelected` accessibility trait automatically.

### `CircleIconBadge` — leading glyph
```swift
CircleIconBadge("flame.fill", tint: .mealBreakfast, size: 56)   // hero
CircleIconBadge(meal.icon, tint: meal.tint, size: 32)           // list row
```
Tinted circle (`tint.opacity(0.15)`) with a centred SF Symbol. Marked
`accessibilityHidden` — pair it with an adjacent text label.

### `StatusBadgeView` — in/out-of-range pill
Icon **and** colour, with a `compact` variant for dense rows. Prefer the
`init(inRange:)` convenience.

### `EmptyStateView` + `PrimaryButtonStyle`
Standard icon / title / message / optional-CTA empty state. Use
`PrimaryButtonStyle()` for the app's primary action button anywhere.

### `LoadingView` + `SkeletonRow`
Full-area spinner with optional message; `SkeletonRow` for in-list shimmer.

### `FloatingTabBar` (app shell)
The translucent capsule tab bar lives in `App/RootView.swift`. Destinations are
declared once in the `AppTab` enum (title + SF Symbol); screens are kept alive
in a `ZStack` (opacity-toggled) so scroll position and view-model state survive
tab switches. **To add a tab, add a case to `AppTab` and one `screen(_:)` line —
do not reintroduce a system `TabView`.**

> ⚠️ The capsule has no automatic "More" overflow. It currently carries six
> tabs; keep labels short (`lineLimit(1)`, 10-pt) and treat ~6 as the practical
> ceiling. If a seventh primary destination is needed, revisit the shell (e.g. a
> grouped "More" sheet) rather than cramming the capsule.

---

## 4. Patterns

- **Page scaffold:** a `ScrollView` of `SoftCard`s with 16-pt padding on
  `Color.bgBase`. For `List`-based screens, set
  `.scrollContentBackground(.hidden)` + `.background(Color.bgBase)` so the page
  tone shows through.
- **List row:** `CircleIconBadge` (leading) · title + subtitle · trailing value
  or a `Menu` (`ellipsis`) for row actions. Destructive/secondary actions belong
  in the per-row menu, not swipe-only, so they're discoverable.
- **Hero metric:** large `CircleIconBadge` beside a `.numericLarge` value, with
  `lineLimit(1)` + `minimumScaleFactor` so big numbers never wrap.
- **Macro / stat pills:** label in the tint colour over a `.numericSmall` value,
  on a `tint.opacity(0.12)` rounded background.

---

## 5. Category & meal tint mapping

Meal slots and dashboard categories reuse the five meal tones. Tint↔icon mapping
is **view-layer only** (e.g. the `BiomarkerCategory` extension in
`CategorySectionView.swift`) — keep it out of the domain models. When adding a
category, pick an existing tone + a distinct SF Symbol; don't introduce new raw
colours outside the palette.

---

## 6. Accessibility checklist

- Colour is never the only signal (icon or text always accompanies it).
- Decorative badges are `accessibilityHidden`; the meaning is on the adjacent
  label.
- Selectable controls add `.isSelected`; icon-only buttons have an
  `accessibilityLabel`.
- Type uses the Dynamic-Type scale; large numerics use `minimumScaleFactor`
  rather than truncating.

---

## 7. Adding to the system

1. If a feature needs a new visual primitive, add it to
   `Core/DesignSystem/Components/` as a `public` view, with a `#Preview`.
2. Add any new colour to `Assets.xcassets/Colors/` (light + dark) and expose it
   as a semantic token in `AppColors.swift` — never a raw hex in a view.
3. Document it in §3 of this file.
4. Reskinning an existing screen: swap to design-system components; preserve all
   existing behaviour, view-model wiring and accessibility traits.
