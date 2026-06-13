# ADR-035: Master-record lifecycle for the common food catalogue

**Status:** Accepted
**Date:** 2026-06-13
**Author:** Faiz (solo developer)
**Sprint:** — (catalogue-quality follow-up)
**Builds on:** [ADR-034](034-catalogue-dedup-master-record.md) — which gave every
donated row a deterministic dedup key so the same product converges on one row.
This ADR is the **deferred half** ADR-034 named: the *lifecycle* of that
converged row — corroboration counting, a trusted `verified` master flag, and a
conflict policy that replaces last-writer-wins. Keeps the
[ADR-027](027-custom-food-anonymise-on-delete.md) /
[ADR-029](029-proactive-catalogue-donation.md) anonymisation boundary verbatim.

---

## Context

ADR-034 made *"one product, one row"* true by construction (a generated dedup
key + a unique index), but it explicitly left three things to a follow-up:

1. **No corroboration signal.** A catalogue row donated by one person and a row
   donated and re-confirmed by twenty are indistinguishable — both are flat
   facts. Search can't prefer the record many users agree on.
2. **No master/canonical concept.** There is no "this is the trusted record"
   flag, so the UI can't badge a corroborated product and the write path can't
   protect it.
3. **Last-writer-wins on a merge.** ADR-034's Consequences spelled this out: when
   two users donate the same `name|brand|serving` (or GTIN) with *different*
   macros, they share one row and **the later donation silently overwrites it** —
   including overwriting a known value with a `NULL` the newer row happened to
   lack. A single new contributor can quietly degrade a good record.

This ADR addresses all three with the smallest coherent slice. It deliberately
still defers **fuzzy near-duplicate matching** (catching `Coca-Cola` vs
`Coca Cola`, or servings that differ by a gram) — that needs a similarity/cluster
pass and a periodic job, is a separable concern, and is earmarked in ADR-034's
own alternatives table. Admin moderation UI is likewise out of scope.

### Compliance posture is unchanged — and the counter is deliberately *bare*

ADR-027/029/034 keep `food_catalogue` **anonymous**, not pseudonymous: no
`user_id`, no `created_at`, no reverse link of any kind (GDPR Recital 26). The
risk in *this* slice is the corroboration count. ADR-034 anticipated it:

> "this slice deliberately does **not** add a `contributor_count` … because
> counting *distinct users* would re-introduce a link the anonymisation severs.
> When the master-record follow-up adds a contributor signal it must do so as a
> **bare, user-unlinkable counter**; that is called out there, not here."

So this ADR adds exactly that: a plain integer that says *"how many times an
independent user row newly linked to this record"*, storing **no** identity, no
set of contributors, and no per-user mark on the catalogue. The "who" lives only
on the user's own `custom_foods.catalogue_id` back-pointer (ADR-029), which is
forward-only and dies with the user row. The catalogue holds a number; deleting
every contributor leaves the number standing with nothing to tie it to anyone —
which is precisely the anonymity property we want to preserve. It is a
corroboration proxy, **not** a verified distinct-user count, and the ADR is
honest about that limitation (see Consequences).

## Decision

**Give each converged catalogue row a corroboration count and a derived
`verified` master flag, and replace last-writer-wins with a conflict policy that
protects a verified record — all done atomically inside one donation RPC so there
is no read-modify-write race.**

### 1. Two columns on `food_catalogue` (`025_catalogue_master_record.sql`)

