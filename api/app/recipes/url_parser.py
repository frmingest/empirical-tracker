"""Recipe-URL importer: fetch a recipe page and return a `RecipeIn`-shaped dict.

Two extraction paths:

1. **schema.org / JSON-LD** (preferred, no LLM call): most recipe sites embed a
   `<script type="application/ld+json">` block with a `Recipe` node — name,
   ingredients, instructions, nutrition, image, etc. When present and complete
   enough (title + ingredients + instructions), it is used directly.
2. **Claude Haiku fallback**: for pages without usable JSON-LD, the page's
   visible text is sent to Claude Haiku with the same "never invent numbers"
   discipline as the nutrition-label OCR parser (`label_parser.py`).

The caller (the `/recipes/import-url` endpoint) treats the result as a preview —
nothing is persisted here.
"""

from __future__ import annotations

import ipaddress
import json
import logging
import socket
from urllib.parse import urljoin, urlparse

import anthropic
import httpx
from bs4 import BeautifulSoup

from app.config import get_settings

logger = logging.getLogger(__name__)

_MODEL = "claude-haiku-4-5-20251001"
_TIMEOUT = 10.0
_MAX_REDIRECTS = 5

# Many recipe sites block non-browser User-Agents (e.g. via Cloudflare bot
# protection), regardless of the request's intent. This is a normal desktop
# Chrome UA + the `Accept`/`Accept-Language` headers a browser would send for a
# page navigation — the request is on behalf of a single user importing a page
# they're looking at, not bulk scraping.
_HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "en-US,en;q=0.9",
}

_SYSTEM = """\
You are a recipe data extractor. You receive the visible text content of a recipe
web page and must extract the recipe as a JSON object.

Return ONLY valid JSON, no markdown fences, no commentary.

Required JSON shape:
{
  "title": <string or null>,
  "category": <string or null>,
  "serving_size": <string or null>,
  "calories_kcal": <number or null>,
  "protein_g": <number or null>,
  "fat_g": <number or null>,
  "carbs_g": <number or null>,
  "ingredients": [<string>, ...],
  "instructions": [<string>, ...],
  "fact": <string or null>
}

Rules:
- "ingredients" is an ordered list of ingredient lines as written on the page
  (e.g. "8 oz pork belly, cubed").
- "instructions" is an ordered list of step descriptions, one per step.
- "category" should be a short course/meal label (e.g. "Breakfast", "Dinner",
  "Dessert") if one is evident, otherwise null.
- Nutrition values are PER SERVING. If the page gives a different basis (e.g.
  per 100g) or no nutrition info, return null for those fields — never estimate
  or invent numbers.
- "fact" is an optional one-sentence interesting note about the recipe (from the
  page's description or intro), or null.
- If the page does not appear to contain a recipe at all, return null for every
  field and an empty list for "ingredients" / "instructions".
"""


# ── SSRF guard ───────────────────────────────────────────────────────────────────


def _is_public_host(host: str) -> bool:
    """Resolve `host` and reject anything pointing at a private/internal address.

    Recipe-URL import takes a user-supplied URL and fetches it server-side — a
    classic SSRF vector (cloud metadata endpoints, internal services, etc.). We
    only allow hosts that resolve exclusively to public, routable addresses.
    """
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    for info in infos:
        addr = info[4][0]
        try:
            ip = ipaddress.ip_address(addr)
        except ValueError:
            return False
        if (
            ip.is_private
            or ip.is_loopback
            or ip.is_link_local
            or ip.is_multicast
            or ip.is_reserved
            or ip.is_unspecified
        ):
            return False
    return True


def _validate_url(url: str) -> str:
    """Validate `url` is an http(s) URL pointing at a public host. Returns it unchanged."""
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("URL must use http or https")
    if not parsed.hostname:
        raise ValueError("URL must include a host")
    if not _is_public_host(parsed.hostname):
        raise ValueError("URL must not point at a private or internal address")
    return url


# ── Fetch ────────────────────────────────────────────────────────────────────────


