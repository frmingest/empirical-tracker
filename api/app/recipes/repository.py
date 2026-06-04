from __future__ import annotations

from datetime import UTC, datetime, timedelta

from app.db import get_supabase

# A recipe counts as "New!" for two weeks after it is created. Derived at read
# time (see `_decorate`) so a recipe ages out on its own — no background job.
NEW_WINDOW_DAYS = 14

_COLUMNS = (
    "id,user_id,title,category,image_url,serving_size,"
    "calories_kcal,protein_g,fat_g,carbs_g,ingredients,instructions,"
    "fact,is_public,is_premium,created_at"
)


# ── Reads ────────────────────────────────────────────────────────────────────────


def _favorite_ids(db, user_id: str) -> set[str]:
    """The set of recipe ids the user has starred."""
    resp = (
        db.table("recipe_favorites")
        .select("recipe_id")
        .eq("user_id", user_id)
        .execute()
    )
    return {row["recipe_id"] for row in (resp.data or [])}


def _is_new(created_at: str | None) -> bool:
    """True when `created_at` (ISO string) is within the New! window."""
    if not created_at:
        return False
    try:
        created = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
    except ValueError:
        return False
    if created.tzinfo is None:
        created = created.replace(tzinfo=UTC)
    return created >= datetime.now(UTC) - timedelta(days=NEW_WINDOW_DAYS)


def _decorate(row: dict, favorite_ids: set[str]) -> dict:
    """Attach derived `is_favorite` / `is_new` flags to a recipe row."""
    row["is_favorite"] = row["id"] in favorite_ids
    row["is_new"] = _is_new(row.get("created_at"))
    return row


def list_recipes(
    user_id: str,
    category: str | None = None,
    only_free: bool = False,
) -> list[dict]:
    """Return recipes visible to the user (their own + the public catalogue).

    Optionally narrowed to one `category` or to free (non-premium) recipes. Each
    row carries derived `is_favorite` and `is_new` flags for the cards.
    """
    db = get_supabase()
    query = (
        db.table("recipes")
        .select(_COLUMNS)
        # RLS already enforces "own OR public"; this OR mirrors it for the
        # service-role client, which bypasses RLS.
        .or_(f"user_id.eq.{user_id},is_public.eq.true")
    )
    if category:
        query = query.eq("category", category)
    if only_free:
        query = query.eq("is_premium", False)
    resp = query.order("created_at", desc=True).execute()
    rows = resp.data or []
    favorite_ids = _favorite_ids(db, user_id)
    return [_decorate(row, favorite_ids) for row in rows]


def get_recipe(user_id: str, recipe_id: str) -> dict | None:
    """Return one recipe if the user may see it, else None."""
    db = get_supabase()
    resp = (
        db.table("recipes")
        .select(_COLUMNS)
        .eq("id", recipe_id)
        .or_(f"user_id.eq.{user_id},is_public.eq.true")
        .execute()
    )
    rows = resp.data or []
    if not rows:
        return None
    return _decorate(rows[0], _favorite_ids(db, user_id))


def list_categories(user_id: str) -> list[str]:
    """Distinct categories present in the user's visible catalogue, sorted."""
    db = get_supabase()
    resp = (
        db.table("recipes")
        .select("category")
        .or_(f"user_id.eq.{user_id},is_public.eq.true")
        .execute()
    )
    return sorted({row["category"] for row in (resp.data or []) if row.get("category")})


# ── Writes ───────────────────────────────────────────────────────────────────────


def create_recipe(user_id: str, recipe: dict) -> dict:
    """Insert a recipe authored by the user and return the stored row."""
    db = get_supabase()
    row = {
        "user_id": user_id,
        "title": recipe["title"],
        "category": recipe["category"],
        "image_url": recipe.get("image_url"),
        "serving_size": recipe.get("serving_size"),
        "calories_kcal": recipe.get("calories_kcal"),
        "protein_g": recipe.get("protein_g"),
        "fat_g": recipe.get("fat_g"),
        "carbs_g": recipe.get("carbs_g"),
        "ingredients": recipe.get("ingredients", []),
        "instructions": recipe.get("instructions", []),
        "fact": recipe.get("fact"),
        "is_public": recipe.get("is_public", False),
        "is_premium": recipe.get("is_premium", False),
    }
    resp = db.table("recipes").insert(row).execute()
    if not resp.data:
        return {}
    return _decorate(resp.data[0], _favorite_ids(db, user_id))


def update_recipe(user_id: str, recipe_id: str, recipe: dict) -> dict | None:
    """Update one of the user's own recipes; return the row or None if not theirs."""
    db = get_supabase()
    fields = {
        "title": recipe["title"],
        "category": recipe["category"],
        "image_url": recipe.get("image_url"),
        "serving_size": recipe.get("serving_size"),
        "calories_kcal": recipe.get("calories_kcal"),
        "protein_g": recipe.get("protein_g"),
        "fat_g": recipe.get("fat_g"),
        "carbs_g": recipe.get("carbs_g"),
        "ingredients": recipe.get("ingredients", []),
        "instructions": recipe.get("instructions", []),
        "fact": recipe.get("fact"),
        "is_public": recipe.get("is_public", False),
        "is_premium": recipe.get("is_premium", False),
    }
    resp = (
        db.table("recipes")
        .update(fields)
        .eq("id", recipe_id)
        .eq("user_id", user_id)
        .execute()
    )
    if not resp.data:
        return None
    return _decorate(resp.data[0], _favorite_ids(db, user_id))


def delete_recipe(user_id: str, recipe_id: str) -> None:
    """Delete one of the user's own recipes (no-op if it isn't theirs)."""
    db = get_supabase()
    (
        db.table("recipes")
        .delete()
        .eq("id", recipe_id)
        .eq("user_id", user_id)
        .execute()
    )


# ── Favourites ─────────────────────────────────────────────────────────────────────


def set_favorite(user_id: str, recipe_id: str, favorite: bool) -> dict:
    """Star (upsert) or un-star (delete) a recipe for the user."""
    db = get_supabase()
    if favorite:
        (
            db.table("recipe_favorites")
            .upsert(
                {"user_id": user_id, "recipe_id": recipe_id},
                on_conflict="user_id,recipe_id",
            )
            .execute()
        )
    else:
        (
            db.table("recipe_favorites")
            .delete()
            .eq("user_id", user_id)
            .eq("recipe_id", recipe_id)
            .execute()
        )
    return {"recipe_id": recipe_id, "is_favorite": favorite}
