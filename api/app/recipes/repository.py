from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from app.db import get_service_supabase, get_supabase

# A recipe counts as "New!" for two weeks after it is created. Derived at read
# time (see `_decorate`) so a recipe ages out on its own — no background job.
NEW_WINDOW_DAYS = 14

_COLUMNS = (
    "id,user_id,title,category,image_url,serving_size,"
    "calories_kcal,protein_g,fat_g,carbs_g,ingredients,instructions,"
    "fact,is_public,is_premium,created_at"
)

# Anonymous donated catalogue (ADR-028). No user_id, no created_at, no image_url
# — only a coarse `donated_at` date and the factual recipe fields.
_CATALOGUE_COLUMNS = (
    "id,title,category,serving_size,"
    "calories_kcal,protein_g,fat_g,carbs_g,ingredients,instructions,"
    "fact,is_premium,donated_at"
)

# The factual fields copied into `recipe_catalogue` when a *public* recipe is
# deleted. `user_id`/`created_at` are dropped and `image_url` is never donated
# (it can't be guaranteed non-identifying — see ADR-028). Keep this list as the
# single source of truth: a new donated column must be added here too.
_DONATED_FIELDS = (
    "title",
    "category",
    "serving_size",
    "calories_kcal",
    "protein_g",
    "fat_g",
    "carbs_g",
    "ingredients",
    "instructions",
    "fact",
    "is_premium",
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


# ── Donated catalogue (ADR-028) ────────────────────────────────────────────────────


def _scrub_for_catalogue(row: dict) -> dict:
    """Keep only the factual recipe fields; drop everything identifying."""
    return {field: row.get(field) for field in _DONATED_FIELDS}


def donate_to_catalogue(service_db, row: dict) -> None:
    """Copy a public recipe's factual fields into the anonymous catalogue.

    Keeps only the factual recipe columns (`_DONATED_FIELDS`), dropping
    `user_id` / `created_at` / `image_url` so the result is anonymous, not merely
    pseudonymous (GDPR Recital 26). Recipes have no natural unique key, so this is
    a plain insert — the source row is hard-deleted immediately after, so the same
    recipe can't be re-donated and rows don't pile up.

    Runs on the **service-role** client — the one sanctioned service-role data
    path (ADR-026) — because `recipe_catalogue` is writable only by that role.
    """
    facts = _scrub_for_catalogue(row)
    facts["donated_at"] = date.today().isoformat()
    service_db.table("recipe_catalogue").insert(facts).execute()


def donate_public_recipes(service_db, user_id: str) -> int:
    """Donate every public recipe a user owns before account erasure.

    Called from the account-deletion path (which already runs on the service-role
    client). Private recipes are left untouched here — the caller's explicit
    `recipes` DELETE hard-erases all of them, public and private alike. Returns
    the number of rows donated.
    """
    resp = (
        service_db.table("recipes")
        .select("*")
        .eq("user_id", user_id)
        .eq("is_public", True)
        .execute()
    )
    rows = resp.data or []
    for row in rows:
        donate_to_catalogue(service_db, row)
    return len(rows)


def _catalogue_row_to_recipe(row: dict) -> dict:
    """Shape an anonymous catalogue row like a recipe row for the cards.

    Donated rows have no owner and cannot be favourited (favourites FK to
    `recipes`), and never show the "New!" badge — `donated_at` is a coarse date
    kept only for ordering, and surfacing it as "new" would leak deletion timing.
    """
    return {
        "id": row["id"],
        "user_id": None,
        "title": row["title"],
        "category": row["category"],
        "image_url": None,
        "serving_size": row.get("serving_size"),
        "calories_kcal": row.get("calories_kcal"),
        "protein_g": row.get("protein_g"),
        "fat_g": row.get("fat_g"),
        "carbs_g": row.get("carbs_g"),
        "ingredients": row.get("ingredients") or [],
        "instructions": row.get("instructions") or [],
        "fact": row.get("fact"),
        "is_public": True,
        "is_premium": row.get("is_premium", False),
        "created_at": row.get("donated_at"),
        "is_favorite": False,
        "is_new": False,
        "is_donated": True,
    }


def _list_catalogue(db, category: str | None, only_free: bool) -> list[dict]:
    """Donated catalogue rows visible to everyone, newest donation first."""
    query = db.table("recipe_catalogue").select(_CATALOGUE_COLUMNS)
    if category:
        query = query.eq("category", category)
    if only_free:
        query = query.eq("is_premium", False)
    resp = query.order("donated_at", desc=True).execute()
    return [_catalogue_row_to_recipe(row) for row in (resp.data or [])]


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
    # Own + public recipes first (newest authored wins), then the anonymous
    # donated catalogue (ADR-028).
    own = [_decorate(row, favorite_ids) for row in rows]
    return own + _list_catalogue(db, category, only_free)


def get_recipe(user_id: str, recipe_id: str) -> dict | None:
    """Return one recipe if the user may see it, else None.

    Falls back to the anonymous donated catalogue (ADR-028) so a card backed by
    a donated recipe still opens.
    """
    db = get_supabase()
    resp = (
        db.table("recipes")
        .select(_COLUMNS)
        .eq("id", recipe_id)
        .or_(f"user_id.eq.{user_id},is_public.eq.true")
        .execute()
    )
    rows = resp.data or []
    if rows:
        return _decorate(rows[0], _favorite_ids(db, user_id))

    donated = (
        db.table("recipe_catalogue")
        .select(_CATALOGUE_COLUMNS)
        .eq("id", recipe_id)
        .execute()
    )
    catalogue_rows = donated.data or []
    if catalogue_rows:
        return _catalogue_row_to_recipe(catalogue_rows[0])
    return None


def list_categories(user_id: str) -> list[str]:
    """Distinct categories present in the user's visible catalogue, sorted."""
    db = get_supabase()
    resp = (
        db.table("recipes")
        .select("category")
        .or_(f"user_id.eq.{user_id},is_public.eq.true")
        .execute()
    )
    donated = db.table("recipe_catalogue").select("category").execute()
    categories = {row["category"] for row in (resp.data or []) if row.get("category")}
    categories |= {row["category"] for row in (donated.data or []) if row.get("category")}
    return sorted(categories)


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
    """Delete one of the user's own recipes (no-op if it isn't theirs).

    If the recipe was shared into the catalogue (`is_public`), its factual
    fields are first donated to the anonymous `recipe_catalogue` so the catalogue
    value survives erasure de-identified (ADR-028); then the user-owned row is
    hard-deleted.
    """
    db = get_supabase()
    resp = (
        db.table("recipes")
        .select(_COLUMNS)
        .eq("id", recipe_id)
        .eq("user_id", user_id)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        return
    if rows[0].get("is_public"):
        donate_to_catalogue(get_service_supabase(), rows[0])
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
