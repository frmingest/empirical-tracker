"""Rate-limiting tests (ADR-026 F2)."""

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from app import rate_limit as rl
from app.auth import current_user_id
from app.main import app
from app.rate_limit import SlidingWindowLimiter

client = TestClient(app)


def teardown_function() -> None:
    rl._limiter.reset()
    app.dependency_overrides.clear()


# ── unit: sliding window ────────────────────────────────────────────────────────

def test_limiter_allows_up_to_limit_then_blocks():
    lim = SlidingWindowLimiter()
    assert lim.check("k", limit=3, window_seconds=60)
    assert lim.check("k", limit=3, window_seconds=60)
    assert lim.check("k", limit=3, window_seconds=60)
    # Fourth hit in the window is refused.
    assert not lim.check("k", limit=3, window_seconds=60)


def test_limiter_keys_are_independent():
    lim = SlidingWindowLimiter()
    assert lim.check("a", limit=1, window_seconds=60)
    assert not lim.check("a", limit=1, window_seconds=60)
    # A different key (different user) has its own budget.
    assert lim.check("b", limit=1, window_seconds=60)


def test_limiter_evicts_outside_window():
    lim = SlidingWindowLimiter()
    times = iter([0.0, 0.0, 100.0])  # third call is past the 60s window
    with patch("app.rate_limit.time.monotonic", lambda: next(times)):
        assert lim.check("k", limit=1, window_seconds=60)
        assert not lim.check("k", limit=1, window_seconds=60)
        assert lim.check("k", limit=1, window_seconds=60)


# ── integration: dependency returns 429 ─────────────────────────────────────────

@patch("app.food_diary.router.registry.search")
@patch("app.rate_limit.get_settings")
def test_endpoint_throttles_per_user(mock_settings, mock_search):
    mock_settings.return_value = MagicMock(
        rate_limit_standard=120, rate_limit_expensive=2, rate_limit_window_seconds=60
    )
    mock_search.return_value = []
    app.dependency_overrides[current_user_id] = lambda: "u1"

    # The expensive limit is 2; the third call in the window is rejected.
    assert client.get("/food-diary/search?q=egg").status_code == 200
    assert client.get("/food-diary/search?q=egg").status_code == 200
    res = client.get("/food-diary/search?q=egg")
    assert res.status_code == 429
    assert res.headers.get("Retry-After") == "60"
