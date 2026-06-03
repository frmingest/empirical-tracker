# ADR-008: Diet-Focus Biomarker Filtering and Per-User Settings

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

---

## Context

The panel imports all 34 biomarkers, but a user following a specific eating pattern only cares
about a clinically relevant subset. Showing every marker at once buries the handful that
actually move on a carnivore / low-carb / fasting protocol.

We needed a way to:

1. Hide markers that aren't informative for the user's chosen diet
2. Let the user hand-pick their own set when the presets don't fit
3. Persist that choice per user (signed-in) and for the demo/mock view (signed-out)

The clinical rationale for each diet's marker list is documented separately in
`docs/DIET_BIOMARKERS.md`.

---

## Decision

- **Diet presets** (`all`, `carnivore`, `low_carb`, `fasting`, `custom`): A segmented
  `DietFilter` control on the dashboard. Each preset maps to a fixed set of biomarkers
  (`DIET_MARKERS` in `Packages/Biomarkers/Sources/Biomarkers/DietProfiles.swift`).

- **Client-side filtering**: Marker classification happens in the browser. A `markerKey()`
  function resolves messy lab names to a stable canonical key using ordered keyword rules
  (mirroring the existing `biomarkerCategories.ts` approach). Matching is against `name_no`,
  the only name field present on both mock and imported data.

- **Custom selection**: A `CustomMarkerModal` picker, seeded from the current view. Custom
  selections are **stored by biomarker name**, not id, so they survive re-imports and new panels.

- **Persistence**: A new `user_settings` table (migration `003_user_settings.sql`), one row
  per user, RLS self-scoped like the rest of the schema. New `GET/PUT /settings` endpoints.
  Signed-out demo view persists to `UserDefaults`.

- **Shared auth dependency**: Token-to-user-id resolution was extracted from the biomarkers
  router into `app/auth.py` (`current_user_id`) so the new settings router reuses it.

---

## Rationale

### Why filter client-side instead of server-side?
The dashboard already fetches the full `BiomarkerWithSeries[]` for sparklines. Filtering in
the browser is O(n) over data already in memory, keeps the filter instant (no round trip when
switching diets), and means the filter logic and the category logic live side by side.

### Why store custom markers by name, not id?
Biomarker rows are recreated on re-import, so ids are not stable. The user's intent ("I always
want to see Ferritin") is tied to the marker's identity, not a database row — names survive.

### Why a new table instead of a column on an existing one?
There is no natural per-user row to hang preferences on (`results`/`panels` are many-per-user).
A dedicated `user_settings` table keyed by `user_id` is the clean home for dashboard
preferences and gives future settings somewhere to land.

### Why extract `current_user_id`?
The biomarkers router already resolved the bearer token inline. Adding a second authenticated
router made duplicated token handling a liability — one shared dependency keeps auth in one place.

---

## Consequences

- **Good:** Switching diets is instant — no network call, no re-fetch
- **Good:** Custom selections are durable across re-imports because they key on name
- **Good:** Settings persistence reuses the existing RLS isolation boundary; no new auth surface
- **Good:** The demo (signed-out) view is fully functional via `UserDefaults`
- **Trade-off:** Marker classification is keyword-based and must stay in sync with the panel's
  naming. New/renamed markers need a rule added in `dietProfiles.ts`
- **Trade-off:** The clinical lists in `docs/DIET_BIOMARKERS.md` and the `DIET_MARKERS` sets in
  code are two sources that must be kept in sync (called out in the doc)

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Server-side filtering endpoint | Extra round trip; data is already in the browser |
| Store custom markers by biomarker id | Ids change on re-import; selections would be lost |
| Add a `diet` column to an existing table | No natural single-row-per-user table to use |
| Hard-code one diet (carnivore) | The tool targets multiple eating patterns |
