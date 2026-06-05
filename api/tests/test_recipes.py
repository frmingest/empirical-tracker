from datetime import UTC, datetime, timedelta
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.main import app
from app.recipes import repository

client = TestClient(app)


def _fluent(execute_data=None):
    """Build a fluent mock where every chained method returns self."""
    m = MagicMock()
    m.execute.return_value = MagicMock(data=execute_data or [])
    for method in (
        "table", "select", "eq", "or_", "order",
        "insert", "update", "delete", "upsert",
    ):
        getattr(m, method).return_value = m
    return m


def _iso(days_ago: int) -> str:
    return (datetime.now(UTC) - timedelta(days=days_ago)).isoformat()


# ── repository: reads ─────────────────────────────────────────────────────────────


@patch("app.recipes.repository.get_supabase")
def test_list_recipes_scopes_to_user_or_public(mock_db):
    recipes = _fluent(
        execute_data=[
            {
                "id": "r1",
                "title": "Pork Belly Bites",
                "category": "Breakfast",
                "created_at": _iso(1),
            }
        ]
    )
    favs = _fluent(execute_data=[])
    catalogue = _fluent(execute_data=[])
    mock_db.return_value = recipes
    # recipes → recipe_favorites → recipe_catalogue
    recipes.table.side_effect = [recipes, favs, catalogue]
    out = repository.list_recipes("u-9")
    assert out[0]["title"] == "Pork Belly Bites"
    recipes.or_.assert_called_with("user_id.eq.u-9,is_public.eq.true")
    recipes.order.assert_called_with("created_at", desc=True)


@patch("app.recipes.repository.get_supabase")
def test_list_recipes_marks_favorite_and_new(mock_db):
    recipes = _fluent(
        execute_data=[
            {"id": "r1", "title": "Fresh", "category": "Beef", "created_at": _iso(2)},
            {"id": "r2", "title": "Old", "category": "Beef", "created_at": _iso(40)},
        ]
    )
    favs = _fluent(execute_data=[{"recipe_id": "r1"}])
    catalogue = _fluent(execute_data=[])
    # recipes → recipe_favorites → recipe_catalogue.
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs, catalogue]

    out = repository.list_recipes("u1")
    by_id = {r["id"]: r for r in out}
    assert by_id["r1"]["is_favorite"] is True
    assert by_id["r1"]["is_new"] is True
    assert by_id["r2"]["is_favorite"] is False
    assert by_id["r2"]["is_new"] is False


@patch("app.recipes.repository.get_supabase")
def test_list_recipes_filters_category_and_free(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    repository.list_recipes("u1", category="Beef", only_free=True)
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("category", "Beef") in eq_calls
    assert ("is_premium", False) in eq_calls


@patch("app.recipes.repository.get_supabase")
def test_get_recipe_returns_none_when_absent(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    assert repository.get_recipe("u1", "missing") is None


@patch("app.recipes.repository.get_supabase")
def test_list_categories_distinct_sorted(mock_db):
    db = _fluent(
        execute_data=[
            {"category": "Snacks"},
            {"category": "Beef"},
            {"category": "Snacks"},
        ]
    )
    mock_db.return_value = db
    assert repository.list_categories("u1") == ["Beef", "Snacks"]


# ── repository: writes ────────────────────────────────────────────────────────────


@patch("app.recipes.repository.get_supabase")
def test_create_recipe_inserts_user_scoped_row(mock_db):
    inserted_row = {"id": "r1", "title": "Ribeye", "created_at": _iso(0)}
    recipes = _fluent(execute_data=[inserted_row])
    favs = _fluent(execute_data=[])
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs]

    out = repository.create_recipe(
        "u1",
        {
            "title": "Ribeye",
            "category": "Beef",
            "ingredients": ["1 ribeye"],
            "instructions": ["Sear it"],
        },
    )
    inserted = recipes.insert.call_args.args[0]
    assert inserted["user_id"] == "u1"
    assert inserted["title"] == "Ribeye"
    assert inserted["ingredients"] == ["1 ribeye"]
    assert out["id"] == "r1"
    assert out["is_favorite"] is False


@patch("app.recipes.repository.get_supabase")
def test_update_recipe_filters_by_user(mock_db):
    updated = {"id": "r1", "title": "New title", "created_at": _iso(0)}
    recipes = _fluent(execute_data=[updated])
    favs = _fluent(execute_data=[])
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs]

    out = repository.update_recipe("u1", "r1", {"title": "New title", "category": "Beef"})
    eq_calls = [call.args for call in recipes.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "r1") in eq_calls
    assert out["title"] == "New title"


