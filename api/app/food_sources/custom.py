"""User-contributed food catalogue (``custom_foods`` table).

Provides search and barcode lookup backed by the user's own additions plus any
items other users have made public.  Unlike the read-only external sources this
module also owns the create/update/delete path so the router stays thin.
"""

from __future__ import annotations

from datetime import date

from app.db import get_service_supabase, get_supabase
from app.food_sources.base import SOURCE_CUSTOM, FoodItem, make_food_item

# The factual product fields donated to the anonymous ``food_catalogue`` on
# delete (ADR-027). Deliberately excludes the identifying / unbounded columns —
# ``user_id``, ``created_at`` and ``ocr_raw`` — which are never donated.
_CATALOGUE_FIELDS = (
    "food_name",
    "brand",
    "barcode",
    "energy_kcal",
    "carbs_g",
    "protein_g",
    "fat_g",
    "saturated_fat_g",
    "sodium_mg",
    "serving_g",
    "ingredients",
)

_COLUMNS = (
    "id,food_name,brand,barcode,"
    "energy_kcal,carbs_g,protein_g,fat_g,saturated_fat_g,sodium_mg,serving_g"
)


def _row_to_food_item(row: dict) -> FoodItem:
    return make_food_item(
        source=SOURCE_CUSTOM,
        code=row["id"],
        name=row["food_name"],
        brand=row.get("brand"),
        quantity=f"{row['serving_g']} g" if row.get("serving_g") else None,
        energy_kcal_100g=_to_float(row.get("energy_kcal")),
        carbs_100g=_to_float(row.get("carbs_g")),
        protein_100g=_to_float(row.get("protein_g")),
        fat_100g=_to_float(row.get("fat_g")),
        saturated_fat_100g=_to_float(row.get("saturated_fat_g")),
        sodium_mg_100g=_to_float(row.get("sodium_mg")),
    )


def _to_float(value: object) -> float | None:
    if value is None:
        return None
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return None


# ── Search ────────────────────────────────────────────────────────────────────

async def search_products(query: str, page_size: int = 20) -> list[FoodItem]:
    """Case-insensitive substring match against food_name and brand.

    RLS on ``custom_foods`` means this automatically returns only the calling
    user's own items plus any items marked ``is_public``.  The Supabase service
    key bypasses RLS, so we must filter by user_id explicitly — however, this
    function is called by the registry which is invoked after auth middleware has
    already resolved ``user_id``; we receive it as a parameter during fan-out via
    :func:`search_with_user`.
    """
    # This thin wrapper is here so the registry can call it with the standard
    # (query, page_size) signature. It returns an empty list — the real call goes
    # through search_with_user below which includes user_id scoping.
    return []


async def search_with_user(query: str, user_id: str, page_size: int = 20) -> list[FoodItem]:
    """Scoped search; must be used instead of search_products in the router."""
    db = get_supabase()
    resp = (
        db.table("custom_foods")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .ilike("food_name", f"%{query}%")
        .limit(page_size)
        .execute()
    )
    return [_row_to_food_item(r) for r in (resp.data or [])]


async def lookup_barcode_with_user(barcode: str, user_id: str) -> FoodItem | None:
    """Exact barcode match scoped to the user's own items."""
    db = get_supabase()
    resp = (
        db.table("custom_foods")
        .select(_COLUMNS)
        .eq("user_id", user_id)
        .eq("barcode", barcode)
        .limit(1)
        .execute()
    )
    if resp.data:
        return _row_to_food_item(resp.data[0])
    return None


# ── CRUD ──────────────────────────────────────────────────────────────────────

def create_custom_food(user_id: str, payload: dict) -> dict:
    """Insert a custom food item and return the full stored row.

    If the item is public, its factual fields are mirrored into the anonymous
    ``food_catalogue`` straight away (ADR-029) so the curated catalogue value is
    captured at registration, not only if the user later deletes it.
    """
    db = get_supabase()
    row = {
        "user_id": user_id,
        "food_name": payload["food_name"],
        "brand": payload.get("brand"),
        "barcode": payload.get("barcode"),
        "energy_kcal": payload.get("energy_kcal"),
        "carbs_g": payload.get("carbs_g"),
        "protein_g": payload.get("protein_g"),
        "fat_g": payload.get("fat_g"),
        "saturated_fat_g": payload.get("saturated_fat_g"),
        "sodium_mg": payload.get("sodium_mg"),
        "serving_g": payload.get("serving_g"),
        "ingredients": payload.get("ingredients"),
        "ocr_raw": payload.get("ocr_raw"),
        # The user's explicit, informed "share to the common catalogue" choice.
        # It both publishes the item to other users today and is the consent gate
        # for anonymised retention (ADR-027/029); default is private.
        "is_public": bool(payload.get("is_public", False)),
    }
    resp = db.table("custom_foods").insert(row).execute()
    stored = resp.data[0] if resp.data else {}
    if stored.get("is_public"):
        sync_catalogue(db, user_id, stored)
    return stored


def update_custom_food(user_id: str, food_id: str, payload: dict) -> dict:
    """Update the user's own custom food. Returns the updated row or {} if not found.

    A public item's anonymous twin is kept in step (ADR-029): edits flow through
    to ``food_catalogue`` so the donated facts don't go stale.
    """
    db = get_supabase()
    updatable = {
        k: v
        for k, v in payload.items()
        if k in {
            "food_name", "brand", "barcode",
            "energy_kcal", "carbs_g", "protein_g", "fat_g",
            "saturated_fat_g", "sodium_mg", "serving_g", "ingredients",
            "is_public",
        }
    }
    if not updatable:
        return {}
    resp = (
        db.table("custom_foods")
        .update(updatable)
        .eq("id", food_id)
        .eq("user_id", user_id)
        .execute()
    )
    stored = resp.data[0] if resp.data else {}
    if stored.get("is_public"):
        sync_catalogue(db, user_id, stored)
    return stored


