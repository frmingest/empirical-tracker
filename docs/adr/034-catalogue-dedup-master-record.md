# ADR-034: Deterministic de-duplication keys for the common food catalogue

**Status:** Accepted
**Date:** 2026-06-13
**Author:** Faiz (solo developer)
**Sprint:** — (catalogue-quality follow-up)
**Builds on:** [ADR-027](027-custom-food-anonymise-on-delete.md),
[ADR-029](029-proactive-catalogue-donation.md) — keeps the anonymisation
boundary and the `is_public` consent gate; changes only *how the donated twin is
keyed* so the same product stops piling up.

---

## Context

The anonymous `food_catalogue` (ADR-027/029) is the shared "common catalogue":
public custom foods are mirrored into it, stripped of `user_id` / `created_at` /
`ocr_raw`, and surfaced to the whole userbase in search and barcode lookup. The
**only** de-duplication today is a `UNIQUE` on the raw `barcode` column, so the
same product is donated as a fresh row over and over in three common cases:

1. **Barcodeless products** — whole foods, deli/restaurant items, and any
   label-scan where no barcode was captured. They have no natural key, so
   `sync_catalogue` inserts a new row per donation. Two users who each add
   "Rema 1000 Kyllingfilet" create two catalogue rows; ten users create ten.
2. **Barcode-format variants of one product** — UPC-A (12 digits), EAN-13
   (13 digits) and leading-zero encodings of the *same* GTIN are distinct
   strings, so the raw-`barcode` `UNIQUE` treats them as different products and
   they never merge.
3. **No master/canonical concept** — catalogue rows are flat donated facts with
   no signal for "this is the corroborated, trusted record" versus "one user's
   variant", so search can't prefer the best record and a single new contributor
   can silently overwrite a good one.

This ADR addresses (1) and (2) — give every donated row a **deterministic,
normalised dedup key** so the same product converges on one row regardless of
who donates it or how their barcode happened to be encoded. The master-record
*lifecycle* (3) — `contributor_count`, a `verified` master flag, a conflict
policy on disagreeing macros, and fuzzy near-duplicate matching — is a larger,
separable change deferred to a follow-up ADR; this slice is the foundation it
will build on.

### Compliance posture is unchanged

This changes only the *key* a donated row is written under. It copies the same
factual fields (`_CATALOGUE_FIELDS`), still drops `user_id` / `created_at` /
`ocr_raw`, and still gates on `is_public`. No per-user data is added to
`food_catalogue` — in particular this slice deliberately does **not** add a
`contributor_count` or any per-contributor record, because counting distinct
users would re-introduce a link the anonymisation severs (Recital 26). When the
master-record follow-up adds a contributor signal it must do so as a bare,
user-unlinkable counter; that is called out there, not here.

## Decision

**Key every donated row by a generated, normalised dedup key and upsert on it, so
the same product merges across users — for barcoded *and* barcodeless rows.**

### 1. Two generated keys on `food_catalogue` (`024_catalogue_dedup_keys.sql`)

Both are `GENERATED ALWAYS … STORED`, so the database is the single source of
truth and the key can never drift from the facts it derives from:

- **`barcode_norm`** — the barcode digits left-padded to **GTIN-14**
  (`lpad(digits, 14, '0')`), `NULL` for barcodeless rows. Collapses UPC-A /
  EAN-13 / leading-zero encodings of one product onto a single key. (This is a
  *dedup* normalisation, not a GS1-correct GTIN conversion — e.g. EAN-8 is
  zero-padded too; internal consistency is what matters, not catalogue
  interchange.)
- **`dedup_key`** — `lower(name)|lower(brand)|round(serving_g)` for barcodeless
  rows, `NULL` when a barcode exists (`barcode_norm` governs those). Gives
  barcodeless products the natural key they previously lacked.

A row therefore has exactly one non-null key: barcoded rows key on
`barcode_norm`, barcodeless rows on `dedup_key`.

### 2. Full unique indexes, not partial

```
CREATE UNIQUE INDEX food_catalogue_barcode_norm_key ON food_catalogue (barcode_norm);
CREATE UNIQUE INDEX food_catalogue_dedup_key_key    ON food_catalogue (dedup_key);
```

Full (non-partial) indexes on nullable columns: Postgres treats NULLs as
distinct, so barcodeless rows (NULL `barcode_norm`) and barcoded rows (NULL
`dedup_key`) never collide on the index that doesn't apply to them. A *partial*
index (`WHERE … IS NOT NULL`) would have been tidier but **breaks `ON CONFLICT`
inference** — PostgREST's `on_conflict` names columns only, not a predicate, so
the donation upserts could not target a partial index. The raw-`barcode`
`UNIQUE` constraint and its perf index are dropped and replaced by these.

