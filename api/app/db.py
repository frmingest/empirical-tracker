from __future__ import annotations

import contextvars
from functools import lru_cache

from app.config import get_settings
from supabase import Client, create_client

# Per-request, JWT-authenticated client. The authentication dependency binds
# this at the start of every authenticated request so that every repository
# query runs *as the user* and Postgres row-level security
# (`auth.uid() = user_id`) enforces tenant isolation in the database itself —
# not merely in application-layer `.eq("user_id", ...)` filters (ADR-026).
_request_client: contextvars.ContextVar[Client | None] = contextvars.ContextVar(
    "request_supabase_client", default=None
)


@lru_cache
def get_service_supabase() -> Client:
    """Service-role Supabase client. **Bypasses RLS** — reserved for genuinely
    administrative operations (e.g. removing an auth user during account
    erasure). Never use it for ordinary user-data reads/writes: routing those
    through the service role is exactly the RLS bypass ADR-026 removes.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError(
            "Supabase service credentials are not configured. Set SUPABASE_URL "
            "and SUPABASE_SERVICE_KEY in the environment."
        )
    return create_client(settings.supabase_url, settings.supabase_service_key)


def make_user_supabase(access_token: str) -> Client:
    """Build a Supabase client scoped to the caller's JWT.

    The public anon key is the ``apikey``; the user's access token is the bearer.
    PostgREST therefore executes every query as that user, so RLS is enforced by
    Postgres — application-layer `user_id` filters become defence-in-depth rather
    than the sole isolation boundary.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_anon_key:
        raise RuntimeError(
            "Supabase anon credentials are not configured. Set SUPABASE_URL "
            "and SUPABASE_ANON_KEY in the environment."
        )
    client = create_client(settings.supabase_url, settings.supabase_anon_key)
    client.postgrest.auth(access_token)
    return client


def bind_request_supabase(client: Client) -> None:
    """Bind the per-request, RLS-scoped client for the current request context."""
    _request_client.set(client)


def get_supabase() -> Client:
    """Return the request-scoped, RLS-enforcing client for user-data access.

    **Fails closed:** if no client is bound — i.e. the request did not pass
    through the authentication dependency — this raises instead of silently
    falling back to a service-role client. That property is the point: a new
    endpoint cannot accidentally read or write user data with RLS bypassed.
    """
    client = _request_client.get()
    if client is None:
        raise RuntimeError(
            "No authenticated Supabase client is bound for this request. "
            "User-data access must go through the authentication dependency "
            "(app.auth.current_user_id)."
        )
    return client
