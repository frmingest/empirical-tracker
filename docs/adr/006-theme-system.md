# ADR-006: Light/Dark Theme System

**Status:** Superseded — web frontend retired  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

> **⚠️ Historical record.** This ADR documents the CSS-variable-based dark/light theme
> system for the retired Next.js web client. The iOS app's theme and design tokens are
> covered by [ADR-025](025-ios-soft-design-system.md) (`AppColors`, `AppTypography`,
> `SettingsStore` `AppTheme` enum). This file is retained as an audit trail.

---

## Context

The initial dashboard used a dark "terminal" aesthetic (zinc palette). User feedback indicated
that a lighter, more clinical look would be more appropriate for a health-data tool — and would
improve legibility in well-lit environments. The dark theme is still preferred for low-light
use and by users who prefer it.

---

## Decision

- **Default theme:** Light (medical/clinical aesthetic — white/slate backgrounds, sky-blue accents)
- **Dark mode:** Available via a toggle button in the top nav; persisted to `localStorage`
- **Implementation:** CSS custom properties on `:root` (light) and `html.dark` (dark override)
- **Component strategy:** All components reference semantic CSS variables (`var(--bg-card)`,
  `var(--text-primary)`, etc.) rather than theme-specific Tailwind utilities
- **Toggle mechanism:** A `ThemeProvider` React context + `ThemeToggle` button component;
  the `dark` class is applied to `<html>` and persisted in `localStorage`

---

## Rationale

### Why CSS custom properties instead of Tailwind `dark:` variants?
Tailwind `dark:` variants double the number of utility classes on every element and require
touching every component every time a color changes. CSS custom properties centralise the
palette in one place (`globals.css`) — components remain unchanged when a theme colour is
adjusted.

### Why light as default?
Medical data tools (EHR portals, lab result viewers) default to light themes because:
1. Clinical environments are typically well-lit
2. Light backgrounds have better print/screenshot legibility
3. Dark mode as an opt-in respects user preference without forcing it

### Why `localStorage` persistence instead of `prefers-color-scheme`?
`prefers-color-scheme` is a good signal but the user should be able to override it. The toggle
reads `prefers-color-scheme` as the initial default if no `localStorage` value is set (future
improvement — for now defaults to light).

---

## Consequences

- **Good:** Single source of truth for colours — only `globals.css` needs changing for a
  palette update
- **Good:** No flash of unstyled content (FOUC) because the class is applied on mount via
  `useEffect`, and `suppressHydrationWarning` is set on `<html>`
- **Trade-off:** There is a brief flash if the user has dark mode saved — the page renders
  light first, then switches. Mitigation: inline script in `<head>` to apply the class before
  first paint (future improvement)
- **Trade-off:** Recharts SVG attributes that accept colours need either CSS-var strings
  (which SVG resolves correctly) or a mounted-state colour read

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Tailwind `dark:` variants | Verbose; every component needs double classes |
| `next-themes` package | Adds a dependency; the custom implementation is ~30 lines |
| System-only (no toggle) | User may want to override their OS setting |
| Dark-only forever | Doesn't match medical/clinical UX expectations |