### 3. Donation upserts on the applicable key (`custom.py`)

`donate_to_catalogue` and `sync_catalogue` choose the conflict target per row —
`barcode_norm` when a barcode is present, else `dedup_key` — and **upsert** on
it. The previous "barcodeless → plain `insert`" branch is gone; barcodeless
donations now merge cross-user exactly like barcoded ones. The forward-only
`custom_foods.catalogue_id` back-pointer (ADR-029) is still recorded for read
de-duplication and survives unchanged.

### 4. Collapse the duplicates already in the table

Adding a unique index to data that already contains duplicates would fail, so the
migration first merges existing rows: group by key, keep the **most complete**
row (fewest NULL facts; oldest donation breaks ties), repoint any
`custom_foods.catalogue_id` from losers to the survivor, then delete the losers.
This is intentionally conservative — the survivor's own facts are kept as-is, no
cross-row fact-coalescing and no fuzzy near-duplicate matching (those belong to
the deferred master-record ADR).

## Rationale

- **One product, one row — by construction.** A deterministic key plus a unique
  index makes the duplicate states from the Context *unrepresentable*, rather
  than something a periodic cleanup chases after the fact.
- **Barcodeless parity.** The biggest gap was that barcodeless products never
  merged; a name|brand|serving key closes it with the same upsert path already
  used for barcodes.
- **DB-guaranteed keys.** Generated columns mean the key is always consistent
  with the facts and there is no second writer to keep in step.
- **Same trust boundary.** No reverse link or per-user data is added to the
  anonymous table; the `is_public` gate and the scrub list are untouched, so the
  ADR-027/029 anonymisation reasoning carries over verbatim.

## Consequences

- **Migration is manual.** `024_catalogue_dedup_keys.sql` must be run in the
  Supabase SQL editor before deploying the `custom.py` change (manual-migration
  convention). The two ship together: the migration swaps the upsert's conflict
  target from `barcode` to `barcode_norm`/`dedup_key`, so the old code against
  the new schema (or vice-versa) would fail donation.
- **Verify `ON CONFLICT` on a generated column in staging.** The donation upserts
  resolve on a unique index over a *generated* column. This is standard Postgres,
  but confirm a public-food donation round-trips against staging Supabase before
  relying on it in production, since it can't be exercised against a live DB from
  the test suite (which mocks the client).
- **Rename orphans a barcodeless twin.** Because the key now derives from
  name/brand/serving, renaming a barcodeless public food changes its
  `dedup_key`, so the upsert writes a *new* twin and the old one is orphaned with
  stale facts — the same behaviour a barcode change already had. The orphan is
  harmless anonymous data; the deferred master-record cleanup will sweep such
  rows.
- **Last writer wins on a barcodeless merge.** When two users donate the same
  name|brand|serving with different macros, they now share one row and the later
  donation overwrites it. Acceptable for this slice; a real conflict policy
  (keep the corroborated/verified facts, branch genuine variants) is exactly what
  the master-record follow-up adds.
- **Single source of truth for fields.** `_CATALOGUE_FIELDS` stays the one list
  of donated columns; the generated keys derive from those columns and need no
  maintenance when a factual column is added.
- **Not legal advice.** As in ADR-027/029, the DPO/counsel sign-off on the
  anonymisation boundary is the responsible final gate; this change does not move
  that boundary.

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Keep raw-`barcode`-only dedup (ADR-029 as-is) | Leaves barcodeless products and barcode-format variants piling up — the actual problem. |
| Partial unique indexes (`WHERE … IS NOT NULL`) | Tidier, but PostgREST `on_conflict` can't target a partial index, so the donation upserts couldn't dedupe. Full indexes over nullable columns get the same effect (NULLs distinct). |
| Compute the keys in Python and store as plain columns | Works, but lets the key drift from the facts and adds a second writer to keep in step; generated columns make the DB authoritative. |
| Normalise barcodes but not barcodeless names | Fixes only half the duplication; the larger, more frequent source is barcodeless whole-food / restaurant items. |
| Add `contributor_count` / `verified` master now | Larger, separable change with its own compliance surface (a distinct-user count); split into a follow-up ADR so this slice stays a clean, low-risk schema move. |
| Periodic dedup job instead of a unique key | Reactive — duplicates still appear between runs. A key + index prevents them; a job is still wanted later for *fuzzy* near-duplicates the exact key can't catch. |
