"""Recipe-PDF importer: extract text from a PDF and return a `RecipeIn`-shaped dict.

The user exports a recipe page using their browser's Print → Save as PDF function,
then uploads the PDF from their device. We extract the visible text with pypdf and
send it to Claude Haiku with the same recipe-extraction prompt used by the old
URL-import Claude fallback, returning a preview dict the iOS form can prefill.

Nothing is persisted here — the caller reviews and edits the result, then saves via
`POST /recipes` as normal.
"""

from __future__ import annotations

import io
import json
import logging

import anthropic
from pypdf import PdfReader

from app.config import get_settings

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"

_SYSTEM = """\
You are a recipe data extractor. You receive the visible text content of a recipe
(extracted from a PDF the user saved from a recipe website) and must extract the
recipe as a JSON object.

Return ONLY valid JSON, no markdown fences, no commentary.

Required JSON shape:
{
  "title": <string or null>,
  "category": <string or null>,
  "serving_size": <string or null>,
  "calories_kcal": <number or null>,
  "protein_g": <number or null>,
  "fat_g": <number or null>,
  "carbs_g": <number or null>,
  "ingredients": [<string>, ...],
  "instructions": [<string>, ...],
  "fact": <string or null>
}

Rules:
- "ingredients" is an ordered list of ingredient lines as written in the document
  (e.g. "8 oz pork belly, cubed").
- "instructions" is an ordered list of step descriptions, one per step.
- "category" should be a short course/meal label (e.g. "Breakfast", "Dinner",
  "Dessert") if one is evident, otherwise null.
- Nutrition values are PER SERVING. If the document gives a different basis (e.g.
  per 100g) or no nutrition info, return null for those fields — never estimate
  or invent numbers.
- "fact" is an optional one-sentence interesting note about the recipe (from the
  document's description or intro), or null.
- If the document does not appear to contain a recipe at all, return null for every
  field and an empty list for "ingredients" / "instructions".
"""

_MAX_CHARS = 12_000


def _to_float(value: object) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    digits = "".join(ch for ch in value if ch.isdigit() or ch in ".,").replace(",", ".")
    if not digits:
        return None
    try:
        return float(digits)
    except ValueError:
        return None


def extract_pdf_text(pdf_bytes: bytes) -> str:
    """Extract visible text from a PDF, capped at `_MAX_CHARS` characters."""
    reader = PdfReader(io.BytesIO(pdf_bytes))
    lines: list[str] = []
    for page in reader.pages:
        text = page.extract_text() or ""
        lines.extend(line.strip() for line in text.splitlines() if line.strip())
    return "\n".join(lines)[:_MAX_CHARS]


def parse_recipe_pdf(pdf_bytes: bytes) -> dict:
    """Extract text from `pdf_bytes` and use Claude Haiku to parse a recipe.

    Returns a `RecipeIn`-shaped dict (a preview, not persisted).
    Raises `ValueError` on an empty PDF, missing API key, or unparseable response.
    """
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is not configured")

    text = extract_pdf_text(pdf_bytes)
    if not text.strip():
        raise ValueError("Could not extract any text from the PDF")

    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)
    message = client.messages.create(
        model=_MODEL,
        max_tokens=2048,
        system=_SYSTEM,
        messages=[{"role": "user", "content": text}],
    )

    raw_json = message.content[0].text.strip()
    if raw_json.startswith("```"):
        raw_json = raw_json.split("\n", 1)[-1]
        raw_json = raw_json.rsplit("```", 1)[0].strip()

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        logger.warning("pdf_parser: failed to parse Claude response as JSON")
        raise ValueError(f"Could not parse Claude response as JSON: {exc}") from exc

    def _str(v: object) -> str | None:
        return v.strip() if isinstance(v, str) and v.strip() else None

    return {
        "title": _str(parsed.get("title")) or "",
        "category": _str(parsed.get("category")),
        "image_url": None,
        "serving_size": _str(parsed.get("serving_size")),
        "calories_kcal": _to_float(parsed.get("calories_kcal")),
        "protein_g": _to_float(parsed.get("protein_g")),
        "fat_g": _to_float(parsed.get("fat_g")),
        "carbs_g": _to_float(parsed.get("carbs_g")),
        "ingredients": [s for s in (parsed.get("ingredients") or []) if isinstance(s, str)],
        "instructions": [s for s in (parsed.get("instructions") or []) if isinstance(s, str)],
        "fact": _str(parsed.get("fact")),
    }
