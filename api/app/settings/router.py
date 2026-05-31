from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator

from app.auth import current_user_id
from app.settings import repository

router = APIRouter(prefix="/settings", tags=["settings"])


class SettingsIn(BaseModel):
    diet: str = "all"
    custom_markers: list[str] = Field(default_factory=list)

    @field_validator("diet")
    @classmethod
    def _valid_diet(cls, v: str) -> str:
        if v not in repository.VALID_DIETS:
            raise ValueError(
                f"diet must be one of {sorted(repository.VALID_DIETS)}"
            )
        return v


@router.get("")
async def read_settings(user_id: str = Depends(current_user_id)) -> dict:
    return repository.get_settings(user_id)


@router.put("")
async def write_settings(
    body: SettingsIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.upsert_settings(user_id, body.diet, body.custom_markers)
