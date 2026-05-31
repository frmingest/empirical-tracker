from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.biomarkers.router import router as biomarkers_router
from app.config import get_settings
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


app.include_router(biomarkers_router)
app.include_router(settings_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}


@app.get("/")
def root() -> dict[str, str]:
    return {"app": settings.app_name}
