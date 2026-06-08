"""Lab-report text parser backed by Claude (ADR-032 Phase 1).

Accepts the raw text of a lab report — extracted on-device from a PDF's text
layer (PDFKit) or via Vision OCR — and returns a structured set of *candidate*
panels and results for the user to review before anything is written to the
biomarker store.

Design mirrors ``app/food_sources/label_parser.py``:
  - The model is told to return strict JSON and to **never invent a value**;
    fields it cannot read are returned as ``null``.
  - The full parsed dict is persisted to ``lab_imports.extracted`` for audit and
    recovery, so nothing the extractor saw is ever silently dropped.
  - Images/PDF bytes are NOT sent here in Phase 1 — only the extracted text.
"""

from __future__ import annotations

import json
import logging

import anthropic

from app.config import get_settings

logger = logging.getLogger(__name__)

# Haiku matches the food-label parser for cost/latency parity. Lab reports are
# denser than a nutrition panel, so this is the obvious knob to turn up (Sonnet)
# if review-time accuracy proves insufficient on the benchmark corpus (ADR-032).
_MODEL = "claude-haiku-4-5-20251001"

_SYSTEM = """\
You extract structured blood-test data from the raw text of a lab report
(often Norwegian — e.g. Fürst, Dr. Dropin, Aleris — sometimes English).

Return ONLY valid JSON, no markdown fences, no commentary.

Required JSON shape:
{
  "panels": [
    {
      "tested_at": <"YYYY-MM-DD" or null>,
      "results": [
        {
          "name_no": <string>,            // analyte name exactly as printed
          "value": <number or null>,      // numeric result, decimal point
          "value_text": <string or null>, // qualitative result e.g. "Positiv"
          "unit": <string or null>,       // e.g. "mmol/L", "g/L"
          "ref_range_raw": <string or null> // e.g. "4.5 - 5.8", "< 5", "> 1.0"
        }
      ]
    }
  ]
}

Rules:
- NEVER invent or estimate a number. If a value is not clearly printed, use null.
- Group results by their draw date. If a report lists several dates as columns,
  emit one panel object per date with that column's values.
- If no date is printed, use null for tested_at (the user will set it on review).
- Normalise Norwegian decimal commas to a decimal point ("5,8" -> 5.8).
- A result is EITHER numeric (value) OR qualitative (value_text), never both.
  "Positiv"/"Negativ"/"Påvist"/"Ikke påvist" go in value_text with value null.
- Keep the reference range as the raw printed string in ref_range_raw; do not
  reinterpret it.
- Preserve the analyte name verbatim in name_no (do not translate or rename).
- Ignore non-result lines (addresses, page numbers, comments, signatures).
"""


def parse_lab_text(text: str) -> dict:
    """Parse raw lab-report text into a candidate ``{"panels": [...]}`` dict.

    Raises ``ValueError`` if the Anthropic API key is not configured or the model
    response cannot be parsed as JSON. Raises ``anthropic.APIError`` upstream.
    """
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is not configured")

    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    message = client.messages.create(
        model=_MODEL,
        max_tokens=4096,
        system=_SYSTEM,
        messages=[{"role": "user", "content": text}],
    )

    raw_json = message.content[0].text.strip()

    # Strip markdown code fences if the model wraps the JSON despite instructions.
    if raw_json.startswith("```"):
        raw_json = raw_json.split("\n", 1)[-1]
        raw_json = raw_json.rsplit("```", 1)[0].strip()

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        logger.warning("lab_parser: failed to parse Claude response as JSON")
        raise ValueError(f"Could not parse Claude response as JSON: {exc}") from exc

    panels = parsed.get("panels")
    if not isinstance(panels, list):
        raise ValueError("Model response did not contain a 'panels' array")

    return {"panels": [_clean_panel(p) for p in panels if isinstance(p, dict)]}


def _clean_panel(panel: dict) -> dict:
    """Coerce one panel into the candidate shape, dropping unusable rows."""
    tested_at = panel.get("tested_at")
    results = panel.get("results")
    cleaned: list[dict] = []
    if isinstance(results, list):
        for r in results:
            if not isinstance(r, dict):
                continue
            name = _clean_str(r.get("name_no"))
            if not name:
                continue  # a result with no analyte name is unusable
            cleaned.append(
                {
                    "name_no": name,
                    "value": _to_float(r.get("value")),
                    "value_text": _clean_str(r.get("value_text")),
                    "unit": _clean_str(r.get("unit")),
                    "ref_range_raw": _clean_str(r.get("ref_range_raw")),
                }
            )
    return {
        "tested_at": _clean_str(tested_at),
        "results": cleaned,
    }


def _clean_str(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    return stripped or None


def _to_float(value: object) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, int | float):
        return float(value)
    if isinstance(value, str):
        s = value.strip().replace(",", ".")
        try:
            return float(s)
        except ValueError:
            return None
    return None
