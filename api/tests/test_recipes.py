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
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs]
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
    # First .table() call is recipes, second is recipe_favorites.
    mock_db.return_value = recipes
    recipes.table.side_effect = [recipes, favs]

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


@patch("app.recipes.repository.get_supabase")
def test_delete_recipe_filters_by_user(mock_db):
    db = _fluent()
    mock_db.return_value = db
    repository.delete_recipe("u1", "r1")
    eq_calls = [call.args for call in db.eq.call_args_list]
    assert ("user_id", "u1") in eq_calls
    assert ("id", "r1") in eq_calls


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
