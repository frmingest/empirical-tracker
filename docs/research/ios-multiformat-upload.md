# Research: Multi-format data/file upload (PDF + image, beyond `.xlsx`)

**Status:** Research / discovery (no decision made yet — precursor to an ADR)
**Author:** iOS
**Date:** 2026-06-08

## Goal

Today the only *file*-based ingestion path is the Norwegian lab `.xlsx` import.
Users increasingly receive lab results as **PDF reports** (from Fürst, Dr.
Dropin, Aleris, hospital portals) or as **photos/screenshots** of a printed
report. This note researches how to extend ingestion to those formats and what
it costs us in data-model, reliability, and technology terms.

Three questions were asked:

1. How do we accept image/PDF file uploads?
2. How do we handle DB constraints when an upload contains data we don't have a
   table/column for?
3. What technology gives the best PDF/image extraction quality/reliability?

---

## 1. Current state (what we already have)

We are not starting from zero — two ingestion pipelines already exist and the
patterns are reusable.

### 1a. `.xlsx` lab import (structured file → DB)

| Layer | Location |
| --- | --- |
| Picker (`UIDocumentPickerViewController`, `.xlsx` only) | `ios/EmpiricalTracker/Features/Import/ImportSheetView.swift:325` |
| Multipart upload + progress | `ios/Packages/Biomarkers/Sources/Biomarkers/BiomarkersImportService.swift` |
| Endpoint + safety checks | `api/app/biomarkers/router.py:87` (`POST /biomarkers/import`) |
| Parser (openpyxl, ref-range parsing) | `api/app/biomarkers/parser.py:77` |
| Upsert (biomarker catalog + panel + results) | `api/app/biomarkers/repository.py:11` |

Safety guards already in place (reuse these verbatim for new formats):
- 10 MiB upload cap — `config.py:30` (`max_upload_bytes`)
- ZIP-bomb / magic-byte validation — `biomarkers/router.py:96-105`
- Chunked read to bound memory — `biomarkers/router.py:25`

### 1b. Nutrition-label OCR (image → text → LLM → structured)

This is the **most important precedent** — it's already exactly the
"unstructured capture → structured data" pattern we want for lab reports, just
applied to food labels:

- **On-device OCR** with Apple Vision (`VNRecognizeTextRequest`, `.accurate`,
  `usesLanguageCorrection`) — `ios/EmpiricalTracker/Features/FoodDiary/NutritionLabelCaptureView.swift:151`
- **Only text leaves the device**, never the image — `label_parser.py:10`
- **Claude Haiku** (`claude-haiku-4-5-20251001`) extracts a strict JSON shape,
  with a "never invent numbers, return null" system prompt — `api/app/food_sources/label_parser.py:27`
- Raw model output persisted for audit (`custom_foods.ocr_raw`)
- OCR text capped at 20k chars before hitting the LLM — `config.py:32` (`max_ocr_chars`)

**Takeaway:** the food-label pipeline is a working blueprint. A lab-report
importer is the same shape (capture → OCR/vision → LLM-to-JSON → review → DB)
with a richer target schema and a mandatory human-review step.

---

## 2. Accepting image + PDF upload (the iOS side)

### Recommended capture surfaces

| Source | API | Notes |
| --- | --- | --- |
| Scan a paper report | **VisionKit `VNDocumentCameraViewController`** | Auto edge-detection, deskew, multi-page, glare reduction. Far better raw quality than `UIImagePickerController` (which the food-label flow currently uses). |
| Existing photo | `PHPickerViewController` | Privacy-friendly, no photo-library permission prompt. |
| PDF / file | `UIDocumentPickerViewController` extended to `[.pdf, .png, .jpeg]` | We already use this for `.xlsx` — just widen `contentTypes`. Add Files + share-sheet import. |

`VNDocumentCameraViewController` is the single biggest quality lever on the
capture side — it should be the default for "photograph my lab report."

### On-device text extraction (before anything leaves the phone)

- **Images:** `VNRecognizeTextRequest` — already wired up for food labels;
  reuse it. Add `recognitionLanguages = ["nb", "en"]` for Norwegian reports.
- **PDFs:** two cases —
  - *Text-based PDF* (most lab portals export these): pull the text layer
    directly with **PDFKit** (`PDFDocument.string` / per-page attributed text).
    No OCR needed, near-perfect fidelity, free.
  - *Scanned/image PDF*: rasterize each page (`PDFPage.thumbnail` / Core
    Graphics) and run Vision OCR per page.

Detecting which kind: if `PDFDocument.string` returns substantive text, it's a
text PDF; otherwise fall back to rasterize+OCR.

