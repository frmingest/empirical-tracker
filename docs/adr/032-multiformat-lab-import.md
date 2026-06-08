# ADR-032: Multi-format lab import — PDF & image documents beyond `.xlsx`

**Status:** Proposed
**Date:** 2026-06-08
**Author:** Architecture proposal (Claude)
**Sprint:** Ingestion follow-up (extends ADR-001 `.xlsx` import; builds on the
food-label OCR pipeline, ADR-016)

> Research backing this ADR: `docs/research/ios-multiformat-upload.md`.

---

## TL;DR

The only file-based way into the biomarker store today is the Norwegian lab
`.xlsx` import. Real users receive results as **PDF reports** (Fürst, Dr. Dropin,
Aleris, hospital portals) or as **photos/screenshots** of a printed sheet. This
ADR extends ingestion to **PDF and image** documents while keeping the app's two
non-negotiables: **never invent a number**, and **never silently drop user data**.

The design is **additive and reuses what already exists**:

- The food-label flow (Apple Vision OCR on-device → Claude → strict JSON →
  persist `ocr_raw`) is the proven blueprint; we apply the same shape to lab
  reports with a richer schema and a **mandatory human-review** step.
- The biomarker catalog is already **per-user and open** (no global whitelist),
  so unknown analytes are an upsert, not a constraint violation.
- Anything we *can't* map cleanly lands in a new **`lab_imports` staging table**
  rather than being rejected — the upload always succeeds.

Two extraction postures are offered behind one switch: **on-device OCR
(private, default)** and **send-the-document to a vision model (best quality,
consent-gated)**.

---

## Context — why this, why now

### What ingestion does today

- **`.xlsx` import** (ADR-001): `UIDocumentPickerViewController` → multipart
  upload → `POST /biomarkers/import` (`api/app/biomarkers/router.py:87`) →
  `openpyxl` parser (`api/app/biomarkers/parser.py:77`) → upsert biomarker
  catalog + panel + results (`api/app/biomarkers/repository.py:11`). Hardened
  with a 10 MiB cap, ZIP-bomb/magic-byte checks, and chunked reads
  (`config.py:30-31`, `biomarkers/router.py:25-105`).
- **Manual entry**: `POST /biomarkers/results/manual` adds one value to an
  existing biomarker (`biomarkers/router.py:182`).
- **Food-label OCR** (ADR-016): Apple Vision `VNRecognizeTextRequest` on-device
  (`NutritionLabelCaptureView.swift:151`) → **text only** to the backend →
  Claude Haiku extracts strict JSON, "never invent, null when unsure"
  (`food_sources/label_parser.py:27`) → raw model output persisted
  (`custom_foods.ocr_raw`); OCR text capped at 20k chars (`config.py:32`).

### The gap

`.xlsx` is a *Fürst-specific* export format. A user whose lab gives them a **PDF**
or who **photographs** a printout has no path in — they must hand-key every row
through manual entry. Yet the hardest part of that flow (capture → structure →
store) is **already solved for food labels**. We should generalise it.

### Why it's lower-risk than it looks

1. The food-label pipeline is the same problem class and is in production.
2. The biomarker schema was deliberately built **open** (per-user catalog, no
   enum/whitelist on marker names or units), so new analytes "just work."
3. We already depend on the `anthropic` SDK, so a vision-model path adds no new
   vendor.

---

## What each input needs

| Input | Detection | Extraction | Notes |
|-------|-----------|------------|-------|
| **Text-based PDF** (portal exports) | `PDFDocument.string` returns substantive text | **PDFKit text layer — read directly** | Near-perfect, free, no OCR error. *Always try first.* |
| **Scanned / image PDF** | text layer empty/garbage | rasterize pages → Vision OCR (or vision model) | Multi-page handled per page. |
| **Photo / screenshot** | n/a | `VNDocumentCameraViewController` capture → Vision OCR (or vision model) | DocCamera gives auto-deskew/edge-detect — big quality lever. |

The net rule: **prefer the embedded text layer when it exists; only OCR when
forced to.**

---

## Decision (proposed)

### 1. iOS — widen capture, reuse the upload

- **Picker:** extend the existing `UIDocumentPickerViewController` content types
  from `.xlsx` to also accept `[.pdf, .png, .jpeg]`
  (`ImportSheetView.swift:325`), and add **`VNDocumentCameraViewController`**
  (VisionKit) as a "Scan report" capture source plus `PHPickerViewController`
  for an existing photo. DocCamera is the default for "photograph my report"
  because its auto edge-detection/deskew materially improves OCR.
