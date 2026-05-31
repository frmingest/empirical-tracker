from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.diet_events import repository

router = APIRouter(prefix="/diet-events", tags=["diet-events"])


class DietEventIn(BaseModel):
    label: str
    kind: str = "diet"
    started_on: str  # "YYYY-MM-DD"
    ended_on: str | None = None
    note: str | None = None

    @field_validator("label")
    @classmethod
    def _non_empty_label(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("label must not be empty")
        return v.strip()

    @field_validator("kind")
    @classmethod
    def _valid_kind(cls, v: str) -> str:
        if v not in repository.VALID_KINDS:
            raise ValueError(f"kind must be one of {sorted(repository.VALID_KINDS)}")
        return v


@router.get("")
async def list_diet_events(user_id: str = Depends(current_user_id)) -> list[dict]:
    return repository.list_events(user_id)


@router.post("", status_code=201)
async def create_diet_event(
    body: DietEventIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_event(
        user_id,
        body.label,
        body.kind,
        body.started_on,
        body.ended_on,
        body.note,
    )


@router.delete("/{event_id}")
async def delete_diet_event(
    event_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_event(user_id, event_id)
    return {"deleted": event_id}
