# ADR-009: Internationalization (English / Norwegian)

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

The app's primary user is Norwegian, and the source lab data is already in Norwegian. The UI,
however, was English-only. We wanted an EN/NO language toggle for the dashboard chrome and
plain-language explanations of each biomarker group — without pulling in a heavyweight i18n
framework for what is currently a two-language, single-page surface.

---

## Decision

- **Lightweight custom i18n**: A `LanguageProvider` React context plus a flat string dictionary
  in `web/src/lib/i18n.ts` (`en` / `no` maps keyed by dotted string ids, e.g. `"hero.title"`).
  No external i18n dependency.

- **Toggle**: A `LanguageToggle` (EN/NO) button in the header, mirroring the existing
  `ThemeProvider` / `ThemeToggle` pattern. The choice persists to `localStorage` and is
  reflected on the `<html lang>` attribute.

- **Scope**: The dashboard, diet filter, and category headings are translated. English is the
  default and the fallback for any missing key.

- **Category tooltips**: An `InfoTooltip` "i" button next to each biomarker grouping (Lipids,
  CBC, Metabolic, …) with a plain-language explanation of what those markers are, in both
  languages.

---

## Rationale

### Why a custom dictionary instead of `next-intl` / `react-i18next`?
The surface is small (one dashboard, two languages) and the strings are static. A flat
dictionary plus a context provider is ~50 lines, has no dependency or bundle cost, and reuses
the exact pattern already established by the theme system. A full i18n library (routing-based
locales, pluralization, ICU messages) is more machinery than the current scope justifies.

### Why mirror the `ThemeProvider` pattern?
Consistency: a contributor who understands theme switching already understands language
switching. Both are client-side, `localStorage`-persisted preferences applied to `<html>`.

### Why translate `name_no`-based data but key the UI on string ids?
Biomarker names already arrive in Norwegian from the lab; only the app's own UI chrome needs
translation. Dotted string ids keep the dictionary readable and make missing-key fallback trivial.

---

## Consequences

- **Good:** No new dependency; bundle cost is the dictionary itself
- **Good:** Same mental model as the theme toggle — low cognitive overhead
- **Good:** `<html lang>` is set correctly for accessibility/SEO
- **Trade-off:** A flat dictionary doesn't scale gracefully to many languages or
  pluralization/interpolation. If a third language or dynamic strings arrive, revisit with a
  proper i18n library
- **Trade-off:** Every new translatable string must be added to both `en` and `no` maps by hand

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| `next-intl` / `react-i18next` | Heavyweight for two languages of static UI chrome |
| Locale-prefixed routes (`/no`, `/en`) | Adds routing complexity; preference toggle is simpler |
| Norwegian-only UI | Loses the English audience and shareability with doctors |
| No tooltips | Group names alone aren't self-explanatory to non-clinical users |
