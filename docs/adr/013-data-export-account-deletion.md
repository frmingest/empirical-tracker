# ADR-013: GDPR data export, account deletion, and security headers

**Status:** Accepted
**Date:** 2026-06-01
**Author:** Faiz (solo developer)
**Sprint:** 6 (part 1 of: doctor sharing · GDPR export · security audit)

---

## Context

ADR-003 committed Sprint 6 to "full data export (CSV/JSON) and account deletion,"
the two data-subject rights that matter most for the health data this app stores:

- **Right to data portability** (GDPR Art. 20) — the user can take their data elsewhere.
- **Right to erasure** (GDPR Art. 17) — the user can have everything deleted.

Neither existed yet. The schema was, however, already designed for this: every
user-owned table carries a `user_id` column with an RLS policy, and each references
`auth.users(id) ON DELETE CASCADE`. So export is "select every table by `user_id`"
and erasure is "delete every table by `user_id`."

This sprint slice also folds in the low-risk half of the "security audit" item:
baseline HTTP security headers.

The third Sprint 6 item — **doctor sharing** — is scoped separately as a
PDF/printable report and deferred to a follow-up; it is not part of this ADR.

---

## Decision

### 1. Export — `GET /account/export?format=json|csv`

A new `app/account/` module (router + repository, matching every other feature
module). `repository.collect_user_data` selects `*` from each table in
`USER_TABLES`, scoped by `user_id`. `build_export` wraps the rows with metadata
(`exported_at`, per-table `row_counts`, a `format_version`).

- **JSON** — one pretty-printed document: `{ export_meta, data: { <table>: [...] } }`.
- **CSV** — a zip with one `<table>.csv` per **non-empty** table plus
  `export_meta.json`. Empty tables are omitted from the archive but stay
  documented via `row_counts`, so the export is still complete and unambiguous.

Both are returned as a download (`Content-Disposition: attachment`). The export
uses `select("*")` deliberately — unlike the feature repositories' explicit column
lists — because the user owns every column and full transparency is the goal.

### 2. Erasure — `DELETE /account`

`repository.delete_user_data` deletes every table in `DELETE_ORDER` (children
before parents, so foreign keys never block erasure: `results` before
`panels`/`biomarkers`, `planned_meals` before `meal_plans`), then removes the auth
user via the admin API so the login itself is gone.

We delete rows **explicitly** rather than relying solely on the `auth.users`
`ON DELETE CASCADE`. Reasons: it is transparent (the code says exactly what is
erased), it is unit-testable without a live database, and it still erases the
health data even if the admin user-deletion step is unavailable. If that step
fails, the response reports `account_deleted: false` so the caller knows the login
record may linger while the data is already gone.

### 3. Security headers

A single `@app.middleware("http")` adds baseline headers to every response:
`X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`,
`Referrer-Policy: no-referrer`, `Strict-Transport-Security`, and a strict
`Content-Security-Policy: default-src 'none'; frame-ancestors 'none'`. The API
serves only JSON and the export download — no HTML, scripts, or frames — so the
policy can be maximally restrictive without affecting functionality.

### 4. Frontend

A new `/account` page (linked from the dashboard nav when signed in) with an
**Export** section (Download JSON / CSV buttons) and a **danger zone** that requires
typing `DELETE` to confirm, then signs out and redirects to `/login`.

---

## Rationale

- **No new dependencies.** Export uses only the standard library (`json`, `csv`,
  `zipfile`, `io`); no `pandas`/`reportlab` needed for tabular data.
- **Erasure is a structural property.** Because isolation is by `user_id` + RLS
  (ADR-003, Art. 25), the same key that scopes reads scopes deletes — there is no
  data to "hunt for."
- **Defense in depth on the deletes.** Explicit per-table deletion is correct even
  if a future table is added without an `ON DELETE CASCADE`, as long as it joins
  `USER_TABLES`/`DELETE_ORDER`.

---

## Consequences

- **Good:** Art. 17 and Art. 20 are now satisfied end-to-end.
- **Good:** Security headers harden every endpoint at one choke point.
- **Trade-off / maintenance note:** `USER_TABLES` and `DELETE_ORDER` must be
  updated whenever a new user-owned table is added (Sprints 9–10 add
  `body_metrics`, and any new nutrient columns). A missing table would silently
  drop out of both export and erasure — call this out in those sprints' reviews.
- **Follow-up:** doctor sharing (PDF/printable report) remains open for Sprint 6.

---

## Alternatives considered

| Option | Rejected because |
|--------|-----------------|
| Rely only on `auth.users` cascade for erasure | Opaque and untestable; explicit deletes are clearer and survive a missing cascade |
| One combined CSV for all tables | Tables have different columns; a zip-per-table is the honest tabular representation |
| Include empty tables as empty CSVs | No column header is known for a zero-row table; `row_counts` documents them instead |
| `pandas` for CSV export | Heavy new dependency for what `csv.DictWriter` does in a few lines |