def fetch_html(url: str) -> str:
    """Fetch `url` and return its HTML body, capped at `max_recipe_page_bytes`.

    Follows redirects manually (up to `_MAX_REDIRECTS` hops), validating each
    target against the SSRF guard — `httpx`'s built-in `follow_redirects` would
    not re-check redirected hosts.
    """
    settings = get_settings()
    url = _validate_url(url)

    try:
        with httpx.Client(timeout=_TIMEOUT, headers=_HEADERS) as client:
            for _ in range(_MAX_REDIRECTS + 1):
                with client.stream("GET", url, follow_redirects=False) as resp:
                    if resp.is_redirect:
                        location = resp.headers.get("location")
                        if not location:
                            break
                        url = _validate_url(urljoin(url, location))
                        continue
                    if resp.status_code >= 400:
                        raise ValueError(
                            f"The recipe site returned an error (HTTP {resp.status_code})"
                        )
                    # Stream and cap the body — a malicious server could otherwise
                    # stall the connection open while sending unbounded data.
                    chunks: list[bytes] = []
                    total = 0
                    for chunk in resp.iter_bytes():
                        chunks.append(chunk)
                        total += len(chunk)
                        if total >= settings.max_recipe_page_bytes:
                            break
                    content = b"".join(chunks)[: settings.max_recipe_page_bytes]
                    return content.decode(resp.encoding or "utf-8", errors="replace")
            raise ValueError("Too many redirects")
    except httpx.HTTPError as exc:
        raise ValueError(f"Could not reach that URL: {exc}") from exc


# ── JSON-LD / schema.org extraction ────────────────────────────────────────────────


def _find_recipe_node(data: object) -> dict | None:
    """Depth-first search for a `@type: Recipe` node in parsed JSON-LD data."""
    nodes = data if isinstance(data, list) else [data]
    for node in nodes:
        if not isinstance(node, dict):
            continue
        types = node.get("@type")
        if types == "Recipe" or (isinstance(types, list) and "Recipe" in types):
            return node
        graph = node.get("@graph")
        if graph:
            found = _find_recipe_node(graph)
            if found:
                return found
    return None


def _extract_json_ld_recipe(html: str) -> dict | None:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup.find_all("script", type="application/ld+json"):
        try:
            data = json.loads(tag.string or "")
        except (json.JSONDecodeError, TypeError):
            continue
        recipe = _find_recipe_node(data)
        if recipe:
            return recipe
    return None


def _as_text_list(value: object) -> list[str]:
    """Normalise a schema.org `recipeIngredient` / `recipeInstructions` value."""
    if value is None:
        return []
    if isinstance(value, str):
        # Some sites put the whole instruction text in one string, newline-separated.
        return [line.strip() for line in value.splitlines() if line.strip()]
    if not isinstance(value, list):
        return []
    items: list[str] = []
    for item in value:
        if isinstance(item, str):
            text = item.strip()
        elif isinstance(item, dict):
            if item.get("@type") == "HowToSection":
                items.extend(_as_text_list(item.get("itemListElement")))
                continue
            text = (item.get("text") or item.get("name") or "").strip()
        else:
            text = ""
        if text:
            items.append(text)
    return items


def _first_str(value: object) -> str | None:
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, list):
        for item in value:
            text = _first_str(item)
            if text:
                return text
    if isinstance(value, dict):
        return _first_str(value.get("name") or value.get("@id"))
    return None


def _image_url(value: object) -> str | None:
    if isinstance(value, str):
        return value.strip() or None
    if isinstance(value, list) and value:
        return _image_url(value[0])
    if isinstance(value, dict):
        return _image_url(value.get("url"))
    return None


def _nutrient(nutrition: dict | None, key: str) -> float | None:
    if not nutrition:
        return None
    return _to_float(nutrition.get(key))