### Privacy decision required: text-only vs. send-the-image

The food-label flow deliberately sends **only OCR text** to the backend, never
the image. That's a privacy win but it caps quality, because Vision OCR throws
away the **2-D table structure** that lab reports depend on (analyte | value |
unit | reference range columns). Lab reports are far more layout-sensitive than
a food label.

We have a fork in the road (this is the key product/privacy decision for the
ADR):

- **Option A — text-only (status quo privacy posture):** Vision OCR on device,
  ship text to an LLM. Cheapest, most private, but layout/column association is
  lossy → more review burden, more mis-parses on multi-column reports.
- **Option B — send the image/PDF to a vision model:** dramatically better on
  tables and messy scans, but health-document pixels now leave the device.
  Requires explicit consent, EU data-residency care (we're Frankfurt/Supabase
  EU), and a clear retention policy.

See §4 for the quality evidence behind this trade-off.

---

## 3. DB constraints when the upload contains data we don't model

This is the subtle one. Two distinct sub-problems:

### 3a. Unknown biomarkers — *already handled gracefully*

The biomarker catalog is **per-user and open** — there is no global whitelist,
enum, or catalog FK to violate:

```sql
-- 001_biomarkers.sql
create table public.biomarkers (
    user_id  uuid not null references auth.users(id),
    name_no  text not null,
    unit     text,              -- free-form, NOT validated
    ref_type text check (ref_type in ('bounded','lt','gt','none')),
    unique (user_id, name_no)
);
```

So an unknown analyte from a PDF is **not a constraint violation** — it just
upserts a new `biomarkers` row on `(user_id, name_no)`, exactly as `.xlsx`
import does (`repository.py:11`, `on_conflict="user_id,name_no"`). The schema
was designed to absorb arbitrary markers.

The only place "unknown" matters is the **iOS canonical mapping**: 34 hardcoded
`MarkerKey`s with Norwegian keyword matching in
`ios/Packages/Biomarkers/Sources/Biomarkers/DietProfiles.swift:8`. A marker that
doesn't match a keyword is **still imported and charted** — it's simply excluded
from diet-focused views. No data is lost; it's a display-completeness issue, not
a storage one.

### 3b. Genuinely out-of-model data — the real gap

PDFs/photos can carry things the schema has **no column for**, e.g.:
- Qualitative results ("Positive", "Negative", "Not detected", "+++")
- Ranged/censored values (`<0.01`, `>1000`)
- Units we don't normalise, or analytes with text answers (e.g. blood type)
- Specimen metadata (fasting status, lab name, method) and free-text comments

Today `results.value` is `numeric NOT NULL` (`001_biomarkers.sql:38`), so a
qualitative result **cannot be stored at all** — it would be silently dropped or
fail insertion. This is the concrete constraint problem the task is pointing at.

**Recommended strategy — never reject, quarantine instead.** Borrow the
`ocr_raw` audit pattern already used for food labels and add a holding area so
nothing the user uploaded is thrown away:

1. **Staging table for raw extraction.** Persist the full extracted document as
   JSONB *before* mapping to `results`, with provenance:

   ```sql
   create table public.lab_imports (
       id            uuid primary key default uuid_generate_v4(),
       user_id       uuid not null references auth.users(id) on delete cascade,
       source_kind   text not null check (source_kind in ('pdf','image','xlsx')),
       extracted     jsonb not null,         -- full model output, audit trail
       status        text not null default 'pending_review'
                     check (status in ('pending_review','applied','discarded')),
       created_at    timestamptz not null default now()
   );
   ```

   This mirrors `custom_foods.ocr_raw` and means a parse we can't fully map is
   *preserved*, not lost — the user (or a later migration) can revisit it.

2. **Human-in-the-loop review before commit.** Extraction from
   photos/PDFs is probabilistic; unlike `.xlsx` it should **not** auto-write to
   `results`. Show a confirmation screen (value, unit, date, reference range,
   confidence) and let the user fix/approve. This is both a data-quality and a
   medical-safety requirement.

3. **Widen the model deliberately, only where justified.** For recurring
   out-of-model cases, make targeted, reversible schema changes rather than
   stuffing everything into JSON:
   - Add `results.value_text text` and relax `value` to nullable, with a CHECK
     that exactly one of `value` / `value_text` is present — captures
     qualitative results.
   - Already supported: censored ranges map cleanly onto the existing
     `ref_type in ('lt','gt')` machinery.
   - Keep an explicit `unit` normalisation map server-side; unrecognised units
     pass through as-is (column is already free-form) and get flagged for review
     rather than blocking the import.