def delete_custom_food(user_id: str, food_id: str) -> None:
    """Delete the user's own custom food; the anonymous twin survives the erasure.

    A public item is normally already mirrored into ``food_catalogue`` at
    create/update time (ADR-029), so deletion just hard-deletes the user-owned
    row and leaves the (anonymous) twin standing — that is the "keep it even
    after deletion" behaviour. As a safety net, a public item that was somehow
    never mirrored (``catalogue_id`` is NULL — e.g. created before ADR-029) is
    donated here before the row goes. A private row is deleted with nothing kept.
    No-op if the item is not theirs / doesn't exist.
    """
    db = get_supabase()
    resp = (
        db.table("custom_foods")
        .select("*")
        .eq("id", food_id)
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    rows = resp.data or []
    if not rows:
        return
    if rows[0].get("is_public") and not rows[0].get("catalogue_id"):
        donate_to_catalogue(get_service_supabase(), rows[0])
    (
        db.table("custom_foods")
        .delete()
        .eq("id", food_id)
        .eq("user_id", user_id)
        .execute()
    )


# ── Anonymising donation (ADR-027) ──────────────────────────────────────────────


def donate_to_catalogue(service_db, row: dict) -> None:
    """Copy a public custom food's factual fields into ``food_catalogue``.

    Keeps only the factual product columns (``_CATALOGUE_FIELDS``), dropping
    ``user_id`` / ``created_at`` / ``ocr_raw`` so the result is anonymous, not
    merely pseudonymous (GDPR Recital 26). Upserts on ``barcode`` so re-donating
    the same product updates its facts instead of piling up duplicates;
    barcodeless rows are simply inserted (NULL barcodes stay distinct).

    This is the one-shot donate used by the deletion safety net (a public row
    that was never mirrored at create/update time). The proactive create/update
    path uses :func:`sync_catalogue`, which also records the back-pointer.

    Runs on the **service-role** client — the one sanctioned service-role data
    path (ADR-026) — because ``food_catalogue`` is writable only by that role.
    """
    facts = {k: row.get(k) for k in _CATALOGUE_FIELDS}
    facts["donated_at"] = date.today().isoformat()
    table = service_db.table("food_catalogue")
    if row.get("barcode"):
        table.upsert(facts, on_conflict="barcode").execute()
    else:
        table.insert(facts).execute()


def sync_catalogue(user_db, user_id: str, row: dict) -> None:
    """Mirror a *public* custom food into ``food_catalogue`` and keep it in step.

    Proactive donation (ADR-029): called on public create/update so the curated
    facts are captured at registration. The same anonymisation as
    :func:`donate_to_catalogue` applies (only ``_CATALOGUE_FIELDS`` survive —
    ``user_id`` / ``created_at`` / ``ocr_raw`` are never copied), so what lands
    in the catalogue is anonymous product data, not personal data.

    Dedupe strategy:
      * **Barcoded** items upsert on ``barcode`` — the same product donated by
        different users merges into one factual row (cross-user catalogue).
      * **Barcodeless** items have no natural key, so the first donation records
        the twin's id back on ``custom_foods.catalogue_id`` and later edits
        update that row in place instead of piling up duplicates.

    The catalogue write runs on the service-role client; the back-pointer write
    runs on the caller's RLS-scoped ``user_db`` (it is the user's own row).
    No-op for a private row — nothing is shared, nothing is retained.
    """
    if not row.get("is_public"):
        return
    service_db = get_service_supabase()
    facts = {k: row.get(k) for k in _CATALOGUE_FIELDS}
    table = service_db.table("food_catalogue")
    catalogue_id = row.get("catalogue_id")

    if row.get("barcode"):
        resp = table.upsert(
            {**facts, "donated_at": date.today().isoformat()},
            on_conflict="barcode",
        ).execute()
        twin_id = (resp.data or [{}])[0].get("id")
    elif catalogue_id:
        # Update the existing twin in place; keep its original donated_at.
        table.update(facts).eq("id", catalogue_id).execute()
        twin_id = catalogue_id
    else:
        resp = table.insert(
            {**facts, "donated_at": date.today().isoformat()}
        ).execute()
        twin_id = (resp.data or [{}])[0].get("id")

    # Record the de-identified back-pointer so future edits update this same twin
    # and reads can dedupe the live row against it. Forward-only: it lives on the
    # user's row and dies with it (ADR-029).
    if twin_id and twin_id != catalogue_id and row.get("id"):
        (
            user_db.table("custom_foods")
            .update({"catalogue_id": twin_id})
            .eq("id", row["id"])
            .eq("user_id", user_id)
            .execute()
        )


def donate_public_foods(service_db, user_id: str) -> int:
    """Donate any not-yet-mirrored public custom foods before account erasure.

    Called from the account-deletion path (which already runs on the service-role
    client). With proactive donation (ADR-029) most public rows already have a
    twin (``catalogue_id`` set) and are skipped; this is the safety net that
    catches public rows created before ADR-029 or whose proactive donation never
    landed. Private rows are left untouched — the caller's explicit
    ``custom_foods`` DELETE hard-erases all of them, public and private alike.
    Returns the number of rows donated here.
    """
    resp = (
        service_db.table("custom_foods")
        .select("*")
        .eq("user_id", user_id)
        .eq("is_public", True)
        .execute()
    )
    donated = 0
    for row in resp.data or []:
        if row.get("catalogue_id"):
            continue  # already mirrored proactively
        donate_to_catalogue(service_db, row)
        donated += 1
    return donated