@patch("app.recipes.repository.get_supabase")
def test_update_recipe_returns_none_when_not_owned(mock_db):
    db = _fluent(execute_data=[])
    mock_db.return_value = db
    assert repository.update_recipe("u1", "r1", {"title": "X", "category": "Beef"}) is None


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_delete_recipe_filters_by_user_and_donates_public(mock_db, mock_service):
    # A public recipe is donated (factual fields only) before being deleted.
    db = _fluent(
        execute_data=[
            {
                "id": "r1",
                "user_id": "u1",
                "title": "Ribeye",
                "category": "Beef",
                "image_url": "https://cdn/u1/ribeye.jpg",
                "ingredients": ["1 ribeye"],
                "instructions": ["Sear it"],
                "is_public": True,
                "created_at": _iso(3),
            }
        ]
    )
    mock_db.return_value = db
    service = _fluent()
    mock_service.return_value = service

    repository.delete_recipe("u1", "r1")

    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "r1") in eq_calls
    db.delete.assert_called()

    # A single de-identified facts dict: factual fields + a coarse donated_at.
    donated = service.insert.call_args.args[0]
    assert donated["title"] == "Ribeye"
    assert donated["category"] == "Beef"
    assert donated["ingredients"] == ["1 ribeye"]
    assert donated["instructions"] == ["Sear it"]
    assert "donated_at" in donated
    # Identifying fields are never donated.
    assert "user_id" not in donated
    assert "image_url" not in donated
    assert "created_at" not in donated


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_delete_recipe_skips_donation_when_private(mock_db, mock_service):
    db = _fluent(
        execute_data=[
            {"id": "r1", "user_id": "u1", "title": "Secret", "category": "Beef",
             "is_public": False, "created_at": _iso(3)}
        ]
    )
    mock_db.return_value = db
    service = _fluent()
    mock_service.return_value = service

    repository.delete_recipe("u1", "r1")

    service.insert.assert_not_called()
    db.delete.assert_called()


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_delete_recipe_noop_when_not_owned(mock_db, mock_service):
    db = _fluent(execute_data=[])  # select finds nothing → not the user's recipe
    mock_db.return_value = db
    service = _fluent()
    mock_service.return_value = service

    repository.delete_recipe("u1", "r1")

    service.insert.assert_not_called()
    db.delete.assert_not_called()


