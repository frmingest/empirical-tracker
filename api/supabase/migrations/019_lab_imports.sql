-- ADR-032 Phase 1: multi-format lab import — staging table for PDF/image documents.
--
-- The .xlsx import (001) is a deterministic export we trust enough to write
-- straight into `results`. PDF/photo extraction is *probabilistic* and medical,
-- so it must NOT auto-write. Instead, every document import lands here first as a
-- candidate the user reviews and explicitly applies.
--
-- This also gives us the "never reject, quarantine instead" guarantee: anything
-- the extractor produces — including analytes/units/values we can't map onto the
-- biomarker schema — is preserved verbatim in `extracted` (jsonb) rather than
-- being silently dropped. Mirrors the `custom_foods.ocr_raw` audit pattern.
--
-- RLS keeps every row strictly self-scoped, like the rest of the schema.

create table public.lab_imports (
    id          uuid        primary key default uuid_generate_v4(),
    user_id     uuid        not null references auth.users(id) on delete cascade,
    -- What kind of document this came from. 'text' = on-device-extracted text
    -- (Phase 1: PDFKit text layer / Vision OCR). 'pdf'/'image' reserved for the
    -- consent-gated vision posture (ADR-032 Phase 4).
    source_kind text        not null default 'text'
                            check (source_kind in ('text', 'pdf', 'image')),
    -- How the candidate was produced — 'ocr_text' (on-device, default) or
    -- 'vision' (document sent to a vision model). Audit + future analytics.
    posture     text        not null default 'ocr_text'
                            check (posture in ('ocr_text', 'vision')),
    -- Full structured model output: the candidate panels/results plus anything
    -- the extractor saw but we couldn't map. Never discarded.
    extracted   jsonb       not null,
    -- Lifecycle: pending_review → applied (written to results) | discarded.
    status      text        not null default 'pending_review'
                            check (status in ('pending_review', 'applied', 'discarded')),
    created_at  timestamptz not null default now(),
    applied_at  timestamptz
);

create index on public.lab_imports (user_id, status, created_at desc);

-- ── Row-Level Security ────────────────────────────────────────────────────────
alter table public.lab_imports enable row level security;

create policy "users_own_lab_imports" on public.lab_imports
    for all using (auth.uid() = user_id);
