from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "Empirical Tracker API"
    environment: str = "development"

    # Comma-separated list of allowed CORS origins (the web client).
    cors_origins: str = "http://localhost:3000"

    # Supabase — populated per environment, never committed.
    supabase_url: str = ""
    # Service-role key: bypasses RLS, used only for admin operations (ADR-026).
    supabase_service_key: str = ""
    # Public anon key: used to build per-request, JWT-scoped clients so user-data
    # queries run under RLS rather than as the service role (ADR-026).
    supabase_anon_key: str = ""
    # Project JWT secret (HS256). When set, access tokens are verified locally —
    # signature + expiry + audience — instead of a network round-trip to Supabase
    # Auth on every request (ADR-026 F5). Server-only secret. When unset, auth
    # falls back to the network `auth.get_user` validation.
    supabase_jwt_secret: str = ""

    # Security limits (ADR-026 F3/F4). Caps on attacker-controlled inputs so a
    # single request cannot exhaust memory or amplify LLM spend.
    max_upload_bytes: int = 10 * 1024 * 1024  # 10 MiB — xlsx biomarker imports
    max_xlsx_uncompressed_bytes: int = 200 * 1024 * 1024  # zip-bomb guard
    max_ocr_chars: int = 20_000  # nutrition-label OCR text sent to the LLM

    # Rate limiting (ADR-026 F2). Per-user sliding-window limits, "requests/window
    # seconds". The standard limit covers ordinary endpoints; the expensive limit
    # covers the upload, OCR/LLM, and external-search paths.
    rate_limit_standard: int = 120
    rate_limit_expensive: int = 20
    rate_limit_window_seconds: int = 60

    # USDA FoodData Central — free api.data.gov key, server-only (never exposed
    # to the browser). When unset, the USDA food source degrades gracefully to
    # "unavailable" rather than erroring (ADR-018).
    usda_fdc_api_key: str = ""

    # Anthropic — used by the nutrition-label OCR parser (parse-label endpoint).
    # When unset the endpoint returns a 503 rather than erroring unpredictably.
    anthropic_api_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
