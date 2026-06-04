from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.config import get_settings
from app.food_diary import repository
from app.food_sources import custom as custom_source
from app.food_sources import openfoodfacts, registry
from app.food_sources.base import VALID_SOURCES
from app.rate_limit import rate_limit

router = APIRouter(prefix="/food-diary", tags=["food-diary"])


class FoodEntryIn(BaseModel):
    logged_on: str  # "YYYY-MM-DD"
    meal: str = "other"
    food_name: str
    brand: str | None = None
    barcode: str | None = None
    quantity_g: float | None = None
    energy_kcal: float | None = None
    carbs_g: float | None = None
    protein_g: float | None = None
    fat_g: float | None = None
    sodium_mg: float | None = None
    saturated_fat_g: float | None = None
    source: str | None = None
    note: str | None = None

    @field_validator("food_name")
    @classmethod
    def _non_empty_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("food_name must not be empty")
        return v.strip()

    @field_validator("source")
    @classmethod
    def _valid_source(cls, v: str | None) -> str | None:
        if v is not None and v not in VALID_SOURCES:
            raise ValueError(f"source must be one of {sorted(VALID_SOURCES)}")
        return v

    @field_validator("meal")
    @classmethod
    def _valid_meal(cls, v: str) -> str:
        if v not in repository.VALID_MEALS:
            raise ValueError(f"meal must be one of {sorted(repository.VALID_MEALS)}")
        return v


class FoodEntryUpdateIn(BaseModel):
    """PUT body — same fields as FoodEntryIn except logged_on (date cannot change)."""
    meal: str = "other"
    food_name: str
    brand: str | None = None
    quantity_g: float | None = None
    energy_kcal: float | None = None
    carbs_g: float | None = None
    protein_g: float | None = None
    fat_g: float | None = None
    sodium_mg: float | None = None
    saturated_fat_g: float | None = None
    note: str | None = None

    @field_validator("food_name")
    @classmethod
    def _non_empty_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("food_name must not be empty")
        return v.strip()

    @field_validator("meal")
    @classmethod
    def _valid_meal(cls, v: str) -> str:
        if v not in repository.VALID_MEALS:
            raise ValueError(f"meal must be one of {sorted(repository.VALID_MEALS)}")
        return v


class CustomFoodIn(BaseModel):
    food_name: str
    brand: str | None = None
    barcode: str | None = None
    energy_kcal: float | None = None
    carbs_g: float | None = None
    protein_g: float | None = None
    fat_g: float | None = None
    saturated_fat_g: float | None = None
    sodium_mg: float | None = None
    serving_g: float | None = None
    ingredients: str | None = None
    ocr_raw: dict | None = None

    @field_validator("food_name")
    @classmethod
    def _non_empty_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("food_name must not be empty")
        return v.strip()


class ParseLabelIn(BaseModel):
    ocr_text: str

    @field_validator("ocr_text")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("ocr_text must not be empty")
        # Cap the text shipped to the LLM so a single request cannot amplify
        # token spend or be used as a prompt-injection delivery vehicle at
        # scale (ADR-026 F4).
        max_chars = get_settings().max_ocr_chars
        if len(v) > max_chars:
            raise ValueError(f"ocr_text must be at most {max_chars} characters")
        return v


# ── Food-source proxy ───────────────────────────────────────────────────────────


@router.get("/search")
async def search_foods(
    q: str = Query(min_length=1),
    source: str = Query(default=registry.SOURCE_ALL),
    user_id: str = Depends(rate_limit("food_search", expensive=True)),
) -> list[dict]:
    if source not in registry.SELECTABLE_SOURCES:
        raise HTTPException(
            status_code=422,
            detail=f"source must be one of {sorted(registry.SELECTABLE_SOURCES)}",
        )
    try:
        return await registry.search(q, source, user_id=user_id)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail="The selected food source is unavailable"
        ) from exc


@router.get("/barcode/{barcode}")
async def lookup_barcode(
    barcode: str,
    user_id: str = Depends(rate_limit("food_barcode", expensive=True)),
) -> dict:
    # User's own custom foods take priority over Open Food Facts.
    custom_hit = await custom_source.lookup_barcode_with_user(barcode, user_id)
    if custom_hit is not None:
        return custom_hit

    try:
        product = await openfoodfacts.lookup_barcode(barcode)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail="Open Food Facts is unavailable"
        ) from exc
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


# ── Parse label (OCR → structured nutrients via Claude Haiku) ──────────────────


@router.post("/parse-label")
async def parse_label(
    body: ParseLabelIn,
    _user_id: str = Depends(rate_limit("parse_label", expensive=True)),
) -> dict:
    """Convert raw nutrition-label OCR text to per-100g structured nutrients.

    The caller (iOS) runs on-device VisionKit OCR and sends the concatenated
    text here. Claude Haiku extracts the structured fields. Numbers that cannot
    be confidently extracted are returned as ``null`` — never invented.
    """
    from app.food_sources.label_parser import parse_label as _parse

    try:
        food_item, ocr_raw = _parse(body.ocr_text)
    except ValueError as exc:
        if "not configured" in str(exc):
            raise HTTPException(status_code=503, detail="Label parser not available") from exc
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Label parsing failed") from exc

    import logging as _logging
    _logging.getLogger(__name__).info("parse-label result: %s", food_item)
    return {**food_item, "ocr_raw": ocr_raw}


# ── Custom food catalogue CRUD ─────────────────────────────────────────────────


@router.post("/custom", status_code=201)
async def create_custom_food(
    body: CustomFoodIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return custom_source.create_custom_food(user_id, body.model_dump())


@router.put("/custom/{food_id}")
async def update_custom_food(
    food_id: str,
    body: CustomFoodIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    result = custom_source.update_custom_food(user_id, food_id, body.model_dump(exclude_none=True))
    if not result:
        raise HTTPException(status_code=404, detail="Custom food not found")
    return result


@router.delete("/custom/{food_id}")
async def delete_custom_food(
    food_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    custom_source.delete_custom_food(user_id, food_id)
    return {"deleted": food_id}


# ── Diary CRUD ────────────────────────────────────────────────────────────────


@router.get("")
async def list_food_entries(
    date: str | None = Query(default=None),
    user_id: str = Depends(current_user_id),
) -> list[dict]:
    return repository.list_entries(user_id, date)


@router.post("", status_code=201)
async def create_food_entry(
    body: FoodEntryIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_entry(user_id, body.model_dump())


@router.put("/{entry_id}")
async def update_food_entry(
    entry_id: str,
    body: FoodEntryUpdateIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.update_entry(user_id, entry_id, body.model_dump())


@router.delete("/{entry_id}")
async def delete_food_entry(
    entry_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_entry(user_id, entry_id)
    return {"deleted": entry_id}
