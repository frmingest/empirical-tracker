from __future__ import annotations

from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.db import bind_request_supabase, make_user_supabase

_bearer = HTTPBearer()


async def current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(_bearer),  # noqa: B008
) -> str:
    """Resolve the authenticated user's id and bind their RLS-scoped DB client.

    Builds a Supabase client scoped to the caller's JWT, validates the token, and
    binds that client for the rest of the request (ADR-026). Every repository
    then queries through it, so Postgres row-level security enforces tenant
    isolation — the service-role key is no longer on the user-data path. Shared by
    every authenticated router so token handling stays in one place.
    """
    token = credentials.credentials
    try:
        client = make_user_supabase(token)
        resp = client.auth.get_user(token)
        if not resp.user:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        bind_request_supabase(client)
        return resp.user.id
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
