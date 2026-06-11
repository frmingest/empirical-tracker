"""Calendar-date validation shared by routers that write Postgres ``date`` columns.

Columns like ``logged_on``, ``measured_on``, and ``started_on`` name a *local*
calendar day the user picked — not an instant. If a client sends a full ISO
timestamp instead (e.g. ``2026-06-09T22:00:00Z`` for local midnight CEST on
June 10), Postgres silently truncates it to the **UTC** date and files the row
under the wrong day for any non-UTC user. Reject loudly instead.
"""

from __future__ import annotations

import re
from datetime import date

_CALENDAR_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def validate_calendar_date(value: str) -> str:
    """Require a bare ``YYYY-MM-DD`` calendar date; raise ``ValueError`` otherwise."""
    if not _CALENDAR_DATE.match(value):
        raise ValueError("must be a calendar date in YYYY-MM-DD format")
    try:
        date.fromisoformat(value)
    except ValueError:
        raise ValueError("must be a valid calendar date (YYYY-MM-DD)") from None
    return value
