"""The source registry — one place that knows every food source.

The diary and meal-plan routers ask the registry for results by ``source`` code
and stay otherwise source-agnostic. ``"all"`` fans out to every real source
concurrently and merges the results, degrading gracefully if one source is down
(a live OFF/USDA outage shouldn't blank out the Norwegian whole-food results that
are already in memory). See ADR-018.

The ``custom`` source is user-scoped and therefore receives ``user_id`` as an
extra argument in the fan-out path.  External sources that don't need it simply
ignore it.
"""

from __future__ import annotations

import asyncio
import logging

from app.food_sources import custom, matvaretabellen, openfoodfacts, usda
from app.food_sources.base import (
    SOURCE_CUSTOM,
    SOURCE_MVT,
    SOURCE_OFF,
    SOURCE_USDA,
    SOURCES,
    FoodItem,
)

logger = logging.getLogger(__name__)

# Sentinel meaning "search every real source and merge".
SOURCE_ALL = "all"

# Sources accepted on the search endpoint: each real source plus "all".
SELECTABLE_SOURCES = frozenset({*SOURCES, SOURCE_ALL})


async def _search_external(source: str, query: str, page_size: int) -> list[FoodItem]:
    modules = {
        SOURCE_OFF: openfoodfacts,
        SOURCE_MVT: matvaretabellen,
        SOURCE_USDA: usda,
    }
    return await modules[source].search_products(query, page_size)


async def _search_external_safe(source: str, query: str, page_size: int) -> list[FoodItem]:
    try:
        return await _search_external(source, query, page_size)
    except Exception:  # noqa: BLE001
        logger.warning("Food source %r failed during 'all' search", source, exc_info=True)
        return []


async def search(
    query: str,
    source: str = SOURCE_ALL,
    page_size: int = 20,
    user_id: str | None = None,
) -> list[FoodItem]:
    """Search one source, or every source when ``source == "all"`` (the default).

    ``user_id`` is required when ``source`` is ``"custom"`` or ``"all"`` so the
    custom source can scope results to the calling user.  It is silently ignored
    by the external sources.
    """
    if source == SOURCE_CUSTOM:
        if not user_id:
            return []
        return await custom.search_with_user(query, user_id, page_size)

    if source == SOURCE_ALL:
        external_sources = [SOURCE_MVT, SOURCE_USDA, SOURCE_OFF]
        tasks: list[asyncio.coroutines] = [  # type: ignore[valid-type]
            *(_search_external_safe(s, query, page_size) for s in external_sources),
        ]
        if user_id:
            tasks.append(custom.search_with_user(query, user_id, page_size))

        results = await asyncio.gather(*tasks)
        merged: list[FoodItem] = []
        # Custom results first so user's own data wins.
        if user_id:
            merged.extend(results[-1])  # custom is the last task appended
            for items in results[:-1]:
                merged.extend(items)
        else:
            for items in results:
                merged.extend(items)
        return merged

    # Single named external source — propagate errors to the router.
    return await _search_external(source, query, page_size)
