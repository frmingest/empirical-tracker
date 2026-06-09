from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator, model_validator

from app.auth import current_user_id
from app.activity_metrics import repository

router = APIRouter(prefix="/activity-metrics", tags=["activity-metrics"])


class ActivityMetricOut(BaseModel):
    """Response model — coerces Postgres `numeric` to float so the iOS decoder
    always receives a JSON number, never a quoted string."""

    id: str
    measured_on: str
    steps: int | None = None
    active_energy_kcal: float | None = None
    exercise_minutes: int | None = None
    source: str
    created_at: str


class ActivityMetricIn(BaseModel):
    measured_on: str  # "YYYY-MM-DD"
    steps: int | None = None
    active_energy_kcal: float | None = None
    exercise_minutes: int | None = None
    source: str = "healthkit"

    @field_validator("source")
    @classmethod
    def _valid_source(cls, v: str) -> str:
        if v not in {"healthkit", "manual"}:
            raise ValueError("source must be healthkit or manual")
        return v

    @field_validator("steps", "exercise_minutes")
    @classmethod
    def _non_negative_int(cls, v: int | None) -> int | None:
        if v is not None and v < 0:
            raise ValueError("must be >= 0")
        return v

    @field_validator("active_energy_kcal")
    @classmethod
    def _non_negative_float(cls, v: float | None) -> float | None:
        if v is not None and v < 0:
            raise ValueError("must be >= 0")
        return v

    @model_validator(mode="after")
    def _at_least_one(self) -> ActivityMetricIn:
        if self.steps is None and self.active_energy_kcal is None and self.exercise_minutes is None:
            raise ValueError("at least one activity metric is required")
        return self


@router.get("", response_model=list[ActivityMetricOut])
async def list_activity_metrics(user_id: str = Depends(current_user_id)) -> list[dict]:
    return repository.list_metrics(user_id)


@router.post("/batch", status_code=201)
async def upsert_activity_metrics_batch(
    body: list[ActivityMetricIn],
    user_id: str = Depends(current_user_id),
) -> list[dict]:
    if not body:
        return []
    if len(body) > 500:
        raise HTTPException(status_code=422, detail="Batch size cannot exceed 500")
    return repository.upsert_metrics_batch(user_id, [m.model_dump() for m in body])


@router.delete("/by-source/{source}")
async def delete_activity_metrics_by_source(
    source: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    if source not in {"healthkit", "manual"}:
        raise HTTPException(status_code=400, detail="Invalid source")
    count = repository.delete_metrics_by_source(user_id, source)
    return {"deleted_count": count, "source": source}
