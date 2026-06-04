"""Nutrition-label OCR parser backed by Claude Haiku.

Accepts raw OCR text from a nutrition-facts panel and returns a structured
``FoodItem``-shaped dict.  Fields that cannot be confidently extracted are
returned as ``None`` — numbers are never invented.

The caller is responsible for:
  - Running on-device OCR (VisionKit) and sending the concatenated text here.
  - Storing the result in ``custom_foods.ocr_raw`` alongside the parsed values.
  - Images are NOT sent to this function; only the text is processed.
"""

from __future__ import annotations

import json
import logging

import anthropic

from app.config import get_settings
from app.food_sources.base import SOURCE_CUSTOM, FoodItem, make_food_item

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"

_SYSTEM = """\
You are a nutrition data extractor. You receive raw OCR text from a nutrition-facts
panel (and possibly an ingredients list) photographed on a food product.

Your task is to extract the following fields and return them as a JSON object.
All nutrient values must be expressed PER 100 G of product — if the label shows
values per serving, convert them using the serving size.

Return ONLY valid JSON, no markdown fences, no commentary.

Required JSON shape:
{
  "food_name": <string or null>,
  "brand": <string or null>,
  "energy_kcal_100g": <number or null>,
  "carbs_100g": <number or null>,
  "protein_100g": <number or null>,
  "fat_100g": <number or null>,
  "saturated_fat_100g": <number or null>,
  "sodium_mg_100g": <number or null>,
  "serving_g": <number or null>,
  "ingredients": <string or null>
}

Rules:
- If a value is not present in the text, return null — never estimate or invent.
- Convert kJ to kcal using: kcal = kJ / 4.184.
- Convert sodium from "salt" using: sodium_mg = salt_g * 390.
- Serving size: if "per serving" values are given, convert to per-100g using the
  serving weight in grams.  If serving weight is not stated, return null for all
  per-100g fields that were only shown per-serving.
- Saturated fat may be labelled "saturates", "saturated fatty acids", or "mättade
  fettsyror".
- Sodium may be labelled "salt" (convert), "sodium", or "natrium".
- Strip trailing punctuation and normalise whitespace in strings.
"""


def parse_label(ocr_text: str) -> FoodItem:
    """Parse raw OCR text and return a FoodItem with per-100g nutrients.

    Raises ``ValueError`` if the Anthropic API key is not configured.
    Raises ``anthropic.APIError`` on upstream failures.
    """
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is not configured")

    # Do not log the OCR text, the model response, or the parsed fields: they are
    # user-submitted label content and must stay out of application logs
    # (ADR-026 F10 — no PII in logs). Log sizes/outcomes only.
    logger.info("label_parser: parsing OCR input (%d chars)", len(ocr_text))

    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)

    message = client.messages.create(
        model=_MODEL,
        max_tokens=512,
        system=_SYSTEM,
        messages=[{"role": "user", "content": ocr_text}],
    )

    raw_json = message.content[0].text.strip()

    # Strip markdown code fences if the model wraps the JSON despite instructions.
    if raw_json.startswith("```"):
        raw_json = raw_json.split("\n", 1)[-1]
        raw_json = raw_json.rsplit("```", 1)[0].strip()

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        logger.warning("label_parser: model returned non-JSON (%d chars)", len(raw_json))
        raise ValueError(f"Could not parse Claude response as JSON: {exc}") from exc

    logger.info("label_parser: parsed %d fields", len(parsed))

    return make_food_item(
        source=SOURCE_CUSTOM,
        code="",
        name=parsed.get("food_name") or "",
        brand=parsed.get("brand"),
        quantity=f"{parsed['serving_g']} g" if parsed.get("serving_g") else None,
        energy_kcal_100g=_to_float(parsed.get("energy_kcal_100g")),
        carbs_100g=_to_float(parsed.get("carbs_100g")),
        protein_100g=_to_float(parsed.get("protein_100g")),
        fat_100g=_to_float(parsed.get("fat_100g")),
        saturated_fat_100g=_to_float(parsed.get("saturated_fat_100g")),
        sodium_mg_100g=_to_float(parsed.get("sodium_mg_100g")),
    ), parsed  # also return the raw parsed dict so the router can persist it


def _to_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        f = float(value)  # type: ignore[arg-type]
        return f if f >= 0 else None  # negative nutrients are artefacts
    except (TypeError, ValueError):
        return None
