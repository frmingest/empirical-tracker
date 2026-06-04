"""Tests for the RLS-on-the-API-path data access layer (ADR-026).

These guard the security property that user-data queries run through a
per-request, JWT-scoped Supabase client (so Postgres RLS is enforced) and that
the layer *fails closed* when no such client is bound.
"""

import asyncio
from unittest.mock import MagicMock, patch

import pytest
from fastapi.security import HTTPAuthorizationCredentials

from app import db as db_module
from app.auth import current_user_id


def teardown_function() -> None:
    # Keep the request-scoped client from leaking between tests.
    db_module._request_client.set(None)


def test_get_supabase_fails_closed_when_unbound():
    # A request that never passed through the auth dependency must NOT silently
    # receive a service-role client — it raises instead.
    db_module._request_client.set(None)
    with pytest.raises(RuntimeError, match="No authenticated Supabase client"):
        db_module.get_supabase()


def test_bind_and_get_request_client_roundtrip():
    sentinel = object()
    db_module.bind_request_supabase(sentinel)
    assert db_module.get_supabase() is sentinel


@patch("app.db.create_client")
@patch("app.db.get_settings")
def test_make_user_supabase_scopes_client_to_jwt(mock_settings, mock_create):
    mock_settings.return_value = MagicMock(
        supabase_url="https://proj.supabase.co", supabase_anon_key="anon.jwt.key"
    )
    client = MagicMock()
    mock_create.return_value = client

    out = db_module.make_user_supabase("user-access-token")

    # Built with the public anon key, then re-authed to the user's JWT so
    # PostgREST runs queries as the user and RLS applies.
    mock_create.assert_called_once_with("https://proj.supabase.co", "anon.jwt.key")
    client.postgrest.auth.assert_called_once_with("user-access-token")
    assert out is client


@patch("app.db.get_settings")
def test_make_user_supabase_requires_anon_key(mock_settings):
    mock_settings.return_value = MagicMock(
        supabase_url="https://proj.supabase.co", supabase_anon_key=""
    )
    with pytest.raises(RuntimeError, match="anon credentials"):
        db_module.make_user_supabase("user-access-token")


@patch("app.auth.make_user_supabase")
def test_current_user_id_binds_the_rls_scoped_client(mock_make):
    client = MagicMock()
    client.auth.get_user.return_value = MagicMock(user=MagicMock(id="u-42"))
    mock_make.return_value = client
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="tok")

    async def _run():
        uid = await current_user_id(creds)
        # Within the same request context, repositories resolve to the very
        # client that was validated against the caller's token.
        return uid, db_module.get_supabase()

    uid, bound = asyncio.run(_run())
    assert uid == "u-42"
    assert bound is client
    mock_make.assert_called_once_with("tok")


@patch("app.auth.make_user_supabase")
def test_current_user_id_rejects_invalid_token(mock_make):
    client = MagicMock()
    client.auth.get_user.return_value = MagicMock(user=None)
    mock_make.return_value = client
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="bad")

    from fastapi import HTTPException

    with pytest.raises(HTTPException) as exc:
        asyncio.run(current_user_id(creds))
    assert exc.value.status_code == 401
