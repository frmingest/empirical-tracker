# ADR-029: Donate to the anonymous catalogues proactively, not only on delete

**Status:** Accepted
**Date:** 2026-06-05
**Author:** Faiz (solo developer)
**Sprint:** — (compliance / data-retention follow-up)
**Amends:** [ADR-027](027-custom-food-anonymise-on-delete.md),
[ADR-028](028-recipe-anonymise-on-delete.md) — changes the *trigger*, keeps the
anonymisation boundary and the consent gate.

---

## Context

ADR-027 (custom foods) and ADR-028 (recipes) settled how we keep a user-curated
catalogue without breaking the right to erasure: when a user deletes a **public**
item — per-item or via account deletion — we copy its **factual fields only**
into a separate anonymous table (`food_catalogue` / `recipe_catalogue`), dropping
`user_id`, `created_at`, and the unbounded/identifying blob (`ocr_raw` /
`image_url`), then hard-delete the user-owned row. The anonymous twin has no
`user_id`, is read-only to all authenticated users, and survives indefinitely
(GDPR Recital 26 — anonymised data falls outside the regulation).

That already delivers the goal "**keep the product/recipe data even after the
user deletes it**." The ask that prompted this ADR was to be *more proactive*:
capture that value **whenever an item is registered**, rather than waiting for a
deletion to trigger the copy.

### Will we still be in conformance? Yes — with the same two invariants

Anonymisation is what makes indefinite retention lawful, and **anonymisation
timing does not change that analysis.** Whether the anonymous copy is made at
deletion or at registration, the retained row is the same de-identified factual
data and is equally outside GDPR scope — *provided* we hold the two invariants
ADR-027/028 established:

1. **The retained copy must be genuinely anonymous.** We keep dropping
   `user_id` / `created_at` / `ocr_raw` / `image_url`; only factual product/recipe
   fields are copied. Retaining the full row (the literal "store it as-is"
   reading) would keep personal data and **break Art. 17** — explicitly rejected
   in both prior ADRs.
2. **The `is_public` consent gate stays.** We only ever copy what the user chose
   to share. Private items are never donated and are fully erased on delete.

Capturing at registration is in fact **more robust**: today the donation depends
on the deletion flowing through our helper. If a row is ever removed by another
path — a `auth.users` cascade, an admin action, a future code path — the
donate-on-delete copy is silently skipped and the catalogue value is lost.
Capturing up front removes that single point of failure.

## Decision

**Mirror a public item into its anonymous catalogue at create time and keep it in
step on edit; keep a one-shot donation on delete purely as a safety net.** The
anonymisation scrub and the `is_public` gate are unchanged from ADR-027/028.

### 1. New state — a de-identified back-pointer (`015_proactive_catalogue_donation.sql`)

A nullable `catalogue_id uuid` column is added to **`custom_foods`** and
**`recipes`**. It is a **forward-only** pointer from the user-owned row to its
anonymous twin. The link lives **only** on the user's row, so it is erased with
the user; the twin carries no reverse link and no `user_id`, so the
anonymisation is unchanged — once the source row is gone there is no path from
the catalogue back to the individual. Deliberately **not** a foreign key: a real
FK would couple the user table and the anonymous catalogue at the schema level
(delete-ordering, cascade) — exactly the coupling we avoid. A dangling pointer is
harmless; it is only ever read from the user's side. It is used to (a) update the
twin **in place** on edit instead of piling up duplicates, and (b) dedupe reads.

### 2. Donation moves to create / update (`sync_catalogue`)

- **Create / update** of a **public** item calls `sync_catalogue` (one per
  module). It scrubs to the factual fields and writes the twin on the
  service-role client (the one sanctioned service-role data path, ADR-026), then
  records `catalogue_id` back on the user's row via the request's RLS-scoped
  client. Private items do nothing.
- **Dedupe of the twin itself:**
  - *Barcoded foods* upsert on `barcode` — the same product donated by different
    users merges into one factual row (a genuine cross-user catalogue), as before.
  - *Barcodeless foods and recipes* have no natural key, so the first donation
    records `catalogue_id` and later edits update that row in place.
- **Delete** keeps a one-shot donation **only as a safety net**: a public item
  that was never mirrored (`catalogue_id IS NULL` — e.g. created before this ADR)
  is donated before the row goes. A mirrored item is simply hard-deleted and its
  anonymous twin is left standing. The twin is **never retracted** — retention is
  the whole point.
