# ADR-003: GDPR Data Handling for Health Data

**Status:** Accepted  
**Date:** 2026-05-31  
**Author:** Faiz (solo developer)

> **Update (ADR-026, 2026-06-04):** Points 2–4 below describe the *intended* RLS
> model. When the web client was retired, the FastAPI backend became the only
> client and accessed Postgres with the **service-role key**, which **bypasses
> RLS** — so on the live API path isolation rested on application-layer
> `.eq("user_id", …)` filtering, not on the database backstop this ADR promises.
> [ADR-026](026-security-risk-compliance.md) restored that backstop: the API now
> queries Postgres *as the user* via a per-request, JWT-scoped client, and the
> service-role key is reserved for account erasure only. Read points 2–4 as
> realised by ADR-026, not by the original service-role implementation.

---

## Context

Blood test results are **GDPR Article 9 special-category data** (health data). Processing them
requires explicit consent and specific technical safeguards. The user is EU/Norway-based.
As the data controller, the developer must implement appropriate technical measures.

---

## Decision

1. **EU data residency** — Supabase project provisioned in `eu-central-1` (Frankfurt).
   All data at rest and in transit stays in the EU.

2. **Row-Level Security on every table** — RLS policies enforce `auth.uid() = user_id`
   at the database layer. Even if application code had a bug that sent a wrong user_id,
   Postgres would reject the query.

3. **Service-role key server-side only** — The `SUPABASE_SERVICE_KEY` is a Railway secret,
   never exposed to the browser. The browser only ever holds the anon key, scoped by RLS.

4. **JWT validation on every API call** — The FastAPI layer calls `supabase.auth.get_user(token)`
   before touching any data. There is no endpoint that accepts data without a valid, live JWT.

5. **Export/delete by user_id** — Sprint 6 implements full data export (CSV/JSON) and
   account deletion. The schema is designed for this: every table has `user_id`, so
   `DELETE FROM biomarkers WHERE user_id = ?` cascades to panels and results cleanly.

6. **No third-party analytics on health data** — The dashboard never sends biomarker data
   to analytics services (no Segment, no Mixpanel on data pages).

7. **Explicit consent at signup** — Sprint 1 auth flow will include a clear consent screen
   stating that blood test data is stored and processed for personal health tracking.

---

## Rationale

GDPR Article 9(2)(a) allows processing special-category data with "explicit consent". Article 25
requires "data protection by design" — meaning the isolation must be a structural property of
the system, not just an application-layer promise.

RLS at the database layer satisfies Article 25: isolation doesn't depend on the application
correctly filtering queries; it is enforced by the storage engine itself.

Storing everything in EU (`eu-central-1`) satisfies Article 44 (no transfer to third countries)
for a Norwegian data subject.

---

## Consequences

- **Good:** A compromised API key cannot access another user's health data (RLS blocks it)
- **Good:** GDPR export/delete is a simple query by `user_id` — no complex data hunting
- **Good:** EU region means no need for Standard Contractual Clauses or adequacy decisions
- **Trade-off:** Can't use the free-tier Supabase project if it isn't EU-region — must
  verify region at project creation
- **Trade-off:** JWT validation on every request adds one network round-trip to Supabase Auth.
  Acceptable at single-user scale; could cache with short TTL if needed

---

## Alternatives Considered

| Option | Rejected because |
|--------|-----------------|
| Application-level tenant filtering only | Article 25 requires structural isolation, not just app logic |
| Encrypting each row with user key | Over-engineering; RLS provides equivalent isolation with less complexity |
| US-region Supabase | Article 44 violation for EU/Norwegian data subject |
| Anonymising blood data | Defeats the purpose — personalised correlation requires identifiable data |
