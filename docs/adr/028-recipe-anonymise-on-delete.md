# ADR-028: Retain the recipe catalogue by anonymising on delete

**Status:** Proposed
**Date:** 2026-06-04
**Author:** Faiz (solo developer)
**Sprint:** — (compliance / data-retention follow-up)

---

## Context

The recipes module (ADR-024, `012_recipes.sql`) lets a user author a recipe —
title, category, hero image, author-estimated per-serving macros, an ordered
ingredient list, ordered instruction steps, and an optional "Recipe Fact" blurb
— and optionally share it into everyone's catalogue via the `is_public` flag
(the same sharing model `custom_foods` introduced in ADR-011 and ADR-024
adopted).

A shared recipe is genuinely valuable: a growing, user-curated catalogue of
carnivore / low-carb recipes, reusable across the whole userbase. We want to
keep leveraging it. This ADR settles **what happens to a recipe when its author
removes it, or deletes their account** — and how to keep the catalogue without
breaking the erasure guarantees ADR-013 established. It is the recipe analogue
of ADR-027 (which settled the same question for `custom_foods`).

### Two problems with the status quo

1. **`recipes` / `recipe_favorites` escape the erasure + export design.**
   ADR-013 deletes every user-owned table *explicitly* (`DELETE_ORDER`) rather
   than leaning on the `auth.users ON DELETE CASCADE`, precisely so erasure is
   transparent and unit-testable — and it exports every table the same way
   (`USER_TABLES`). But `recipes` and `recipe_favorites` are in **neither** list
   (`app/account/repository.py`). Today they are only cleaned up incidentally by
   the cascade when the admin user-deletion step succeeds, and they are
   **silently absent from the GDPR export** (Art. 20 portability gap). ADR-013's
   own consequences section warned this would happen to any table added without
   joining those lists; it did again.

2. **"Keep it because it's valuable" is not an erasure exception.** The instinct
   to retain a shared recipe as-is after a deletion request conflicts with the
   right to erasure (GDPR Art. 17). As stored, a recipe row is **personal data**:
   it is linked to `user_id`, timestamped, and carries author free text (the
   `fact` blurb, the hero `image_url`, and the ingredient/instruction lines). The
   *set* of recipes a person authors also reveals dietary/health habits. We
   operate in the EU region (Supabase Frankfurt) on health-adjacent data, so this
   is squarely in scope (ADR-026).

The escape hatch GDPR actually provides is **anonymisation** (Recital 26): data
that is *irreversibly* de-linked from the individual falls outside the regulation
and may be retained indefinitely. A bare recipe — "Pork Belly Bites, Breakfast,
8 oz pork belly…, 450 kcal / serving" — is factual *recipe* content, not data
about a *person*, once it is detached from the author. Pseudonymisation (keeping
`user_id`) is **not** enough; the link must be severed.

## Decision

**Anonymise on delete, don't retain author-linked rows.** When a user deletes a
recipe (or their whole account), we keep the *factual catalogue value* by copying
it into a separate, de-identified table and then hard-delete the original
user-owned row.

### 1. New table — `recipe_catalogue` (`014_recipes_anonymise.sql`)

A donated-facts table that is **not** a `USER_TABLES` member and has **no**
`user_id`:

- Columns: `title`, `category`, `serving_size`, the macro columns
  (`calories_kcal`, `protein_g`, `fat_g`, `carbs_g`), `ingredients`,
  `instructions`, `fact`, and `is_premium` — **the factual recipe fields only**.