- **Account deletion** (`donate_public_foods` / `donate_public_recipes`) becomes
  "donate any *not-yet-mirrored* public rows," skipping those already mirrored,
  then the existing explicit DELETE erases all user rows (public and private).

### 3. Reads dedupe the live row against its twin

Because a live public item now coexists with its anonymous twin, a naive read
would show it twice. The twin is suppressed while the source is live:

- **Recipes** (`list_recipes`): the catalogue read excludes any twin whose id is
  the `catalogue_id` of a recipe still visible-and-live here. The richer live row
  (image, favourite, "New!" badge) is shown; the twin surfaces only once the
  source is deleted (orphaned).
- **Foods** (`registry.search` "all"): the only duplicate is **owner-side** (the
  catalogue is unscoped, but a user's own custom foods are; other users only ever
  saw the twin). The "all" merge drops catalogue rows whose `(name, brand)`
  matches one of the user's own items. The barcode-lookup path already returns
  the first hit (own → catalogue → external), so it needs no change.

A side benefit for foods: a public custom food is now discoverable by **other**
users the moment it is shared (via the twin), instead of only after its author
deletes it.

## Rationale

- **Same compliance posture, captured earlier.** The retained data is identical
  to ADR-027/028's; only the trigger moved. The `is_public` gate and the scrub
  list are untouched, so the Art. 17 / Recital 26 reasoning carries over verbatim.
- **Robust by construction.** The catalogue value no longer depends on deletion
  going through one specific code path; it is captured at the source.
- **No new trust boundary.** The back-pointer is forward-only and user-owned, so
  it dies with the user and never re-links the anonymous twin to a person.
- **House style.** Writes stay on the service-role client; reads stay on the
  RLS-scoped client; the dedupe lives next to the merge it corrects.

## Consequences

- **Migration:** `015_proactive_catalogue_donation.sql` must be run in the
  Supabase SQL editor before the new path works (manual-migration convention).
- **Un-sharing (public → private) does not retract the twin.** Once an item was
  public it may already have been seen/used; the anonymous twin is kept (it is not
  personal data) and simply stops being refreshed while private. This is a
  deliberate, documented choice — `is_public` is the consent gate **at share
  time**, consistent with "retention is the point." If product/legal later want
  un-share to retract, it is a localized change (delete the twin by `catalogue_id`
  and clear the pointer for the keyless case; barcoded twins must not be deleted
  on one user's un-share because they may represent several contributors).
- **Privacy policy:** the disclosure that publicly-shared custom foods and recipes
  are retained in anonymised form (already required by ADR-027/028) is updated to
  reflect that the anonymised copy is made when an item is shared, and persists
  after deletion. Updated in `docs/legal/privacy-policy.md` §6.
- **Not legal advice:** as in ADR-027/028, a DPO/counsel sign-off on the
  anonymisation boundary ("is `barcode + brand + macros`, or a recipe's free-text
  `fact`/instructions, truly non-identifying for niche items?") remains the
  responsible final gate. Moving the trigger does not change that boundary.
- **Maintenance:** the donated field lists (`custom._CATALOGUE_FIELDS`,
  `recipes._DONATED_FIELDS`) remain the single source of truth; a new factual
  column must be added there or donated rows silently lose it.

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Keep donate-on-delete only (ADR-027/028 as-is) | Already retains post-deletion, but the capture depends on deletion flowing through our helper — a cascade/admin/other path loses the value. Proactive capture closes that gap. |
| Retain the **full** row (the literal "store it regardless") | Keeps `user_id` + `ocr_raw`/`image_url` — still personal data, breaks Art. 17. The anonymising copy is what makes retention lawful. |
| Donate **every** item, ignoring `is_public` | Retaining facts a user kept private overreaches consent; niche `barcode+brand+macros` may be quasi-identifying. The gate stays. |
| Put a `source_*_id` on the **catalogue** row to dedupe edits | Re-introduces a reverse link from the anonymous row to the user's data — weakens anonymisation. The forward-only pointer on the user's row dies with the user instead. |
| A real FK for `catalogue_id` | Couples the user table to the anonymous catalogue (delete-ordering/cascade); a plain dangling pointer keeps the trust boundary clean. |
