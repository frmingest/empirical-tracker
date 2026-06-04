from __future__ import annotations

import logging
import time
from threading import Lock

import jwt
from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jwt import PyJWKClient, PyJWKClientError

from app.config import get_settings
from app.db import bind_request_supabase, make_user_supabase

logger = logging.getLogger(__name__)

_bearer = HTTPBearer()

_JWT_AUDIENCE = "authenticated"

# Short-lived cache of locally-verified tokens → (user_id, exp). Avoids
# re-verifying the same token on back-to-back requests. Bounded so a flood of
# distinct tokens cannot grow it without limit.
_VERIFIED_TOKENS: dict[str, tuple[str, float]] = {}
_VERIFIED_TOKENS_MAX = 1024

# JWKS client is created lazily (needs supabase_url at runtime) and shared
# across requests.  PyJWKClient handles its own key cache + TTL internally.
_jwks_client: PyJWKClient | None = None
_jwks_lock = Lock()


def _get_jwks_client() -> PyJWKClient | None:
    """Return a lazily-initialised JWKS client, or None if supabase_url is unset."""
    global _jwks_client
    if _jwks_client is not None:
        return _jwks_client
    with _jwks_lock:
        if _jwks_client is not None:
            return _jwks_client
        url = get_settings().supabase_url
        if not url:
            return None
        jwks_uri = url.rstrip("/") + "/auth/v1/.well-known/jwks.json"
        # cache_keys=True keeps fetched keys in memory; lifespan=3600 refreshes
        # them hourly so a rotated key is picked up within one hour.
        _jwks_client = PyJWKClient(jwks_uri, cache_keys=True, lifespan=3600)
        logger.info("JWKS client initialised: %s", jwks_uri)
        return _jwks_client


def _verify_token_local(token: str) -> str | None:
    """Verify a Supabase access token locally and return its subject (user id).

    Verification order:
      1. ES256 via JWKS (preferred — no shared secret required)
      2. HS256 via SUPABASE_JWT_SECRET (legacy / self-hosted)
      3. Returns None → caller falls back to Supabase Auth network call

    Raises HTTPException(401) on a present-but-invalid token so an attacker
    cannot downgrade to the network path with a forged token.
    """
    # --- token cache (algorithm-agnostic) -----------------------------------
    cached = _VERIFIED_TOKENS.get(token)
    if cached is not None:
        user_id, exp = cached
        if exp > time.time():
            return user_id
        _VERIFIED_TOKENS.pop(token, None)

    # Peek at the header to route to the right verifier without a full decode.
    # Non-JWT opaque tokens (e.g. Supabase legacy tokens) can't be parsed here;
    # fall through to the network path rather than refusing outright.
    try:
        header = jwt.get_unverified_header(token)
    except jwt.DecodeError:
        return None

    alg = header.get("alg", "")

    # --- path 1: ES256 via JWKS ---------------------------------------------
    if alg == "ES256":
        client = _get_jwks_client()
        if client is None:
            # No supabase_url configured — cannot fetch JWKS.
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        try:
            signing_key = client.get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                signing_key.key,
                algorithms=["ES256"],
                audience=_JWT_AUDIENCE,
            )
        except (PyJWKClientError, jwt.PyJWTError) as exc:
            raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
        return _cache_and_return(token, claims)

    # --- path 2: HS256 via shared secret ------------------------------------
    if alg == "HS256":
        secret = get_settings().supabase_jwt_secret
        if not secret:
            return None  # secret not configured → fall through to network
        try:
            claims = jwt.decode(
                token,
                secret,
                algorithms=["HS256"],
                audience=_JWT_AUDIENCE,
            )
        except jwt.PyJWTError as exc:
            raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
        return _cache_and_return(token, claims)

    # Unknown algorithm — refuse rather than silently skipping verification.
    raise HTTPException(status_code=401, detail="Invalid or expired token")


def _cache_and_return(token: str, claims: dict) -> str:
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

    Builds a Supabase client scoped to the caller's JWT and binds it for the
    rest of the request (ADR-026 F1). Every repository then queries through it,
    so Postgres RLS enforces tenant isolation.

    Token verification order (ADR-026 F5, extended with JWKS/ES256):
      1. ES256 via Supabase JWKS endpoint (preferred, no shared secret needed)
      2. HS256 via SUPABASE_JWT_SECRET (legacy / self-hosted deployments)
      3. Network call to Supabase Auth (fallback when neither is configured)
    """
    token = credentials.credentials
    try:
        client = make_user_supabase(token)

        user_id = _verify_token_local(token)
        if user_id is None:
            # Neither JWKS nor JWT secret available: validate via Supabase Auth.
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