# ── proactive donation: mirror on create / update (ADR-029) ─────────────────────


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_create_public_recipe_mirrors_and_links(mock_db, mock_service):
    inserted = {
        "id": "r1", "title": "Ribeye", "category": "Beef",
        "image_url": "https://cdn/u1/r.jpg", "ingredients": ["1 ribeye"],
        "instructions": ["Sear it"], "is_public": True,
        "created_at": _iso(0), "catalogue_id": None,
    }
    recipes = _fluent(execute_data=[inserted])
    favs = _fluent(execute_data=[])
    service = _fluent(execute_data=[{"id": "cat1"}])
    mock_db.return_value = recipes
    mock_service.return_value = service
    # insert recipe → back-pointer update → favourites lookup
    recipes.table.side_effect = [recipes, recipes, favs]

    repository.create_recipe(
        "u1",
        {"title": "Ribeye", "category": "Beef", "is_public": True,
         "ingredients": ["1 ribeye"], "instructions": ["Sear it"]},
    )

    # Donated at create time, de-identified (no user_id / image_url / created_at).
    donated = service.insert.call_args.args[0]
    assert donated["title"] == "Ribeye"
    assert "user_id" not in donated and "image_url" not in donated
    assert "donated_at" in donated
    # The twin id is linked back onto the user's own recipe row.
    update_args = [c.args[0] for c in recipes.update.call_args_list]
    assert {"catalogue_id": "cat1"} in update_args


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_create_private_recipe_is_not_mirrored(mock_db, mock_service):
    inserted = {"id": "r1", "title": "Secret", "category": "Beef",
                "is_public": False, "created_at": _iso(0), "catalogue_id": None}
    recipes = _fluent(execute_data=[inserted])
    favs = _fluent(execute_data=[])
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs]

    repository.create_recipe("u1", {"title": "Secret", "category": "Beef"})

    mock_service.assert_not_called()


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_update_public_recipe_updates_twin_in_place(mock_db, mock_service):
    updated = {"id": "r1", "title": "New", "category": "Beef", "is_public": True,
               "created_at": _iso(0), "catalogue_id": "cat1"}
    recipes = _fluent(execute_data=[updated])
    favs = _fluent(execute_data=[])
    service = _fluent()
    mock_db.return_value = recipes
    mock_service.return_value = service
    recipes.table.side_effect = [recipes, favs]

    repository.update_recipe("u1", "r1", {"title": "New", "category": "Beef", "is_public": True})

    # Already linked → the existing twin is updated in place, not re-inserted.
    service.update.assert_called_once()
    service.insert.assert_not_called()


@patch("app.recipes.repository.get_service_supabase")
@patch("app.recipes.repository.get_supabase")
def test_delete_already_mirrored_recipe_skips_safety_net(mock_db, mock_service):
    db = _fluent(execute_data=[{
        "id": "r1", "user_id": "u1", "title": "Ribeye", "category": "Beef",
        "is_public": True, "created_at": _iso(3), "catalogue_id": "cat1",
    }])
    mock_db.return_value = db

    repository.delete_recipe("u1", "r1")

    # Twin already exists → keep it, just hard-delete the user row.
    db.delete.assert_called()
    mock_service.assert_not_called()


def test_donate_public_recipes_skips_already_mirrored():
    rows = [
        {"id": "r1", "title": "A", "category": "Beef", "is_public": True,
         "ingredients": [], "instructions": [], "catalogue_id": None},
        {"id": "r2", "title": "B", "category": "Beef", "is_public": True,
         "ingredients": [], "instructions": [], "catalogue_id": "cat2"},
    ]
    service = _fluent(execute_data=rows)
    n = repository.donate_public_recipes(service, "u1")
    assert n == 1
    service.insert.assert_called_once()


@patch("app.recipes.repository.get_supabase")
def test_list_recipes_hides_live_public_twin(mock_db):
    # A live public recipe (r1) already carries its twin id c1; the catalogue's
    # c1 row must be deduped away, while an orphaned twin (c2) still shows.
    recipes = _fluent(execute_data=[
        {"id": "r1", "title": "Live", "category": "Beef",
         "created_at": _iso(1), "catalogue_id": "c1"}
    ])
    favs = _fluent(execute_data=[])
    catalogue = _fluent(execute_data=[
        {"id": "c1", "title": "Live", "category": "Beef", "donated_at": "2026-05-01"},
        {"id": "c2", "title": "Orphan", "category": "Beef", "donated_at": "2026-04-01"},
    ])
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs, catalogue]

    out = repository.list_recipes("u1")
    ids = {r["id"] for r in out}
    assert "r1" in ids          # the live row is shown
    assert "c1" not in ids      # its twin is deduped away
    assert "c2" in ids          # an orphaned donated recipe still surfaces


@patch("app.recipes.repository.get_supabase")
def test_list_recipes_includes_donated_catalogue(mock_db):
    recipes = _fluent(
        execute_data=[
            {"id": "r1", "title": "Own", "category": "Beef", "created_at": _iso(1)}
        ]
    )
    favs = _fluent(execute_data=[])
    catalogue = _fluent(
        execute_data=[
            {
                "id": "c1",
                "title": "Donated",
                "category": "Beef",
                "ingredients": ["x"],
                "instructions": ["y"],
                "donated_at": "2026-05-01",
            }
        ]
    )
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs, catalogue]

    out = repository.list_recipes("u1")
    by_id = {r["id"]: r for r in out}
    # Donated rows are anonymous: no owner, never favourited, no "New!" badge.
    donated = by_id["c1"]
    assert donated["user_id"] is None
    assert donated["is_favorite"] is False
    assert donated["is_new"] is False
    assert donated["is_donated"] is True
    assert donated["image_url"] is None


