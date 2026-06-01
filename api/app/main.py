from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware

from app.account.router import router as account_router
from app.biomarkers.router import router as biomarkers_router
from app.config import get_settings
from app.diet_events.router import router as diet_events_router
from app.food_diary.router import router as food_diary_router
from app.meal_plans.router import router as meal_plans_router
from app.settings.router import router as settings_router

settings = get_settings()

app = FastAPI(title=settings.app_name)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    """Attach baseline security headers to every response.

    This API only ever returns JSON (and the GDPR export download); it serves no
    HTML, scripts, or frames, so the policy can be strict: deny embedding, forbid
    MIME sniffing, send no referrer, and lock the CSP down to nothing by default.
    """
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Strict-Transport-Security"] = "max-age=63072000; includeSubDomains"
    response.headers["Content-Security-Policy"] = "default-src 'none'; frame-ancestors 'none'"
    return response


app.include_router(biomarkers_router)
app.include_router(settings_router)
app.include_router(diet_events_router)
app.include_router(food_diary_router)
app.include_router(meal_plans_router)
app.include_router(account_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}


@app.get("/")
def root() -> dict[str, str]:
    return {"app": settings.app_name}
