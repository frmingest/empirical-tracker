"""Matvaretabellen — the Norwegian Food Composition Table, in-process.

Matvaretabellen (Mattilsynet / Helsedirektoratet / Universitetet i Oslo) is the
authoritative, lab-analysed table of Norwegian whole foods — exactly the staples
a carnivore / low-carb eater logs (egg, ribeye, butter, salmon) and exactly where
Open Food Facts, a branded/barcode database, is weakest.

It's only ~2 000 foods, so rather than add a runtime dependency we **vendor the
dataset** as a build-time asset (``data/matvaretabellen.<version>.json``) and
search it in-process: zero rate limit, instant, works offline, and trivially
reproducible. The file is regenerated from the upstream open data by
``scripts/ingest_matvaretabellen.py`` and refreshed only on a deliberate version
bump (ADR-018). Values are per 100 g edible portion, taken as published — we
never invent them.
"""

from __future__ import annotations

import json
import re
from functools import lru_cache
from pathlib import Path

from app.food_sources.base import SOURCE_MVT, FoodItem, make_food_item

# The vendored dataset version this build ships. Bump deliberately alongside a
# regenerated data file (a reviewable change, not a silent live refresh).
DATASET_VERSION = "2024-01"
_DATA_DIR = Path(__file__).parent / "data"
_DATASET_PATH = _DATA_DIR / f"matvaretabellen.{DATASET_VERSION}.json"

_NUTRIENT_KEYS = (
    "energy_kcal_100g",
    "carbs_100g",
    "protein_100g",
    "fat_100g",
    "saturated_fat_100g",
    "sodium_mg_100g",
)


@lru_cache(maxsize=1)
def _load() -> list[FoodItem]:
    """Load and normalise the vendored table once, then cache it in memory."""
    raw = json.loads(_DATASET_PATH.read_text(encoding="utf-8"))
    items: list[FoodItem] = []
    for food in raw.get("foods", []):
        name = (food.get("name") or "").strip()
        if not name:
            continue
        items.append(
            make_food_item(
                source=SOURCE_MVT,
                code=food.get("code") or "",
                name=name,
                quantity="100 g",
                **{key: food.get(key) for key in _NUTRIENT_KEYS},
            )
        )
    return items


# Common English → Norwegian translations so that searching "potato" surfaces
# "Potet" entries without requiring the user to know the Norwegian term.
_EN_NO: dict[str, str] = {
    "potato": "potet",
    "potatoes": "potet",
    "carrot": "gulrot",
    "carrots": "gulrot",
    "onion": "løk",
    "onions": "løk",
    "chicken": "kylling",
    "beef": "biff",
    "pork": "svinekjøtt",
    "lamb": "lam",
    "salmon": "laks",
    "cod": "torsk",
    "herring": "sild",
    "shrimp": "reke",
    "butter": "smør",
    "milk": "melk",
    "cheese": "ost",
    "bread": "brød",
    "rice": "ris",
    "apple": "eple",
    "apples": "eple",
    "orange": "appelsin",
    "strawberry": "jordbær",
    "strawberries": "jordbær",
    "blueberry": "blåbær",
    "blueberries": "blåbær",
    "cucumber": "agurk",
    "cabbage": "kål",
    "spinach": "spinat",
    "mushroom": "sopp",
    "mushrooms": "sopp",
    "lentil": "linse",
    "lentils": "linse",
    "oat": "havre",
    "oats": "havre",
    "cream": "fløte",
    "yogurt": "yoghurt",
    "yoghurt": "yoghurt",
    "liver": "lever",
    "kidney": "nyre",
    "heart": "hjerte",
    "pea": "ert",
    "peas": "ert",
    "bean": "bønne",
    "beans": "bønne",
    "tomato": "tomat",
    "tomatoes": "tomat",
    "garlic": "hvitløk",
    "pepper": "pepper",
    "celery": "selleri",
    "leek": "purre",
    "cauliflower": "blomkål",
    "zucchini": "squash",
    "courgette": "squash",
    "corn": "mais",
    "walnut": "valnøtt",
    "walnuts": "valnøtt",
    "almond": "mandel",
    "almonds": "mandel",
    "hazelnut": "hasselnøtt",
    "hazelnuts": "hasselnøtt",
    "sunflower": "solsikke",
    "pumpkin": "gresskar",
    "avocado": "avokado",
    "lemon": "sitron",
    "grape": "drue",
    "grapes": "drue",
    "pear": "pære",
    "plum": "plomme",
    "plums": "plomme",
    "cherry": "kirsebær",
    "cherries": "kirsebær",
    "peach": "fersken",
    "melon": "melon",
    "pineapple": "ananas",
    "mango": "mango",
    "kiwi": "kiwi",
    "coconut": "kokos",
    "raisin": "rosin",
    "raisins": "rosin",
    "honey": "honning",
    "sugar": "sukker",
    "flour": "mel",
    "oatmeal": "havregrøt",
    "porridge": "grøt",
    "oil": "olje",
    "vinegar": "eddik",
    "salt": "salt",
    "mustard": "sennep",
    "mayonnaise": "majones",
    "ketchup": "ketchup",
    "tuna": "tunfisk",
    "mackerel": "makrell",
    "anchovy": "ansjos",
    "trout": "ørret",
    "turkey": "kalkun",
    "duck": "and",
    "sausage": "pølse",
    "sausages": "pølse",
    "ham": "skinke",
    "bacon": "bacon",
    "minced": "kjøttdeig",
    "mince": "kjøttdeig",
}


def _translate_terms(terms: list[str]) -> list[str]:
    """Replace any recognised English term with its Norwegian equivalent."""
    return [_EN_NO.get(t, t) for t in terms]


def _score(name: str, terms: list[str]) -> int:
    """Rank a match: every term must appear; whole-word and prefix hits rank up.

    Keeps the ordering intuitive for short, specific queries ("egg", "ribeye")
    without pulling in a search dependency for a ~2 000-row table.
    """
    lowered = name.lower()
    score = 0
    for term in terms:
        if term not in lowered:
            return -1  # AND semantics: a missing term disqualifies the food
        if re.search(rf"\b{re.escape(term)}", lowered):
            score += 2  # matches at a word boundary
        else:
            score += 1
    if lowered.startswith(terms[0]):
        score += 3  # a leading match is almost always what the user meant
    return score


def search(query: str, page_size: int = 20) -> list[FoodItem]:
    """Substring/word search over the vendored table, best matches first."""
    terms = [t for t in query.lower().split() if t]
    if not terms:
        return []
    terms = _translate_terms(terms)
    scored = [(item, _score(item["name"], terms)) for item in _load()]
    hits = [(item, s) for item, s in scored if s >= 0]
    hits.sort(key=lambda pair: (-pair[1], pair[0]["name"]))
    return [item for item, _ in hits[:page_size]]


# Async wrapper so the registry can treat every source uniformly. The lookup is
# pure in-memory work, so there's nothing to await — but the signature matches
# the live (OFF / USDA) sources.
async def search_products(query: str, page_size: int = 20) -> list[FoodItem]:
    """Full-text search Matvaretabellen; return normalised food items."""
    return search(query, page_size)
