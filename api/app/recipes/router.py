from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from pydantic import BaseModel, field_validator

from app.auth import current_user_id
from app.rate_limit import rate_limit
from app.recipes import repository

router = APIRouter(prefix="/recipes", tags=["recipes"])


class RecipeIn(BaseModel):
    title: str
    category: str
    image_url: str | None = None
    serving_size: str | None = None
    calories_kcal: float | None = None
    protein_g: float | None = None
    fat_g: float | None = None
    carbs_g: float | None = None
    ingredients: list[str] = []
    instructions: list[str] = []
    fact: str | None = None
    is_public: bool = False
    is_premium: bool = False

    @field_validator("title", "category")
    @classmethod
    def _non_empty(cls, v: str) -> str:
        if not v.strip():
            raise ValueError("must not be empty")
        return v.strip()

    @field_validator("ingredients", "instructions")
    @classmethod
    def _clean_lines(cls, v: list[str]) -> list[str]:
        # Drop blank rows the form may submit; keep author order otherwise.
        return [line.strip() for line in v if line and line.strip()]


class FavoriteIn(BaseModel):
    favorite: bool


# ── Reads ────────────────────────────────────────────────────────────────────────


@router.get("")
async def list_recipes(
    category: str | None = Query(default=None),
    only_free: bool = Query(default=False),
    user_id: str = Depends(current_user_id),
) -> list[dict]:
    return repository.list_recipes(user_id, category, only_free)


@router.get("/categories")
async def list_categories(user_id: str = Depends(current_user_id)) -> list[str]:
    return repository.list_categories(user_id)


@router.get("/{recipe_id}")
async def get_recipe(
    recipe_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    recipe = repository.get_recipe(user_id, recipe_id)
    if recipe is None:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return recipe


# ── Writes ───────────────────────────────────────────────────────────────────────


@router.post("/import-pdf")
async def import_recipe_pdf(
    file: UploadFile = File(...),
    _user_id: str = Depends(rate_limit("import_recipe_pdf", expensive=True)),
) -> dict:
    """Accept a PDF uploaded by the user and return a `RecipeIn`-shaped preview (not persisted).

    The user saves any recipe page using their browser's Print → Save as PDF
    function. We extract the visible text with pypdf and send it to Claude Haiku
    for parsing. The caller (iOS) shows the result in the authoring form for the
    user to review and edit before saving via `POST /recipes`.
    """
    from app.recipes.pdf_parser import parse_recipe_pdf

    if file.content_type not in ("application/pdf", "application/octet-stream"):
        raise HTTPException(status_code=422, detail="Only PDF files are accepted")

    pdf_bytes = await file.read()
    if len(pdf_bytes) > 20 * 1024 * 1024:  # 20 MB guard
        raise HTTPException(status_code=413, detail="PDF too large (max 20 MB)")

    try:
        return parse_recipe_pdf(pdf_bytes)
    except ValueError as exc:
        if "not configured" in str(exc):
            raise HTTPException(status_code=503, detail="Recipe importer not available") from exc
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    except Exception as exc:
        raise HTTPException(status_code=502, detail="Could not import recipe from PDF") from exc


@router.post("", status_code=201)
async def create_recipe(
    body: RecipeIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.create_recipe(user_id, body.model_dump())


@router.put("/{recipe_id}")
async def update_recipe(
    recipe_id: str,
    body: RecipeIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    updated = repository.update_recipe(user_id, recipe_id, body.model_dump())
    if updated is None:
        raise HTTPException(status_code=404, detail="Recipe not found")
    return updated


@router.delete("/{recipe_id}")
async def delete_recipe(
    recipe_id: str,
    user_id: str = Depends(current_user_id),
) -> dict:
    repository.delete_recipe(user_id, recipe_id)
    return {"deleted": recipe_id}


# ── Favourites ─────────────────────────────────────────────────────────────────────


@router.put("/{recipe_id}/favorite")
async def set_favorite(
    recipe_id: str,
    body: FavoriteIn,
    user_id: str = Depends(current_user_id),
) -> dict:
    return repository.set_favorite(user_id, recipe_id, body.favorite)
