"""Local JWT verification tests (ADR-026 F5, JWKS/ES256 extension)."""

import asyncio
import time
from unittest.mock import MagicMock, patch

import jwt
import pytest
from cryptography.hazmat.primitives.asymmetric.ec import SECP256K1, generate_private_key
from cryptography.hazmat.backends import default_backend
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


# ── ES256 / JWKS path ────────────────────────────────────────────────────────


def _make_ec_keypair():
    """Return (private_key, public_key) as cryptography objects."""
    from cryptography.hazmat.primitives.asymmetric.ec import SECP256R1
    private_key = generate_private_key(SECP256R1(), default_backend())
    return private_key, private_key.public_key()


def _make_es256_token(private_key, sub="u-ec", exp_delta=3600, aud="authenticated"):
    return jwt.encode(
        {"sub": sub, "aud": aud, "exp": int(time.time()) + exp_delta},
        private_key,
        algorithm="ES256",
    )


def test_es256_valid_token_verified_via_jwks():
    private_key, public_key = _make_ec_keypair()
    token = _make_es256_token(private_key, sub="u-ec-1")

    mock_signing_key = MagicMock()
    mock_signing_key.key = public_key
    mock_jwks_client = MagicMock()
    mock_jwks_client.get_signing_key_from_jwt.return_value = mock_signing_key

    with patch("app.auth._get_jwks_client", return_value=mock_jwks_client):
        uid = _verify_token_local(token)

    assert uid == "u-ec-1"


def test_es256_expired_token_rejected():
    private_key, public_key = _make_ec_keypair()
    token = _make_es256_token(private_key, exp_delta=-10)

    mock_signing_key = MagicMock()
    mock_signing_key.key = public_key
    mock_jwks_client = MagicMock()
    mock_jwks_client.get_signing_key_from_jwt.return_value = mock_signing_key

    with patch("app.auth._get_jwks_client", return_value=mock_jwks_client):
        with pytest.raises(HTTPException) as exc:
            _verify_token_local(token)
    assert exc.value.status_code == 401


def test_es256_wrong_key_rejected():
    private_key, _ = _make_ec_keypair()
    _, wrong_public_key = _make_ec_keypair()
    token = _make_es256_token(private_key)

    mock_signing_key = MagicMock()
    mock_signing_key.key = wrong_public_key
    mock_jwks_client = MagicMock()
    mock_jwks_client.get_signing_key_from_jwt.return_value = mock_signing_key

    with patch("app.auth._get_jwks_client", return_value=mock_jwks_client):
        with pytest.raises(HTTPException) as exc:
            _verify_token_local(token)
    assert exc.value.status_code == 401


def test_es256_no_supabase_url_rejected():
    """ES256 token with no supabase_url → cannot fetch JWKS → 401."""
    private_key, _ = _make_ec_keypair()
    token = _make_es256_token(private_key)

    with patch("app.auth._get_jwks_client", return_value=None):
        with pytest.raises(HTTPException) as exc:
            _verify_token_local(token)
    assert exc.value.status_code == 401


def test_es256_verified_token_is_cached():
    private_key, public_key = _make_ec_keypair()
    token = _make_es256_token(private_key, sub="u-ec-cache")

    mock_signing_key = MagicMock()
    mock_signing_key.key = public_key
    mock_jwks_client = MagicMock()
    mock_jwks_client.get_signing_key_from_jwt.return_value = mock_signing_key

    with patch("app.auth._get_jwks_client", return_value=mock_jwks_client):
        uid = _verify_token_local(token)

    assert uid == "u-ec-cache"
    assert token in auth_module._VERIFIED_TOKENS


@patch("app.auth.make_user_supabase")
def test_current_user_id_uses_es256_without_network(mock_make):
    """ES256 JWKS path resolves user without any auth.get_user call."""
    private_key, public_key = _make_ec_keypair()
    token = _make_es256_token(private_key, sub="u-ec-live")

    mock_signing_key = MagicMock()
    mock_signing_key.key = public_key
    mock_jwks_client = MagicMock()
    mock_jwks_client.get_signing_key_from_jwt.return_value = mock_signing_key

    client = MagicMock()
    mock_make.return_value = client
    creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials=token)

    with patch("app.auth._get_jwks_client", return_value=mock_jwks_client):
        uid = asyncio.run(current_user_id(creds))

    assert uid == "u-ec-live"
    client.auth.get_user.assert_not_called()
