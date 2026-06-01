#!/usr/bin/env python3
"""Regenerate the vendored Matvaretabellen dataset.

Matvaretabellen (the Norwegian Food Composition Table) publishes its full table
as open data — a JSON dump of ~2 000 lab-analysed foods, each with per-100 g
nutrient values. Because it's small and changes only on a deliberate version
release, we **vendor** it as a build-time asset and search it in-process rather
than calling the API at runtime (ADR-018).

This script downloads the upstream ``foods.json`` and writes our normalised
``app/food_sources/data/matvaretabellen.<version>.json`` — the exact shape
``app/food_sources/matvaretabellen.py`` loads. Run it to refresh the dataset,
then bump ``DATASET_VERSION`` in that module to point at the new file. The result
is a reviewable diff, not a silent live refresh.

Usage:
    python scripts/ingest_matvaretabellen.py --version 2024-01
    python scripts/ingest_matvaretabellen.py --version 2024-01 \\
        --url https://www.matvaretabellen.no/api/nb/foods.json

Upstream data © Matvaretabellen (Mattilsynet / Helsedirektoratet / UiO),
published under NLOD 2.0 / CC BY 4.0 — attribution is preserved in the output.
"""

from __future__ import annotations

import argparse
import json
from datetime import date
from pathlib import Path

import httpx

# Default upstream open-data endpoint (Norwegian Bokmål food names).
DEFAULT_URL = "https://www.matvaretabellen.no/api/nb/foods.json"
USER_AGENT = "EmpiricalTracker/1.0 (https://github.com/frmingest/empirical-tracker)"

OUTPUT_DIR = Path(__file__).resolve().parent.parent / "app" / "food_sources" / "data"

# Matvaretabellen exposes nutrients as a list of constituents keyed by a short
# id. Map the ones the diary tracks to our per-100 g field names. Sodium ("Nacl"
# is salt; "Natrium" is sodium) is reported in mg already.
_CONSTITUENT_FIELDS = {
    "Karbo": "carbs_100g",      # Karbohydrat
    "Protein": "protein_100g",  # Protein
    "Fett": "fat_100g",         # Fett (total)
    "Mettet": "saturated_fat_100g",  # Mettede fettsyrer
    "Natrium": "sodium_mg_100g",     # Natrium (mg)
}


def _num(value: object) -> float | None:
    if value in (None, ""):
        return None
    try:
        return round(float(value), 1)
    except (TypeError, ValueError):
        return None


def _normalise(food: dict) -> dict | None:
    """Map one upstream food to our vendored shape; None if it has no name."""
    name = (food.get("foodName") or food.get("name") or "").strip()
    if not name:
        return None

    item: dict[str, object] = {
        "code": f"mvt:{food.get('foodId') or food.get('id') or ''}",
        "name": name,
        "energy_kcal_100g": None,
        "carbs_100g": None,
        "protein_100g": None,
        "fat_100g": None,
        "saturated_fat_100g": None,
        "sodium_mg_100g": None,
    }

    # Energy lives in its own block (kcal preferred) in the upstream schema.
    calories = food.get("calories") or {}
    item["energy_kcal_100g"] = _num(calories.get("quantity"))

    for constituent in food.get("constituents") or []:
        field = _CONSTITUENT_FIELDS.get(str(constituent.get("nutrientId") or ""))
        if field is not None:
            item[field] = _num(constituent.get("quantity"))

    return item


def fetch(url: str) -> list[dict]:
    """Download the upstream food table."""
    with httpx.Client(timeout=60.0, headers={"User-Agent": USER_AGENT}) as client:
        resp = client.get(url)
        resp.raise_for_status()
        data = resp.json()
    return data.get("foods") or data.get("data") or []


def build(foods: list[dict], version: str) -> dict:
    """Assemble the vendored dataset document around the normalised foods."""
    items = [i for i in (_normalise(f) for f in foods) if i is not None]
    items.sort(key=lambda i: i["name"])
    return {
        "version": version,
        "source": "matvaretabellen",
        "language": "nb",
        "license": "NLOD 2.0 / CC BY 4.0",
        "attribution": (
            "Matvaretabellen, Mattilsynet / Helsedirektoratet / "
            "Universitetet i Oslo"
        ),
        "retrieved": date.today().isoformat(),
        "foods": items,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="dataset version, e.g. 2024-01")
    parser.add_argument("--url", default=DEFAULT_URL, help="upstream foods.json URL")
    args = parser.parse_args()

    print(f"Downloading Matvaretabellen from {args.url} …")
    foods = fetch(args.url)
    document = build(foods, args.version)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUTPUT_DIR / f"matvaretabellen.{args.version}.json"
    out_path.write_text(
        json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"Wrote {len(document['foods'])} foods → {out_path}")
    print("Next: set DATASET_VERSION in app/food_sources/matvaretabellen.py to "
          f"'{args.version}'.")


if __name__ == "__main__":
    main()