- **Text-PDF shortcut on-device:** if `PDFDocument.string` yields real text,
  send **that text** (no OCR) — highest fidelity, cheapest.
- **Upload:** reuse `BiomarkersImportService`'s multipart machinery
  (`BiomarkersImportService.swift`); add a document endpoint (below). What gets
  sent depends on the posture in §3.

### 2. Backend — a document import endpoint + staging

New endpoint, mirroring the `.xlsx` one's guards:

```
POST /biomarkers/import/document    (multipart: file=pdf|png|jpeg, or text=…)
```

- Same size cap (`max_upload_bytes`), magic-byte validation (per type), chunked
  read. PDFs get a page-count / uncompressed guard analogous to the ZIP-bomb
  check.
- The endpoint **does not write to `results` directly.** It runs extraction
  (§3), writes the full result to **`lab_imports`** as `pending_review`, and
  returns a structured candidate payload for the review UI.

### 3. Extraction posture — one switch, two paths

A server setting + per-user consent selects between:

- **Option A — on-device OCR (DEFAULT, private):** Apple Vision
  `VNRecognizeText` (`.accurate`, `recognitionLanguages = ["nb","en"]`) extracts
  text on the phone; **only text** reaches the backend, where Claude structures
  it into candidate rows. Same privacy posture as food labels. Cheapest, fully
  EU-safe, but loses 2-D table structure (column association is reconstructed by
  the LLM from line text).
- **Option B — vision model (consent-gated, best quality):** the **document
  image/PDF page** is sent to **Claude with vision**, which preserves layout and
  associates *analyte ↔ value ↔ unit ↔ reference-range* across columns —
  exactly where plain OCR struggles. Reuses the `anthropic` SDK (no new vendor).
  Gated behind **explicit per-user consent** because health-document pixels now
  leave the device; retention is minimised (see §6).

Both paths share the same **strict-JSON, never-invent, null-when-unsure** prompt
discipline as `label_parser.py`, low temperature, and a fixed output schema.

> Dedicated Document-AI vendors (AWS Textract / Google Document AI / Azure) lead
> on raw table accuracy but add a new data-processor + EU-residency review for
> marginal gain over a vision model we already integrate. **Deferred** unless
> benchmarking (§7) shows A/B are insufficient.

### 4. Database — never reject, quarantine instead

Unknown **biomarkers** are already fine: the catalog upserts on
`(user_id, name_no)` with free-form `unit` and no whitelist
(`001_biomarkers.sql`), so a new analyte from a PDF creates a row exactly as
`.xlsx` does. The real constraint gap is **out-of-model data** — qualitative
results ("Positive"), censored values (`<0.01`), text-valued analytes — which
today cannot be stored because `results.value` is `numeric NOT NULL`
(`001_biomarkers.sql:38`).

Two migrations:

**`0xx_lab_imports.sql`** — a staging/audit table (mirrors the `ocr_raw`
pattern):

```sql
create table public.lab_imports (
    id          uuid primary key default uuid_generate_v4(),
    user_id     uuid not null references auth.users(id) on delete cascade,
    source_kind text not null check (source_kind in ('pdf','image','xlsx')),
    posture     text not null check (posture in ('ocr_text','vision')),
    extracted   jsonb not null,            -- full model output: audit + recovery
    status      text not null default 'pending_review'
                check (status in ('pending_review','applied','discarded')),
    created_at  timestamptz not null default now()
);
```

**`0xx_results_value_text.sql`** — admit non-numeric results:

```sql
alter table public.results add column value_text text;
alter table public.results alter column value drop not null;
alter table public.results add constraint value_one_of
    check ((value is not null) <> (value_text is not null));  -- exactly one
```

Censored values (`<`, `>`) already map onto the existing
`ref_type in ('lt','gt')` machinery — no new column needed. Units that don't
normalise pass through as-is (column is already free-form) and are **flagged for
review**, never blocked. Anything still unmapped stays in
`lab_imports.extracted` for later recovery.

**Invariant:** *an import never fails and never silently drops data* — worst
case it lands in staging.

### 5. Review UX — human-in-the-loop before commit

Unlike `.xlsx` (a deterministic export we trust), PDF/photo extraction is
probabilistic and medical, so it **must not auto-write** to `results`. After
upload the user sees a **confirmation screen**: candidate rows (analyte, value,
unit, date, reference range) with **per-field confidence**, inline edit, and an
explicit Apply. Apply transitions the `lab_imports` row to `applied` and writes
the (now user-verified) panel + results through the existing upsert path;
Discard sets `discarded`. This is both a data-quality and a patient-safety gate.

