# ADR-027: Retain the custom-food catalogue by anonymising on delete

**Status:** Accepted
**Date:** 2026-06-04
**Author:** Faiz (solo developer)
**Sprint:** — (compliance / data-retention follow-up)

---

## Context

The food diary lets a user add a product that isn't in the external sources
(Open Food Facts / Matvaretabellen / USDA) two ways: a **camera label scan** and a
**manual entry form** (ADR-011 introduced the diary; the `custom_foods` table came
with `011_custom_foods.sql`). The scan flow runs OCR **on-device** with Apple's
Vision framework — the photographed image never leaves the phone — and only the
*extracted text* is sent to the backend, where Claude Haiku parses it into
per-100 g nutrients (`app/food_sources/label_parser.py`). The image is never
stored anywhere; the migration says as much (`011_custom_foods.sql:3`).

What **is** stored, permanently, is a `custom_foods` row: `food_name`, `brand`,
`barcode`, the nutrient columns, free-text `ingredients`, and **`ocr_raw`** (the
raw text scraped off whatever the user photographed). Every row carries a
`user_id` and an `is_public` flag (items can be shared into a common catalogue,
the same model recipes later adopted — ADR-024).

This data is genuinely valuable: a growing, user-curated catalogue of regional /
niche products that the external sources miss, reusable across the whole userbase.
We want to keep leveraging it. The question this ADR settles is **what happens to
it when a user removes an item, or deletes their account** — and how to keep the
catalogue without breaking the erasure guarantees ADR-013 established.

### Two problems with the status quo

1. **`custom_foods` escapes the erasure + export design.** ADR-013 deletes every
   user-owned table *explicitly* (`DELETE_ORDER`) rather than leaning on the
   `auth.users ON DELETE CASCADE`, precisely so erasure is transparent and
   unit-testable — and it exports every table the same way (`USER_TABLES`). But
   `custom_foods` is in **neither** list (`app/account/repository.py`). Today it
   is only cleaned up incidentally by the cascade when the admin user-deletion
   step succeeds, and it is **silently absent from the GDPR export** (Art. 20
   portability gap). ADR-013's own consequences section warned this would happen
   to any table added without joining those lists; it did.

2. **"Keep it because it's valuable" is not an erasure exception.** The instinct
   to retain the row as-is after a deletion request conflicts with the right to
   erasure (GDPR Art. 17). As stored, a row is **personal data**: it is linked to
   `user_id`, timestamped, and `ocr_raw` is unbounded free text the user
   photographed (it can contain anything). The *set* of foods a person adds also
   reveals dietary/health habits. We operate in the EU region (Supabase
   Frankfurt) on health-adjacent data, so this is squarely in scope (ADR-026).

The escape hatch GDPR actually provides is **anonymisation** (Recital 26):
data that is *irreversibly* de-linked from the individual falls outside the
regulation and may be retained indefinitely. A bare nutrition fact — "Brand X
bar, 450 kcal / 100 g, barcode 737…" — is factual *product* data, not data about
a *person*, once it is detached from the contributor. Pseudonymisation (keeping
`user_id`) is **not** enough; the link must be severed.

## Decision

**Anonymise on delete, don't retain user-linked rows.** When a user deletes a
custom food (or their whole account), we keep the *factual catalogue value* by
copying it into a separate, de-identified table and then hard-delete the original
user-owned row.

### 1. New table — `food_catalogue` (`013_custom_foods_anonymise.sql`)

A donated-facts table that is **not** a `USER_TABLES` member and has **no**
`user_id`:

- Columns: `food_name`, `brand`, `barcode`, the nutrient columns, `serving_g`,
  and `ingredients` — **the factual fields only**.