4. **Anything still unmapped stays in `lab_imports.extracted`** with
   `status='pending_review'`. The invariant: **an upload never fails and never
   silently drops data** — worst case it lands in staging for later.

All schema changes follow the repo convention: numbered migration in
`api/supabase/migrations/`, run manually (per `CLAUDE.md`).

---

## 4. Extraction quality / reliability — what technology is best

Ranked for *lab-report* extraction (dense, multi-column, numeric, sometimes
Norwegian, sometimes a phone photo). Evidence is qualitative/industry-level —
we should benchmark on our own corpus (§5) before committing.

### Tier 0 — Text-based PDF: just read the text layer
If the PDF has a real text layer (most portal exports do), **PDFKit
`PDFDocument.string` is the highest-fidelity and cheapest option, full stop** —
no OCR error at all. Always try this first and only fall back to OCR when the
text layer is absent/garbage.

### Tier 1 — Vision LLM on the image/PDF (best for messy real-world capture)
Sending the actual pixels/PDF to a **multimodal model** (Claude with vision)
preserves 2-D layout, so it associates *analyte ↔ value ↔ unit ↔ range* across
columns — exactly where plain OCR falls down. We already depend on Anthropic
(`anthropic` SDK, `label_parser.py`), so this is the **lowest-friction
high-quality path**: same SDK, same "strict JSON, never invent, null when
unsure" prompt discipline, just with an image block added. Best for crumpled
photos, scans, and multi-column tables. Cost: per-image tokens + the privacy
trade-off in §2 (pixels leave device). Reliability control: low temperature,
strict JSON schema, mandatory user review.

### Tier 2 — Apple Vision on-device OCR (best privacy, free, offline)
`VNRecognizeText` `.accurate` is genuinely good on clean, high-contrast text and
costs nothing / never leaves the device. Weaknesses: it returns *lines*, not
*table structure*, so column association must be reconstructed downstream (an
LLM can do this but with less context than it'd have from the image). This is
the status-quo posture (food labels) and the right **default for Option A**.
Add `recognitionLanguages = ["nb","en"]`.

### Tier 3 — Dedicated cloud Document AI (best raw table accuracy, heaviest)
**AWS Textract**, **Google Document AI**, **Azure Document Intelligence** are
purpose-built for tables/forms and lead on pure structured-table accuracy. But:
new vendor + new data-processor agreement, EU-residency review (we're EU-only
today), extra cost, and they still need an LLM/rules pass to map to *our*
schema. Hard to justify when a vision LLM we already integrate gets us most of
the way.

### Recommended stack
```
PDF? ──has text layer?──► PDFKit text  ─┐
  │ no                                   ├─► [optional] LLM normalise ─► review ─► DB
  └─rasterize ─┐                         │
Image ─────────┴─► Apple Vision OCR ─────┘   (Option A: private, cheap)
                                  └────────► Claude vision on the image
                                              (Option B: best quality)
```

- **Always** prefer the PDF text layer when present (Tier 0).
- **Default** to on-device Vision OCR for privacy/cost (Tier 2), with Claude as
  the structuring/normalisation step — consistent with today's architecture.
- **Offer** the Claude-vision path (Tier 1) for hard captures, gated behind
  explicit consent (Option B), as a quality escape hatch.
- **Defer** dedicated Document-AI vendors (Tier 3) unless benchmarking shows the
  above is insufficient.

Reliability is not just model choice — it's the **confidence + mandatory review
+ raw-audit + never-reject-quarantine** loop in §3 around whatever extractor we
pick.

---

## 5. Suggested next steps

1. **Benchmark corpus:** collect ~20 real (anonymised) lab reports — Fürst PDF,
   Dr. Dropin PDF, a phone photo, a scan — and measure Tier 0/1/2 on
   field-level accuracy. Decide Option A vs B on evidence, not assumption.
2. **iOS spike:** widen `UIDocumentPickerViewController` content types and add
   `VNDocumentCameraViewController` capture; reuse `BiomarkersImportService`'s
   multipart upload.
3. **Backend spike:** `POST /biomarkers/import/document` accepting `pdf|image`,
   reusing the existing size/magic-byte guards; persist to a new `lab_imports`
   staging table.
4. **Review UX:** confirmation screen before writing to `results` (medical-
   safety gate).
5. **Schema:** migration for `lab_imports` + `results.value_text`; write the ADR
   once Option A/B is chosen.

## Open questions for product/clinical
- Do we allow health-document **images** to leave the device (Option B)? Consent
  + retention + EU residency implications.
- Auto-apply high-confidence extractions, or **always** require review?
- How much non-numeric/qualitative data do we commit to modelling now vs. park
  in `lab_imports.extracted`?
