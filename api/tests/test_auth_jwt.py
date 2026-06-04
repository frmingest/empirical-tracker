"""Local JWT verification tests (ADR-026 F5)."""

import asyncio
import time
from unittest.mock import MagicMock, patch

import jwt
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app import auth as auth_module
from app.auth import _verify_token_local, current_user_id

_SECRET = "test-jwt-secret"


def teardown_function() -> None:
    auth_module._VERIFIED_TOKENS.clear()


def _make_token(secret=_SECRET, sub="u-7", exp_delta=3600, aud="authenticated"):
    return jwt.encode(
        {"sub": sub, "aud": aud, "exp": int(time.time()) + exp_delta},
        secret,
        algorithm="HS256",
    )


@patch("app.auth.get_settings")
def test_returns_none_when_no_secret_configured(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret="")
    assert _verify_token_local(_make_token()) is None


@patch("app.auth.get_settings")
def test_valid_token_returns_subject(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    assert _verify_token_local(_make_token(sub="u-42")) == "u-42"


@patch("app.auth.get_settings")
def test_expired_token_rejected(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    with pytest.raises(HTTPException) as exc:
        _verify_token_local(_make_token(exp_delta=-10))
    assert exc.value.status_code == 401


@patch("app.auth.get_settings")
def test_wrong_signature_rejected(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    with pytest.raises(HTTPException) as exc:
        _verify_token_local(_make_token(secret="attacker-secret"))
    assert exc.value.status_code == 401


@patch("app.auth.get_settings")
def test_wrong_audience_rejected(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    with pytest.raises(HTTPException):
        _verify_token_local(_make_token(aud="anon"))


@patch("app.auth.get_settings")
def test_verified_token_is_cached(mock_settings):
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    token = _make_token(sub="u-9")
    assert _verify_token_local(token) == "u-9"
    assert token in auth_module._VERIFIED_TOKENS


@patch("app.auth.make_user_supabase")
@patch("app.auth.get_settings")
def test_current_user_id_uses_local_path_without_network(mock_settings, mock_make):
    """With a JWT secret set, the token is verified locally — no auth.get_user."""
    mock_settings.return_value = MagicMock(supabase_jwt_secret=_SECRET)
    client = MagicMock()
    mock_make.return_value = client
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=_make_token(sub="u-1"))

    uid = asyncio.run(current_user_id(creds))

    assert uid == "u-1"
    client.auth.get_user.assert_not_called()


@patch("app.auth.make_user_supabase")
@patch("app.auth.get_settings")
def test_current_user_id_falls_back_to_network_without_secret(mock_settings, mock_make):
    mock_settings.return_value = MagicMock(supabase_jwt_secret="")
    client = MagicMock()
    client.auth.get_user.return_value = MagicMock(user=MagicMock(id="u-net"))
    mock_make.return_value = client
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="opaque")

    uid = asyncio.run(current_user_id(creds))

    assert uid == "u-net"
    client.auth.get_user.assert_called_once_with("opaque")