@patch("app.recipes.repository.get_supabase")
def test_get_recipe_falls_back_to_catalogue(mock_db):
    recipes = _fluent(execute_data=[])  # not in the user's recipes
    catalogue = _fluent(
        execute_data=[
            {"id": "c1", "title": "Donated", "category": "Beef", "donated_at": "2026-05-01"}
        ]
    )
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, catalogue]

    out = repository.get_recipe("u1", "c1")
    assert out is not None
    assert out["id"] == "c1"
    assert out["is_donated"] is True


@patch("app.recipes.repository.get_supabase")
def test_set_favorite_upserts_when_true(mock_db):
    db = _fluent()
    mock_db.return_value = db
    out = repository.set_favorite("u1", "r1", True)
    db.upsert.assert_called_once()
    assert out == {"recipe_id": "r1", "is_favorite": True}


@patch("app.recipes.repository.get_supabase")
def test_set_favorite_deletes_when_false(mock_db):
    db = _fluent()
    mock_db.return_value = db
    out = repository.set_favorite("u1", "r1", False)
    db.delete.assert_called()
    assert out == {"recipe_id": "r1", "is_favorite": False}


# ── HTTP endpoints ───────────────────────────────────────────────────────────────


@patch("app.recipes.router.repository.list_recipes")
def test_list_recipes_endpoint(mock_list):
    mock_list.return_value = [{"id": "r1", "title": "Pork Belly Bites"}]
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/recipes")
        assert res.status_code == 200
        assert res.json()[0]["title"] == "Pork Belly Bites"
        mock_list.assert_called_once_with("u1", None, False)
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.list_recipes")
def test_list_recipes_endpoint_passes_filters(mock_list):
    mock_list.return_value = []
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/recipes?category=Beef&only_free=true")
        assert res.status_code == 200
        mock_list.assert_called_once_with("u1", "Beef", True)
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.get_recipe")
def test_get_recipe_endpoint_404(mock_get):
    mock_get.return_value = None
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.get("/recipes/missing")
        assert res.status_code == 404
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.create_recipe")
def test_create_recipe_endpoint_ok(mock_create):
    mock_create.return_value = {"id": "r1"}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post(
            "/recipes",
            json={
                "title": "Ribeye",
                "category": "Beef",
                "ingredients": ["1 ribeye", "  ", ""],
                "instructions": ["Sear it"],
            },
        )
        assert res.status_code == 201
        # Blank ingredient rows are stripped by the validator.
        payload = mock_create.call_args.args[1]
        assert payload["ingredients"] == ["1 ribeye"]
    finally:
        app.dependency_overrides.clear()


def test_create_recipe_endpoint_rejects_empty_title():
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.post("/recipes", json={"title": "  ", "category": "Beef"})
        assert res.status_code == 422
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.update_recipe")
def test_update_recipe_endpoint_404(mock_update):
    mock_update.return_value = None
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.put("/recipes/r1", json={"title": "X", "category": "Beef"})
        assert res.status_code == 404
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.delete_recipe")
def test_delete_recipe_endpoint(mock_del):
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.delete("/recipes/r1")
        assert res.status_code == 200
        mock_del.assert_called_once_with("u1", "r1")
    finally:
        app.dependency_overrides.clear()


@patch("app.recipes.router.repository.set_favorite")
def test_favorite_endpoint(mock_fav):
    mock_fav.return_value = {"recipe_id": "r1", "is_favorite": True}
    app.dependency_overrides[current_user_id] = lambda: "u1"
    try:
        res = client.put("/recipes/r1/favorite", json={"favorite": True})
        assert res.status_code == 200
        mock_fav.assert_called_once_with("u1", "r1", True)
    finally:
        app.dependency_overrides.clear()
