from functools import lru_cache

from supabase import Client, create_client

from app.config import get_settings


@lru_cache
def get_supabase() -> Client:
    """Service-role Supabase client for server-side access.

    Returns None-like behaviour is avoided: callers should only invoke this once
    credentials are configured (Sprint 1+). In Sprint 0 the app boots without it.
    """
    settings = get_settings()
    if not settings.supabase_url or not settings.supabase_service_key:
        raise RuntimeError(
            "Supabase credentials are not configured. Set SUPABASE_URL and "
            "SUPABASE_SERVICE_KEY in the environment."
        )
    return create_client(settings.supabase_url, settings.supabase_service_key)