- **Dropped on donation:** `user_id`, `created_at` (replaced by a coarse
  `donated_at` date with no tie to the user's activity), and **`ocr_raw`**
  entirely. `ocr_raw` is unbounded free text and cannot be guaranteed
  non-identifying, so it is never donated — it lives only on the user-owned row
  and dies with it.
- `barcode`-unique (upsert): re-donating the same product updates the facts
  rather than piling up duplicates.
- RLS: readable by any authenticated user, writable only by the service role
  (the donation path), mirroring how the read-only external sources behave.

### 2. Donation happens at the moment of deletion, service-side

- **Per-item delete** (`custom.delete_custom_food`): before deleting the row,
  copy its factual fields into `food_catalogue` (scrubbing as above), then delete.
- **Account delete** (`account.delete_user_data`): add `custom_foods` to the
  erase path, but route it through the same donate-then-delete helper rather than
  a bare `DELETE`. After this, `custom_foods` is genuinely, explicitly erased —
  closing problem (1) on the deletion side.

### 3. Only donate what the user agreed to share

We donate a row **only if `is_public = true`**. A private custom food was never
shared and carries the strongest expectation of deletion; it is hard-deleted with
nothing kept. `is_public` already exists as the user's sharing signal — we reuse
it as the consent gate rather than inventing a new flag. (The label-scan / manual
forms must make the "share to the common catalogue" choice explicit at
contribution time; if today's UI defaults `is_public` silently, that is a
required pre-req — see Consequences.)

### 4. Search reads the donated catalogue too

`food_catalogue` joins the source registry as a read-only source, so the donated
facts keep showing up in search/barcode lookup for the whole userbase — which is
the entire point of keeping them.

### 5. Close the export gap

Add `custom_foods` to `USER_TABLES` so a user's own custom foods appear in their
Art. 20 export. (The donated `food_catalogue` rows are anonymous and intentionally
*not* part of any individual's export.)

## Rationale

- **It actually delivers both goals.** The curated catalogue survives and stays
  useful to everyone; the individual's right to erasure is honoured because what
  remains is no longer their personal data.
- **It matches the house style.** Donation runs on the service-role client — the
  one sanctioned service-role data path (ADR-026) — and the read side mirrors the
  external food sources' "service role bypasses RLS, filter explicitly" pattern.
- **Defensible by construction.** Dropping `user_id`/`created_at`/`ocr_raw` and
  keeping only factual product fields is a concrete, reviewable anonymisation
  step, not a hand-wave. The `is_public` gate means we never retain anything from
  a user who kept their entry private.
- **Fixes the latent ADR-013 bug as a side effect.** `custom_foods` finally joins
  the explicit export and erasure lists.

## Consequences

- **Migration:** `013_custom_foods_anonymise.sql` must be run in the Supabase SQL
  editor before the new path works (manual-migration convention).
- **Required pre-req:** the contribution UI must capture `is_public` as an
  explicit, informed "share to the common catalogue" choice; donating on an
  implicitly-defaulted flag would undermine the consent basis. Worth confirming
  the current default before shipping.
- **Privacy policy:** disclose that publicly-shared custom foods are retained in
  anonymised form after account/item deletion. This is a policy/counsel touch
  point, not just code.
- **Not legal advice:** this records an engineering decision aligned with Art. 17
  / Recital 26; a DPO/counsel sign-off on the anonymisation boundary (especially
  "is barcode + brand + macros truly non-identifying for niche products?") is the
  responsible final gate.
- **Maintenance:** `food_catalogue`'s factual columns must track any new nutrient
  column added to `custom_foods`, or donated rows silently lose those fields.

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Retain `custom_foods` rows as-is after deletion (the original ask) | Keeps `user_id` + `ocr_raw`; that is still personal data, so it conflicts with Art. 17. "It's valuable to us" is not an erasure exception. |
| Just scrub `user_id` in place (set it NULL / a sentinel) on the existing table | Leaves `ocr_raw` and `created_at`; row-level join risk remains, and the table still sits in the user-data blast radius. A separate facts table is a cleaner trust boundary. |
| Full delete, retain nothing (the conservative fix) | Safest, but throws away the curated catalogue the user explicitly wants to keep. Anonymisation gets the value *and* compliance. |
| Donate every row regardless of `is_public` | Retaining facts a user kept private overreaches the sharing they consented to; gate on the existing public flag instead. |
| Keep `ocr_raw` in the donated table for richer parsing later | Unbounded free text can't be guaranteed non-identifying; donating it would defeat the anonymisation. The structured factual columns are what the catalogue needs. |