def _to_float(value: object) -> float | None:
    """Parse a number out of values like `"270 kcal"`, `"12 g"`, `12`, `"12.5"`."""
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if not isinstance(value, str):
        return None
    digits = "".join(ch for ch in value if ch.isdigit() or ch in ".,").replace(",", ".")
    if not digits:
        return None
    try:
        return float(digits)
    except ValueError:
        return None


def _json_ld_to_recipe(node: dict) -> dict:
    nutrition = node.get("nutrition") if isinstance(node.get("nutrition"), dict) else None
    return {
        "title": _first_str(node.get("name")) or "",
        "category": _first_str(node.get("recipeCategory")),
        "image_url": _image_url(node.get("image")),
        "serving_size": _first_str(node.get("recipeYield")),
        "calories_kcal": _nutrient(nutrition, "calories"),
        "protein_g": _nutrient(nutrition, "proteinContent"),
        "fat_g": _nutrient(nutrition, "fatContent"),
        "carbs_g": _nutrient(nutrition, "carbohydrateContent"),
        "ingredients": _as_text_list(node.get("recipeIngredient")),
        "instructions": _as_text_list(node.get("recipeInstructions")),
        "fact": _first_str(node.get("description")),
    }


def _is_usable(recipe: dict) -> bool:
    return bool(recipe.get("title")) and bool(recipe.get("ingredients")) and bool(recipe.get("instructions"))


# ── Claude fallback ──────────────────────────────────────────────────────────────


def _page_text(html: str, max_chars: int) -> str:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup(["script", "style", "noscript", "svg"]):
        tag.decompose()
    text = soup.get_text("\n")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    return "\n".join(lines)[:max_chars]


def _parse_with_claude(html: str) -> dict:
    settings = get_settings()
    if not settings.anthropic_api_key:
        raise ValueError("ANTHROPIC_API_KEY is not configured")

    text = _page_text(html, settings.max_recipe_html_chars)
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key)
    message = client.messages.create(
        model=_MODEL,
        max_tokens=2048,
        system=_SYSTEM,
        messages=[{"role": "user", "content": text}],
    )

    raw_json = message.content[0].text.strip()
    if raw_json.startswith("```"):
        raw_json = raw_json.split("\n", 1)[-1]
        raw_json = raw_json.rsplit("```", 1)[0].strip()

    try:
        parsed = json.loads(raw_json)
    except json.JSONDecodeError as exc:
        logger.warning("url_parser: failed to parse Claude response as JSON")
        raise ValueError(f"Could not parse Claude response as JSON: {exc}") from exc

    return {
        "title": _first_str(parsed.get("title")) or "",
        "category": _first_str(parsed.get("category")),
        "image_url": None,
        "serving_size": _first_str(parsed.get("serving_size")),
        "calories_kcal": _to_float(parsed.get("calories_kcal")),
        "protein_g": _to_float(parsed.get("protein_g")),
        "fat_g": _to_float(parsed.get("fat_g")),
        "carbs_g": _to_float(parsed.get("carbs_g")),
        "ingredients": [s for s in (parsed.get("ingredients") or []) if isinstance(s, str)],
        "instructions": [s for s in (parsed.get("instructions") or []) if isinstance(s, str)],
        "fact": _first_str(parsed.get("fact")),
    }


# ── Entry point ──────────────────────────────────────────────────────────────────


def parse_recipe_url(url: str) -> dict:
    """Fetch `url` and return a `RecipeIn`-shaped dict (a preview, not persisted).

    Raises `ValueError` for an invalid/unsafe URL, an unreachable page, or (in the
    Claude fallback path) a missing API key / unparseable response.
    """
    html = fetch_html(url)

    node = _extract_json_ld_recipe(html)
    if node:
        recipe = _json_ld_to_recipe(node)
        if _is_usable(recipe):
            return recipe
        # JSON-LD present but incomplete (e.g. missing instructions) — fall back
        # to Claude, but keep the JSON-LD image since Claude never returns one.
        fallback = _parse_with_claude(html)
        for key, value in recipe.items():
            if value and not fallback.get(key):
                fallback[key] = value
        return fallback

    return _parse_with_claude(html)
