from __future__ import annotations

from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.db import get_supabase

_bearer = HTTPBearer()


async def current_user_id(
    credentials: HTTPAuthorizationCredentials = Security(_bearer),  # noqa: B008
) -> str:
    """Resolve the authenticated user's id from the bearer token.

    Shared by every authenticated router so token handling stays in one place.
    """
    token = credentials.credentials
    try:
        db = get_supabase()
        resp = db.auth.get_user(token)
        if not resp.user:
            raise HTTPException(status_code=401, detail="Invalid or expired token")
        return resp.user.id
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid or expired token") from exc