- **Dropped on donation:** `user_id`, `created_at` (replaced by a coarse
  `donated_at` date with no tie to the user's activity), and **`image_url`**
  entirely. The hero image is the recipe analogue of `custom_foods`' `ocr_raw`:
  a user-supplied photo cannot be guaranteed non-identifying (EXIF / faces) and
  its storage URL may embed a user-scoped path, so it is never donated — it lives
  only on the user-owned row and dies with it.
- No natural unique key (recipes have no barcode), so donation is a plain insert
  — no upsert/dedup. Because the source row is hard-deleted immediately after,
  the same recipe cannot be re-donated, so rows do not pile up.
- RLS: readable by any authenticated user, writable only by the service role
  (the donation path), mirroring how the read-only external food sources behave.

### 2. Donation happens at the moment of deletion, service-side

- **Per-item delete** (`recipes.delete_recipe`): before deleting the row, copy
  its factual fields into `recipe_catalogue` (scrubbing as above), then delete.
- **Account delete** (`account.delete_user_data`): add `recipes` and
  `recipe_favorites` to the erase path, but route the recipes through the same
  donate-then-delete helper rather than a bare `DELETE`. After this, both tables
  are genuinely, explicitly erased — closing problem (1) on the deletion side.

Both paths run the donation on the service-role client — the one sanctioned
service-role data path (ADR-026) — because `recipe_catalogue` is writable only by
the service role.

### 3. Only donate what the user agreed to share

We donate a recipe **only if `is_public = true`**. A private recipe was never
shared and carries the strongest expectation of deletion; it is hard-deleted with
nothing kept. `is_public` already exists as the user's sharing signal — we reuse
it as the consent gate rather than inventing a new flag. (The authoring form must
make the "share to the catalogue" choice explicit at contribution time; if
today's UI defaults `is_public` silently, that is a required pre-req — see
Consequences.)

### 4. The catalogue reads the donated rows too

`recipe_catalogue` is merged into the recipe reads (`list_recipes`, `get_recipe`,
`list_categories`) as read-only, always-visible rows, so the donated recipes keep
showing up for the whole userbase — which is the entire point of keeping them.
Donated rows are shaped like a recipe row for the cards (`is_favorite` is always
false — favourites FK to `recipes`, not the catalogue — and the "New!" badge is
suppressed so deletion timing never leaks).

### 5. Close the export gap

Add `recipes` and `recipe_favorites` to `USER_TABLES` so a user's own recipes and
stars appear in their Art. 20 export. (The donated `recipe_catalogue` rows are
anonymous and intentionally *not* part of any individual's export.)

## Rationale

- **It actually delivers both goals.** The curated catalogue survives and stays
  useful to everyone; the individual's right to erasure is honoured because what
  remains is no longer their personal data.
- **It matches the house style.** Donation runs on the service-role client (the
  one sanctioned service-role data path, ADR-026) and the read side mirrors the
  external food sources' "service role writes, authenticated users read"
  pattern. It is the same shape as ADR-027.
- **Defensible by construction.** Dropping `user_id`/`created_at`/`image_url` and
  keeping only factual recipe fields is a concrete, reviewable anonymisation step,
  not a hand-wave. The `is_public` gate means we never retain anything from a user
  who kept their recipe private.
- **Fixes the latent ADR-013 bug as a side effect.** `recipes` and
  `recipe_favorites` finally join the explicit export and erasure lists.

## Consequences

- **Migration:** `014_recipes_anonymise.sql` must be run in the Supabase SQL
  editor before the new path works (manual-migration convention).
- **Required pre-req:** the authoring UI must capture `is_public` as an explicit,
  informed "share to the catalogue" choice; donating on an implicitly-defaulted
  flag would undermine the consent basis. Worth confirming the current default
  before shipping.
- **Privacy policy:** disclose that publicly-shared recipes are retained in
  anonymised form after account/item deletion. This is a policy/counsel touch
  point, not just code.
- **Not legal advice:** this records an engineering decision aligned with Art. 17
  / Recital 26; a DPO/counsel sign-off on the anonymisation boundary (especially
  "is a recipe's free-text `fact` / instructions truly non-identifying?") is the
  responsible final gate. The `fact` and instruction lines are donated as the
  recipe's factual content; if review finds them too risky, they can join
  `image_url` as dropped fields with a one-line change to the scrub list.
- **Maintenance:** `recipe_catalogue`'s factual columns must track any new
  field added to `recipes`, or donated rows silently lose those fields. The
  donated field list lives in one place (`recipes.repository._DONATED_FIELDS`).

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Retain `recipes` rows as-is after deletion (the original ask) | Keeps `user_id` + author free text + `image_url`; that is still personal data, so it conflicts with Art. 17. "It's valuable to us" is not an erasure exception. |
| Just scrub `user_id` in place on the existing table | Leaves `image_url`/`created_at` and the row inside the user-data blast radius. A separate facts table is a cleaner trust boundary. |
| Full delete, retain nothing (the conservative fix) | Safest, but throws away the curated catalogue the user explicitly wants to keep. Anonymisation gets the value *and* compliance. |
| Donate every recipe regardless of `is_public` | Retaining recipes a user kept private overreaches the sharing they consented to; gate on the existing public flag instead. |
| Keep `image_url` in the donated table for nicer cards | A user-uploaded photo can't be guaranteed non-identifying and its URL may embed a user-scoped path; donating it would defeat the anonymisation. Factual recipe text is what the catalogue needs. |
