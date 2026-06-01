from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.meal_plans import repository

router = APIRouter(prefix="/meal-plans", tags=["meal-plans"])


class MealPlanIn(BaseModel):
    name: str
    description: str | None = None

    @field_validator("name")
    @classmethod
    def _non_empty_name(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("name must not be empty")
        return v.strip()


class PlannedMealIn(BaseModel):
    scheduled_on: str  # "YYYY-MM-DD"
    meal: str = "other"
    food_name: str
    plan_id: str | None = None
    brand: str | None = None
    barcode: str | None = None
    quantity_g: float | None = None
    energy_kcal: float | None = None
    carbs_g: float | None = None
    protein_g: float | None = None
    fat_g: float | None = None
    sodium_mg: float | None = None
    saturated_fat_g: float | None = None
    note: str | None = None
    done: bool = False

    @field_validator("food_name")
    @classmethod
    def _non_empty_food(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("food_name must not be empty")
        return v.strip()

    @field_validator("meal")
    @classmethod
    def _valid_meal(cls, v: str) -> str:
        if v not in repository.VALID_MEALS:
            raise ValueError(f"meal must be one of {sorted(repository.VALID_MEALS)}")
        return v


class PlannedMealPatch(BaseModel):
    done: bool


# ── Named plans ─────────────────────────────────────────────────────────────────


@router.get("")
async def list_meal_plans(user_id: str = Depends(current_user_id)) -> list[dict]:
    return repository.list_plans(user_id)


@router.post("", status_code=201)
async def create_meal_plan(
    body: MealPlanIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_plan(user_id, body.name, body.description)


@router.delete("/{plan_id}")
async def delete_meal_plan(
    plan_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_plan(user_id, plan_id)
    return {"deleted": plan_id}


# ── Scheduled meals (the calendar) ──────────────────────────────────────────────


@router.get("/calendar")
async def list_calendar(
    start: str | None = Query(default=None),
    end: str | None = Query(default=None),
    user_id: str = Depends(current_user_id),
) -> list[dict]:
    return repository.list_planned_meals(user_id, start, end)


@router.post("/calendar", status_code=201)
async def create_calendar_meal(
    body: PlannedMealIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_planned_meal(user_id, body.model_dump())


@router.patch("/calendar/{meal_id}")
async def update_calendar_meal(
    meal_id: str,
    body: PlannedMealPatch,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.set_planned_meal_done(user_id, meal_id, body.done)


@router.delete("/calendar/{meal_id}")
async def delete_calendar_meal(
    meal_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_planned_meal(user_id, meal_id)
    return {"deleted": meal_id}
