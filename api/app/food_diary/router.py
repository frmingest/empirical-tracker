from __future__ import annotations

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.food_diary import openfoodfacts, repository

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


# ── Open Food Facts proxy ───────────────────────────────────────────────────────
# These two endpoints are a thin, normalising proxy in front of Open Food Facts.
# They require auth so the lookup can't be used as an open relay.


@router.get("/search")
async def search_foods(
    q: str = Query(min_length=1),
    _user_id: str = Depends(current_user_id),
) -> list[dict]:
    try:
        return await openfoodfacts.search_products(q)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail="Open Food Facts is unavailable"
        ) from exc


@router.get("/barcode/{barcode}")
async def lookup_barcode(
    barcode: str,
    _user_id: str = Depends(current_user_id),
) -> dict:
    try:
        product = await openfoodfacts.lookup_barcode(barcode)
    except httpx.HTTPError as exc:
        raise HTTPException(
            status_code=502, detail="Open Food Facts is unavailable"
        ) from exc
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


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


@router.delete("/{entry_id}")
async def delete_food_entry(
    entry_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_entry(user_id, entry_id)
    return {"deleted": entry_id}
