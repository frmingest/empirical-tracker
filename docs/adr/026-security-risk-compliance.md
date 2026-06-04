# ADR-026: Security, Risk & Compliance Baseline

**Status:** Accepted (F1 implemented; F2–F10 sequenced)
**Date:** 2026-06-04
**Author:** Security / iOS-platform review
**Supersedes the RLS guarantee in:** [ADR-003](003-gdpr-data-handling.md) (clarified, not retired)

---

## Context

Empirical Tracker processes GDPR **Article 9 special-category (health) data** —
blood biomarkers, body metrics, and diet logs — for an EU/Norway data subject.
The product is already thoughtful about this (EU-region storage, Keychain-stored
JWTs, a versioned consent gate, security headers, a schema where every table
carries `user_id`). But a structured security/risk/compliance review found that
the **documented** security model and the **actual** one diverged in one critical
place, and that several health-data-grade controls were missing rather than weak.

This ADR records the baseline: the prioritised findings, the decision to fix the
critical one now, and the sequencing for the rest. Findings are referenced as
**F1–F10** so follow-up ADRs and issues can cite them.

---

## Findings

### F1 · RLS was bypassed on the entire live data path 🔴 — **fixed in this ADR**

`api/app/db.py` built a single Supabase client with the **service-role key**, and
every repository used it. The service role **bypasses Row-Level Security by
design.** RLS therefore only protected the *anon-key* path — which the iOS client
never uses, because it talks to the FastAPI backend, not Postgres directly.

So the guarantee in ADR-003 / `SOLUTION.md` — *"even if application code had a bug
that sent a wrong `user_id`, Postgres would reject the query"* — **was not true for
the real data path.** Tenant isolation rested entirely on every repository
remembering to add `.eq("user_id", user_id)`. They all did, but it was one
forgotten filter on one new endpoint away from a cross-tenant **health-data**
leak, with **no database backstop** — while the docs asserted the backstop
existed. That is an Article 25 ("data protection by design") gap, not just a code
smell.

### F2 · No rate limiting anywhere 🟠
No throttle on auth, uploads, search, or the LLM endpoint. With F3/F4 this is a
real DoS and cost-amplification surface on a public API.

### F3 · `/biomarkers/import` reads the whole upload into memory, unchecked 🟠
`await file.read()` with no `Content-Length` cap → memory-exhaustion DoS. Only the
`.xlsx` *extension* is checked (no magic-byte validation), and `openpyxl` parses
attacker-controlled XML (zip-bomb / entity-expansion exposure).

### F4 · `parse-label` ships an untrusted image to an LLM 🟠
Authenticated (good) but no size cap and no rate limit — a prompt-injection and
spend surface. Output is already validated into a Pydantic shape; keep that strict.

### F5 · Token validated by a network call to Supabase on every request 🟠
`current_user_id` calls `auth.get_user(token)` per request — no local JWT
signature verification, no caching. A latency tax, a hard availability dependency
on Supabase Auth, and (with F2) an amplification vector.

