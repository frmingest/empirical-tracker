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
    supabase_service_key: str = ""

    # USDA FoodData Central — free api.data.gov key, server-only (never exposed
    # to the browser). When unset, the USDA food source degrades gracefully to
    # "unavailable" rather than erroring (ADR-018).
    usda_fdc_api_key: str = ""

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
