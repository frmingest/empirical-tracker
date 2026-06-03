"""The shared food shape and the source contract.

Every food source — Open Food Facts, Matvaretabellen, USDA — returns the same
normalised dict, a ``FoodItem``: a name, optional brand/quantity, six per-100 g
nutrient values exactly as published (never invented), and a ``source`` tag that
records where the numbers came from. The ``source`` tag is what lets the diary
show a provenance badge and lets a clinician reading an export tell a
lab-analysed whole-food entry from a crowd-sourced branded one (ADR-018).

A later phase will add an optional micronutrient map to this shape; today's six
macro fields are the stable contract the frontend and storage rely on.
"""

from __future__ import annotations

from typing import Protocol, TypedDict

# ── Source codes ────────────────────────────────────────────────────────────────
# Short, stable identifiers persisted on entries and surfaced as a UI badge.
SOURCE_OFF = "off"      # Open Food Facts — branded / barcode
SOURCE_MVT = "mvt"      # Matvaretabellen — Norwegian whole foods
SOURCE_USDA = "usda"    # USDA FoodData Central — American whole foods
SOURCE_CUSTOM = "custom"  # User-contributed catalogue (custom_foods table)

# Real database sources, in the order the "all" search and UI prefer them.
# Custom comes first so a user's own data always wins over external sources.
SOURCES = (SOURCE_CUSTOM, SOURCE_MVT, SOURCE_USDA, SOURCE_OFF)
VALID_SOURCES = frozenset(SOURCES)


class FoodItem(TypedDict):
    """A food normalised to the diary's shape. All nutrients are per 100 g."""

    code: str
    name: str
    brand: str | None
    quantity: str | None
    energy_kcal_100g: float | None
    carbs_100g: float | None
    protein_100g: float | None
    fat_100g: float | None
    saturated_fat_100g: float | None
    sodium_mg_100g: float | None
    source: str


def make_food_item(
    *,
    source: str,
    name: str,
    code: str = "",
    brand: str | None = None,
    quantity: str | None = None,
    energy_kcal_100g: float | None = None,
    carbs_100g: float | None = None,
    protein_100g: float | None = None,
    fat_100g: float | None = None,
    saturated_fat_100g: float | None = None,
    sodium_mg_100g: float | None = None,
) -> FoodItem:
    """Build a ``FoodItem``, giving every source one place to stamp ``source``."""
    return {
        "code": code,
        "name": name,
        "brand": brand,
        "quantity": quantity,
        "energy_kcal_100g": energy_kcal_100g,
        "carbs_100g": carbs_100g,
        "protein_100g": protein_100g,
        "fat_100g": fat_100g,
        "saturated_fat_100g": saturated_fat_100g,
        "sodium_mg_100g": sodium_mg_100g,
        "source": source,
    }


class FoodSource(Protocol):
    """What the diary needs from any food source.

    ``search`` is required of every source. ``lookup_barcode`` is optional —
    only product databases (Open Food Facts) have barcodes; whole-food
    composition tables don't, so they simply don't implement it.
    """

    async def search(self, query: str, page_size: int = 20) -> list[FoodItem]:
        ...
