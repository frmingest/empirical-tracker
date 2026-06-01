"""The source registry — one place that knows every food source.

The diary and meal-plan routers ask the registry for results by ``source`` code
and stay otherwise source-agnostic. ``"all"`` fans out to every real source
concurrently and merges the results, degrading gracefully if one source is down
(a live OFF/USDA outage shouldn't blank out the Norwegian whole-food results that
are already in memory). See ADR-018.
"""

from __future__ import annotations

import asyncio
import logging

from app.food_sources import matvaretabellen, openfoodfacts, usda
from app.food_sources.base import (
    SOURCE_MVT,
    SOURCE_OFF,
    SOURCE_USDA,
    SOURCES,
    FoodItem,
)

logger = logging.getLogger(__name__)

# Sentinel meaning "search every real source and merge".
SOURCE_ALL = "all"

# code -> the source module. We dispatch through the module (rather than caching
# its ``search_products`` reference) so the lookup always sees the current
# function — which keeps the sources patchable in tests.
_MODULES = {
    SOURCE_OFF: openfoodfacts,
    SOURCE_MVT: matvaretabellen,
    SOURCE_USDA: usda,
}

# Sources accepted on the search endpoint: each real source plus "all".
SELECTABLE_SOURCES = frozenset({*SOURCES, SOURCE_ALL})


async def _search_one(source: str, query: str, page_size: int) -> list[FoodItem]:
    return await _MODULES[source].search_products(query, page_size)


async def _search_one_safe(source: str, query: str, page_size: int) -> list[FoodItem]:
    """Search a single source, swallowing its failure during an "all" merge."""
    try:
        return await _search_one(source, query, page_size)
    except Exception:  # noqa: BLE001 — one source failing must not blank the rest
        logger.warning("Food source %r failed during 'all' search", source, exc_info=True)
        return []


async def search(query: str, source: str = SOURCE_OFF, page_size: int = 20) -> list[FoodItem]:
    """Search one source, or every source when ``source == "all"``.

    A single named source propagates its errors (the router maps them to 502);
    ``"all"`` is best-effort and returns whatever sources responded, ordered by
    the source preference in :data:`~app.food_sources.base.SOURCES`
    (whole foods first, branded last).
    """
    if source == SOURCE_ALL:
        results = await asyncio.gather(
            *(_search_one_safe(s, query, page_size) for s in SOURCES)
        )
        merged: list[FoodItem] = []
        for items in results:
            merged.extend(items)
        return merged
    return await _search_one(source, query, page_size)
