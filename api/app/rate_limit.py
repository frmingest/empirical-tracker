"""In-memory, per-user sliding-window rate limiting (ADR-026 F2).

A public API processing health data needs a throttle on its expensive paths —
uploads, the OCR/LLM endpoint, external search — so a single caller cannot turn
the service into a DoS or cost-amplification vector.

This implementation is deliberately dependency-free and process-local: the API
runs as a single Railway instance at current scale, so an in-memory limiter is
sufficient and avoids a Redis dependency. The limiter is keyed by authenticated
user id, so the throttle is per-account rather than per-IP (every limited
endpoint requires authentication). If the deployment is ever scaled horizontally
this must move to a shared store — noted in ADR-026.
"""

from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import Depends, HTTPException

from app.auth import current_user_id
from app.config import get_settings


class SlidingWindowLimiter:
    """Tracks per-key request timestamps in a fixed time window.

    Thread-safe: FastAPI runs sync dependencies in a worker threadpool, so the
    shared buckets are guarded by a lock.
    """

    def __init__(self) -> None:
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = threading.Lock()

    def check(self, key: str, limit: int, window_seconds: float) -> bool:
        """Record a hit for ``key``; return ``True`` if it is within ``limit``."""
        now = time.monotonic()
        cutoff = now - window_seconds
        with self._lock:
            bucket = self._hits[key]
            while bucket and bucket[0] <= cutoff:
                bucket.popleft()
            if len(bucket) >= limit:
                return False
            bucket.append(now)
            return True

    def reset(self) -> None:
        """Clear all state (used by tests)."""
        with self._lock:
            self._hits.clear()


_limiter = SlidingWindowLimiter()


def rate_limit(bucket: str, *, expensive: bool = False):
    """Build a FastAPI dependency enforcing a per-user rate limit.

    ``bucket`` namespaces the limit so different endpoints do not share a budget.
    ``expensive`` selects the stricter limit for upload/LLM/search paths. The
    dependency reuses the ``current_user_id`` result (FastAPI caches it within a
    request), so it both authenticates and throttles, and returns the user id so
    it can stand in for the auth dependency at the call site.
    """

    def _dependency(user_id: str = Depends(current_user_id)) -> str:  # noqa: B008
        settings = get_settings()
        limit = settings.rate_limit_expensive if expensive else settings.rate_limit_standard
        key = f"{bucket}:{user_id}"
        if not _limiter.check(key, limit, settings.rate_limit_window_seconds):
            raise HTTPException(
                status_code=429,
                detail="Too many requests — please slow down and try again shortly.",
                headers={"Retry-After": str(settings.rate_limit_window_seconds)},
            )
        return user_id

    return _dependency
