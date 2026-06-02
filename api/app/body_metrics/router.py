from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, field_validator, model_validator

from app.auth import current_user_id
from app.body_metrics import repository

router = APIRouter(prefix="/body-metrics", tags=["body-metrics"])


class BodyMetricIn(BaseModel):
    measured_on: str  # "YYYY-MM-DD"
    weight_kg: float | None = None
    waist_cm: float | None = None
    systolic: int | None = None
    diastolic: int | None = None
    note: str | None = None
    source: str = "manual"

    @field_validator("source")
    @classmethod
    def _valid_source(cls, v: str) -> str:
        if v not in {"manual", "healthkit", "withings"}:
            raise ValueError("source must be manual, healthkit, or withings")
        return v

    @field_validator("weight_kg", "waist_cm")
    @classmethod
    def _positive(cls, v: float | None) -> float | None:
        if v is not None and v <= 0:
            raise ValueError("must be greater than 0")
        return v

    @model_validator(mode="after")
    def _coherent_measurement(self) -> "BodyMetricIn":
        # Blood pressure is a pair: both halves or neither.
        if (self.systolic is None) != (self.diastolic is None):
            raise ValueError("systolic and diastolic must be provided together")
        # Never store an empty measurement.
        if (
            self.weight_kg is None
            and self.waist_cm is None
            and self.systolic is None
        ):
            raise ValueError("at least one metric (weight, waist, or blood pressure) is required")
        return self


@router.get("")
async def list_body_metrics(user_id: str = Depends(current_user_id)) -> list[dict]:
    return repository.list_metrics(user_id)


@router.post("", status_code=201)
async def create_body_metric(
    body: BodyMetricIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_metric(user_id, body.model_dump())


@router.delete("/{metric_id}")
async def delete_body_metric(
    metric_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_metric(user_id, metric_id)
    return {"deleted": metric_id}
