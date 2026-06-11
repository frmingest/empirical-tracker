"""Calendar-date validation (app/dates.py).

Columns like ``logged_on`` / ``measured_on`` name a local day. A full ISO
timestamp must be rejected: Postgres would otherwise truncate it to the UTC
date and file the row under the wrong day for non-UTC users (local midnight
CEST arrives as 22:00Z the previous day).
"""

import pytest
from fastapi.testclient import TestClient

from app.auth import current_user_id
from app.dates import validate_calendar_date
from app.main import app

client = TestClient(app)


# ── unit ────────────────────────────────────────────────────────────────────────

def test_accepts_bare_calendar_date():
    assert validate_calendar_date("2026-06-10") == "2026-06-10"


@pytest.mark.parametrize(
    "value",
    [
        "2026-06-09T22:00:00Z",      # the UTC-shifted instant that caused the bug
        "2026-06-10T00:00:00+02:00",
        "2026-06-10 00:00:00",
        "10.06.2026",
        "2026-6-1",                  # missing zero padding
        "20260610",
        "not a date",
        "",
    ],
)
def test_rejects_non_calendar_date_strings(value):
    with pytest.raises(ValueError):
        validate_calendar_date(value)


def test_rejects_impossible_dates():
    with pytest.raises(ValueError):
        validate_calendar_date("2026-02-30")


# ── router integration: a timestamp regression fails loudly (422), never writes ──

def test_body_metrics_rejects_timestamp_measured_on():
    app.dependency_overrides[current_user_id] = lambda: "u-test"
    try:
        resp = client.post(
            "/body-metrics",
            json={"measured_on": "2026-06-09T22:00:00Z", "weight_kg": 80.0},
        )
        assert resp.status_code == 422
    finally:
        app.dependency_overrides.pop(current_user_id, None)


def test_food_diary_rejects_timestamp_logged_on():
    app.dependency_overrides[current_user_id] = lambda: "u-test"
    try:
        resp = client.post(
            "/food-diary",
            json={
                "logged_on": "2026-06-09T22:00:00Z",
                "meal": "dinner",
                "food_name": "Ribeye",
            },
        )
        assert resp.status_code == 422
    finally:
        app.dependency_overrides.pop(current_user_id, None)
