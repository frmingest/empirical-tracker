from __future__ import annotations

import logging
import time

import jwt
from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import get_settings
from app.db import bind_request_supabase, make_user_supabase

logger = logging.getLogger(__name__)

_bearer = HTTPBearer()

# Supabase access tokens carry this audience and are signed HS256 with the
# project JWT secret.
_JWT_AUDIENCE = "authenticated"
_JWT_ALGORITHMS = ["HS256"]

# Short-lived cache of locally-verified tokens → (user_id, exp). Avoids
# re-verifying the signature of the same token on back-to-back requests. Bounded
# so a flood of distinct tokens cannot grow it without limit.
_VERIFIED_TOKENS: dict[str, tuple[str, float]] = {}
_VERIFIED_TOKENS_MAX = 1024


def _verify_token_local(token: str) -> str | None:
    """Verify a Supabase access token locally and return its subject (user id).

    Returns ``None`` when local verification is not configured (no JWT secret),
    so the caller can fall back to network validation. Raises on a token that is
    present-but-invalid (bad signature, expired, wrong audience) so an attacker
    cannot downgrade to the network path with a forged token.
    """
    settings = get_settings()
    secret = settings.supabase_jwt_secret
    if not secret:
        return None

    cached = _VERIFIED_TOKENS.get(token)
    if cached is not None:
        user_id, exp = cached
        if exp > time.time():
            return user_id
        _VERIFIED_TOKENS.pop(token, None)

    try:
        claims = jwt.decode(
            token,
            secret,
            algorithms=_JWT_ALGORITHMS,
            audience=_JWT_AUDIENCE,
        )
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc

    user_id = claims.get("sub")
    if not user_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")

    exp = float(claims.get("exp", 0))
    if len(_VERIFIED_TOKENS) >= _VERIFIED_TOKENS_MAX:
        _VERIFIED_TOKENS.clear()
    _VERIFIED_TOKENS[token] = (user_id, exp)
    return user_id


async def current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(_bearer),  # noqa: B008
) -> str:
    """Resolve the authenticated user's id and bind their RLS-scoped DB client.

    Builds a Supabase client scoped to the caller's JWT and binds it for the rest
    of the request (ADR-026 F1). Every repository then queries through it, so
    Postgres row-level security enforces tenant isolation.

    The token is verified locally (signature + expiry + audience) when a JWT
    secret is configured (ADR-026 F5) — no network round-trip — and otherwise
    falls back to validating against Supabase Auth. Either way the same RLS-scoped
    client is bound for the request.
    """
    token = credentials.credentials
    try:
        client = make_user_supabase(token)

        user_id = _verify_token_local(token)
        if user_id is None:
            # No JWT secret configured: validate against Supabase Auth.
            resp = client.auth.get_user(token)
            if not resp.user:
                raise HTTPException(status_code=401, detail="Invalid or expired token")
            user_id = resp.user.id

        bind_request_supabase(client)
        return user_id
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
