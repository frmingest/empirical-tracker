# ADR-005: Frontend Architecture

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

The web frontend needs to display 34 biomarkers across 8 categories, with sparkline cards,
a full trend chart per biomarker, and an import flow. It must be fast, type-safe, and
lay the groundwork for the future React Native mobile client.

---

## Decision

- **Framework:** Next.js 16 App Router (TypeScript strict mode)
- **Styling:** Tailwind CSS v4 — utility-first, no CSS modules
- **Charting:** Recharts — client components only, with `mounted` guard for SSR safety
- **Data during dev:** Static mock data matching the exact API response shape, with TODO
  comments marking where live API calls replace it
- **Design system:** Dark-only palette (zinc + emerald/rose/blue semantics), Geist fonts,
  no light mode toggle needed
- **Component boundary:** Server components for layout/data; client components only where
  browser APIs are needed (charts, modals, file upload)

---

## Rationale

### Why client-side rendering for the dashboard?
The dashboard page is `"use client"` because it needs the `ImportModal` state (`useState`).
Individual chart components (`BiomarkerCard`, `BiomarkerChart`) are already client components
for Recharts. When auth is wired, the data fetching will move to a server component wrapper
and pass data down as props — the structure already separates data from interactivity.

### Why Recharts over Chart.js / Nivo / Visx?
- Recharts has first-class TypeScript types
- `ReferenceArea` for the reference-range band is a first-class API, not a plugin
- Familiar React component model — no imperative API to fight
- Next.js App Router compatible with the `"use client"` boundary

The `mounted` guard (`useState(false)` + `useEffect(() => setMounted(true))`) prevents
hydration mismatches because Recharts' `ResponsiveContainer` reads `window.innerWidth`
on mount.

### Why Tailwind v4 (not v3)?
The project was initialized with v4. Tailwind v4 uses `@import "tailwindcss"` and CSS-first
configuration. Since the app is dark-only, no `dark:` variant configuration was needed —
dark colors are written directly as the base palette.

### Why mock data before auth?
Wiring auth (Sprint 1 auth) and building UI (Sprint 1 UI) are parallel workstreams. Mock data
matching the exact `BiomarkerWithSeries` API shape lets the UI be built, tested, and iterated
without blocking on auth. The swap is a single-line change in `page.tsx`.

---

## Consequences

- **Good:** TypeScript strict mode catches API shape mismatches at compile time
- **Good:** Server/client boundary is explicit — pages that don't need interactivity compile
  to static HTML
- **Good:** Dark-only design means no conditional styling, smaller CSS bundle
- **Trade-off:** Recharts requires a `"use client"` boundary even for static charts.
  Mitigation: charts are isolated in leaf components; server components compose them
- **Trade-off:** Mock data will diverge from real data if the API shape changes.
  Mitigation: both use the same `BiomarkerWithSeries` TypeScript interface; any divergence
  is a compile error

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Pages Router | App Router's server components reduce client JS bundle; no reason to use legacy |
| CSS Modules | Tailwind is faster to iterate; the project has no design token file to maintain |
| Chart.js | Imperative API doesn't fit React's component model; worse TypeScript story |
| Nivo | Beautiful but heavy bundle; overkill for sparklines |
| Fetching in useEffect | Server components + async params is cleaner; avoids loading spinners |