### F6 · Keychain item is backup/iCloud-syncable 🟡
`KeychainService` sets no `kSecAttrAccessible`, so the JWT defaults into device /
iCloud-Keychain backups and can migrate off-device. Should be
`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; consider an optional Face ID
App-Lock.

### F7 · Consent is local-only — no server-side audit trail 🟡
`ConsentStore` (UserDefaults) gates the UI and its own doc-comment admits it "is
not a substitute for the signup-time consent recorded server-side" — but that
server record does not exist. Article 9 explicit consent must be *demonstrable*:
who consented, when, to which policy version.

### F8 · Anthropic / USDA are undocumented sub-processors 🟡
The label-OCR flow sends user-submitted images to **Anthropic (US)** — a new
special-category-adjacent data flow and an Article 44 transfer — and USDA is
queried server-side. Neither is governed by a published sub-processor list / DPA,
nor confirmed in `PrivacyInfo.xcprivacy` and the privacy policy.

### F9 · CORS is credentialed and wildcarded for a non-browser client 🟡
`allow_credentials=True` with `allow_methods=["*"], allow_headers=["*"]`. The only
client is the iOS app (no cookies), so credentialed CORS is unnecessary and a
misconfiguration risk (it is also invalid combined with `allow_origins=["*"]`).

### F10 · No audit logging / breach-detection readiness 🟡
No record of access to health data → GDPR Art 33/34 breach notification cannot be
substantiated. Needs structured access logging (no PII in logs), a retention
policy, and a documented breach-response runbook.

### Compliance closeout (paperwork half of the above)
Legal docs carry `[TBD]` controller identity, contacts, jurisdiction, and no
hosting URL (`docs/legal/README.md`); no documented data-retention / minimization
policy; service-key rotation undocumented (a single high-value secret = full DB
access bypassing RLS).

---

## Decision

### Now (this ADR): fix F1 — enforce RLS on the API path

The backend no longer uses the service-role key for user data. Instead:

1. **`make_user_supabase(access_token)`** (`app/db.py`) builds a per-request
   Supabase client with the **public anon key** as `apikey` and the caller's
   **JWT** as the bearer (`client.postgrest.auth(token)`). PostgREST then runs
   every query *as the user*, so Postgres RLS (`auth.uid() = user_id`) enforces
   isolation in the database itself.
2. **`current_user_id`** (`app/auth.py`) builds that client, validates the token
   against it, and **binds it for the request** via a `ContextVar`.
3. **`get_supabase()`** returns the bound, RLS-scoped client and **fails closed**:
   if no client is bound (i.e. a request never passed the auth dependency) it
   *raises* rather than silently falling back to the service role. A new endpoint
   therefore cannot accidentally query user data with RLS bypassed.
4. The service-role client (`get_service_supabase()`) is **reserved for one
   sanctioned admin path**: account erasure (`delete_user_data`), which removes
   the auth user via the admin API and must complete regardless of RLS.
5. The existing per-repository `.eq("user_id", user_id)` filters are **kept** as
   defence-in-depth (and remain required so inserts set `user_id` for RLS
   `WITH CHECK`).

**Why a `ContextVar` rather than threading a client through every signature:** it
keeps the change localized to `db.py`/`auth.py`, leaves the well-tested repository
filters and their tests untouched (avoiding a 17-file mechanical refactor that
could itself introduce the very missed-filter bug we are removing), and is safe
here because every authenticated endpoint is `async def` and resolves its
dependencies in the same context it runs in — the bound client propagates to the
endpoint and the synchronous repository calls it makes, and each request runs in
its own copied context so nothing leaks between requests. The property that makes
this *secure* rather than *convenient* is that it fails closed.

**New configuration:** `SUPABASE_ANON_KEY` must now be set on the API
(`app/config.py`, `.env.example`, `docs/SETUP.md`). It is the public key the iOS
app already ships; it is **not** a secret, but it is now required server-side.

### Next — sequenced, not yet built

| Phase | Items | Rationale |
|-------|-------|-----------|
| **P1 — Hardening** | F2 rate limiting; F3 upload size/type + hardened xlsx parse; F4 OCR size/rate limits; F5 local JWT verification + short cache | Remove DoS / cost / availability surfaces on a public API |
| **P2 — Client & governance** | F6 `…ThisDeviceOnly` (+ optional App-Lock); F7 server-side `consents` table; F8 sub-processor list + DPA + manifest; F9 drop credentialed/wildcard CORS; F10 access logging + breach runbook | Demonstrable GDPR consent, transport, sub-processor & breach readiness |
| **P3 — Compliance + UX** | Legal `[TBD]` closeout + hosting URL; retention/minimization policy; service-key rotation; a "Your data" transparency screen with one-tap export/delete; layered + per-flow consent | Submittable and trustworthy; aligns with `IOS_APP_STORE_READINESS.md` |

---

## Consequences

- **Good:** Tenant isolation is now a structural property of the database on the
  live path (Article 25 satisfied in fact, not just intent). A forgotten
  `user_id` filter can no longer leak another user's health data — RLS denies it.
- **Good:** Fail-closed `get_supabase()` makes the secure path the only path; new
  endpoints inherit isolation or break loudly.
- **Good:** Service-role blast radius shrinks to a single audited admin operation.
- **Trade-off:** One extra Supabase client is constructed per request. Acceptable
  at current scale; F5 (local JWT verification + caching) will reduce the
  per-request auth round-trip that dominates this cost.
- **Trade-off:** The API now requires `SUPABASE_ANON_KEY` in its environment;
  deployments missing it fail closed with a clear error.
- **Migration:** No schema change — RLS policies already exist
  (`auth.uid() = user_id`, RLS enabled per table since migration 001). This ADR
  makes the API actually run under them.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Keep service-role + rely on `.eq("user_id")` filters | The status quo this ADR exists to fix: no DB backstop, contradicts the documented Art 25 guarantee |
| Thread an explicit `db` client through every repository signature | Correct but a large mechanical diff across ~17 files + their tests; higher risk of a missed call site than the localized ContextVar approach, for no extra security benefit given fail-closed |
| Per-request service client with `SET LOCAL request.jwt.claims` | More moving parts than `postgrest.auth(token)`; the SDK already supports per-client JWT bearer cleanly |
| Decode the JWT locally instead of `auth.get_user` | A good optimization (F5) but orthogonal to enforcing RLS; deferred to keep this change focused |