- **`contributor_count integer NOT NULL DEFAULT 1`** — a bare counter. A fresh
  donation inserts at `1`; a later donation that comes from a user row **not
  already linked to this record** increments it by one. A user re-syncing their
  *own* already-linked row does **not** increment (it isn't new corroboration).
  Stores no identity — see the compliance note above.
- **`verified boolean GENERATED ALWAYS AS (contributor_count >= 2) STORED`** — the
  master flag, derived in the database so it can never drift from the count, in
  the same spirit as ADR-034's generated keys. Two independent agreements is the
  threshold: one person is an assertion, two is corroboration. The threshold is a
  single literal, easy to revisit.

### 2. One atomic donation function (`donate_catalogue` RPC)

ADR-034 donated with a PostgREST `upsert`. Counting and the conflict policy need
to read the *existing* row's state (`verified`, `id`, current count) and write
back in one step; a PostgREST upsert can't express conditional `SET`s or an
atomic increment, and a read-then-write in Python would race two concurrent
donations. So the donation moves into a single `INSERT … ON CONFLICT … DO UPDATE`
inside a SQL function, called via `.rpc("donate_catalogue", …)`:

- **Conflict target** is chosen the same way as ADR-034 — `barcode_norm` when the
  row has a barcode, else `dedup_key` — by branching inside the function on
  whether the normalised barcode is non-null.
- **Insert path (new product):** writes the facts, `contributor_count = 1`.
- **Update path (merge):** applies the conflict policy below and bumps the count.

The function takes the factual fields as one `jsonb` payload (so it stays
agnostic to `_CATALOGUE_FIELDS` at the call boundary — ADR-034's single-source
list is unchanged) plus the donor row's **prior** `catalogue_id`, which is how it
decides whether this is new corroboration. It returns the resulting row so the
caller can still record the ADR-029 back-pointer. Execution is granted to
`service_role` only and revoked from `authenticated` / `public`: the catalogue is
service-role-writable (ADR-026), and the RPC must not become a way for a signed-in
user to mint or tamper with catalogue rows directly.

### 3. Conflict policy — verified records are protected, the rest build consensus

In the `DO UPDATE`, for every **factual** column:

```
col = CASE WHEN food_catalogue.verified              -- the EXISTING row
           THEN food_catalogue.col                   -- verified → keep it
           ELSE coalesce(EXCLUDED.col, food_catalogue.col)  -- else newest non-null wins
      END
```

- **Verified (`count ≥ 2`) → facts are frozen.** A single later donation can
  *corroborate* (bump the count) but cannot overwrite the agreed macros. This is
  the direct fix for ADR-034's "a single new contributor can silently overwrite a
  good record."
- **Not yet verified → newest non-null wins.** While consensus is still forming,
  a newer donation updates the facts — but via `coalesce`, so it **never nulls
  out a known value** it simply didn't carry. That is already a strict
  improvement over ADR-034's raw last-writer-wins (which overwrote with NULLs).
- The flip happens on the **second** contributor: the `DO UPDATE` reads the *old*
  row (`verified = false`, count `1`), so that donation's facts win **and** the
  count goes to `2`, locking the record. Two users who agree set the canonical
  value; the third onward only corroborate. Genuine variants don't collide here —
  a different serving or barcode is already a different key (ADR-034).

`contributor_count` updates as:

```
contributor_count = food_catalogue.contributor_count
    + CASE WHEN food_catalogue.id IS DISTINCT FROM p_prior_catalogue_id
           THEN 1 ELSE 0 END
```

The donor's prior `catalogue_id` is compared to the row it just hit: same →
re-sync of an already-counted link, no bump; different (or `NULL`) → a newly
linking row, +1. No contributor identity is read or stored to make this decision.

### 4. Read side prefers the trusted record (`food_catalogue.py`)

Catalogue search and barcode lookup select `verified, contributor_count` and
**order verified rows first, then by `contributor_count` desc**. Because the
registry inserts the catalogue results as an ordered block (it doesn't re-sort
them), the corroborated record surfaces above one-off donations in the merged
"all" search. The wire shape — the shared `FoodItem` (ADR-018) — is **left
unchanged**; the trust signal is delivered as *ranking*, not a new field, keeping
this slice backend-only. A visible "verified" badge in the iOS food picker is a
small, noted follow-up that can read the same flag once we choose to widen the
contract.

## Rationale

- **Corroboration without re-identification.** The whole reason ADR-034 punted
  the counter was the distinct-user trap; a bare increment keyed off the donor's
  *own* back-pointer gives a useful "how corroborated is this" signal while
  storing nothing that ties the catalogue back to a person.
- **The DB stays the source of truth.** `verified` is generated from the count
  exactly as ADR-034's keys are generated from the facts — no second writer, no
  drift. The conflict policy lives in one SQL function, not scattered across the
  app.
- **Atomic by construction.** Counting and protecting are inherently
  read-and-write; doing them in a single `INSERT … ON CONFLICT` removes the race
  that a Python read-modify-write would have introduced, and removes ADR-034's
  residual last-writer race for verified records.
- **Same trust boundary.** No reverse link, no per-user mark, same `_CATALOGUE_
  FIELDS` scrub, same `is_public` gate. The ADR-027/029/034 anonymisation
  reasoning carries over verbatim.

## Consequences

- **Migration is manual and ships with the code.** `025_catalogue_master_record.
  sql` must be run in the Supabase SQL editor before deploying the `custom.py`
  change (numbered-migration convention). They are co-dependent: the new code
  calls `donate_catalogue`, which the migration creates; old code against the new
  schema (or vice-versa) keeps working for *reads* but the donation path requires
  both.
- **Verify the RPC round-trip in staging.** As with ADR-034, the donation now
  resolves on a generated column and runs server-side logic that the mocked test
  suite can't exercise against a live DB. Confirm a public-food donation —
  insert, second-contributor merge (count → 2, verified flips), and a third
  donation against a verified row (count bumps, facts unchanged) — round-trips
  against staging Supabase before relying on it in production.
- **The count is a corroboration proxy, not a distinct-user count.** A user who
  deletes and re-adds the same public food, then re-links, can bump the count
  more than once; the count cannot be deduplicated by user without storing the
  very identity the anonymisation forbids. This is an accepted, deliberate
  imprecision — the signal is "independently linked N times", and it errs toward
  over- not under-counting corroboration. It is **not** safe to present as
  "N distinct people verified this."
- **A verified record can lock in a wrong value.** If the first two donations
  happen to agree on a bad number, it freezes until a human corrects it (no admin
  tooling in this slice) or the deferred fuzzy/moderation pass arrives. Acceptable
  for a community catalogue that is one input among several sources, never the
  sole authority for a diary entry.
- **Orphans and renames behave as in ADR-034.** Renaming a barcodeless public
  food still re-keys it to a new `dedup_key` and writes a new (count = 1) twin,
  orphaning the old one. The deferred cleanup still owns sweeping those.
- **`FoodItem` is unchanged**, so no iOS decode change is required; the only
  user-visible effect today is that corroborated catalogue items rank higher in
  search. The badge is a follow-up.
- **Not legal advice.** As in ADR-027/029/034, the DPO/counsel sign-off on the
  anonymisation boundary is the responsible final gate. This change adds a bare
  counter and a derived flag; it does not move that boundary, but the
  "bare counter, no identity" property is the thing to confirm at sign-off.

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Keep ADR-034 last-writer-wins | Leaves the actual lifecycle gap: no trust signal and a single contributor can silently overwrite a corroborated record (incl. with NULLs). |
| Count **distinct users** (store contributor ids/hashes) | Re-introduces exactly the user→catalogue link ADR-027/029 sever (Recital 26). A bare increment gives most of the value with none of the re-identification risk. |
| Increment on **every** donation upsert | A single user re-saving their public food would inflate the count; the back-pointer check makes it "new link" events, a better corroboration proxy, at no identity cost. |
| Do counting + conflict policy in **Python** (read then write) | Races two concurrent donations and re-introduces ADR-034's last-writer window for verified rows; one atomic `INSERT … ON CONFLICT` is correct and keeps the policy in one place. |
| `verified` as a plain, app-set boolean | Lets the flag drift from the count and adds a second writer; a generated column keeps the DB authoritative, matching ADR-034. |
| Add a `verified` field to `FoodItem` now | Widens the stable shared contract and forces an iOS decode change for a badge we haven't designed; ranking delivers the search benefit today, the field can follow when the badge does. |
| Build fuzzy near-duplicate matching in this slice | A separate similarity/cluster + periodic-job concern (ADR-034's alternatives already earmark it); folding it in would balloon a clean schema+policy move. Deferred again, on purpose. |