### 6. Privacy, consent & residency

- Option A keeps the device-only-text posture; nothing new leaves the phone.
- Option B requires **opt-in consent** with plain-language copy ("your lab
  document image is sent to our processor to read it"), is **off by default**,
  and **minimises retention** — the document bytes are processed transiently and
  not stored once `lab_imports.extracted` is written (we keep the structured
  extraction + audit, not the raw image, unless the user opts to retain it).
- `lab_imports` is user-scoped (RLS, `on delete cascade`) and flows into the
  existing GDPR export/erasure via `select("*")` — add it to `USER_TABLES` /
  `DELETE_ORDER` per ADR-013's pattern.

### 7. Phasing (small PRs, house style)

- **Phase 1 — text-based PDF (Option A only).** PDFKit text-layer extraction →
  Claude structuring → `lab_imports` + review screen → apply. Highest fidelity,
  no new privacy surface, no vision spend. *Do this first.*
- **Phase 2 — image / scanned-PDF via on-device OCR (Option A).** Add
  `VNDocumentCameraViewController` + `PHPicker`, Vision OCR, rasterize image
  PDFs. Same backend path.
- **Phase 3 — `results.value_text` + qualitative results.** Widen the schema and
  the review UI to admit non-numeric answers.
- **Phase 4 — vision-model posture (Option B), consent-gated.** Offer the
  best-quality path for hard captures; benchmark against Phases 1–2 to confirm
  it's worth the privacy trade.

---

## Why we need it (summary of the case)

1. **Meet users where their data is.** Most labs hand out PDFs or paper, not a
   Fürst `.xlsx`. Today those users can only hand-key results.
2. **Reuse, don't reinvent.** The food-label pipeline already does
   capture→structure→store→audit; this generalises it.
3. **The schema is ready.** The open per-user catalog absorbs unknown markers
   for free; only the `numeric NOT NULL` value needs widening for qualitative
   data.
4. **Safety and honesty preserved.** Mandatory review + never-invent prompting +
   never-reject staging keep the app's contracts intact.

---

## Pros / Cons

**Pros**

- Unlocks the dominant real-world formats (PDF, photo) for lab data.
- Additive: `.xlsx`, manual entry, and the food flow are untouched.
- No new vendor (Vision + Anthropic already in the stack).
- "Never reject" staging means no user data is ever lost to a parse failure.
- Schema change is minimal and reversible (`value_text` + one staging table).

**Cons / trade-offs**

- **Probabilistic extraction** → requires a review step (more UX, deliberate).
- **Option B leaks document pixels** → consent + retention + EU care (mitigated:
  off by default, transient processing, Option A is the default).
- **More moving parts** (PDFKit, DocCamera, two postures) → phased to keep PRs
  small.
- **Qualitative data modelling** is open-ended → bounded by `value_text` now,
  everything else parked in `lab_imports.extracted`.

---

## Alternatives considered

| Option | Rejected because |
|--------|------------------|
| Keep `.xlsx` only | Excludes most real users (PDF/paper labs). |
| Auto-apply extractions (no review) | Unsafe for medical data; extraction is probabilistic. |
| Reject rows we can't model | Violates "never drop user data"; staging preserves them instead. |
| Stuff everything into JSON, no schema change | Loses queryability/charting of qualitative results; `value_text` is cheap and reversible. |
| Dedicated Document-AI vendor (Textract/GCP/Azure) first | New DPA + EU review for marginal gain over a vision model already integrated; deferred pending benchmark. |
| Send images by default (Option B as default) | Unnecessary privacy exposure; on-device OCR covers the common clean-text case. |

---

## Open questions

1. **Auto-apply threshold** — always require review (proposed), or allow
   one-tap apply above a confidence bar for clean text-PDFs?
2. **Vision retention** — discard document bytes immediately after extraction
   (proposed), or offer opt-in retention so users can re-review later?
3. **Norwegian-name canonicalisation** — extend the 34 `MarkerKey` keyword map
   (`DietProfiles.swift:8`) as PDFs surface new analyte spellings, or add a
   server-side synonym table?
4. **Multi-date PDFs** — some reports carry several draw dates in columns (like
   the `.xlsx`); confirm the extractor emits one panel per `tested_at`, reusing
   the `(user_id, tested_at)` upsert.
5. **Benchmark corpus** — assemble ~20 anonymised real reports (Fürst/Dr. Dropin
   PDF, photo, scan) to choose Option A vs B on field-level accuracy before
   Phase 4.
