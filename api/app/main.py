from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

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


app.include_router(biomarkers_router)
app.include_router(settings_router)
app.include_router(diet_events_router)
app.include_router(food_diary_router)
app.include_router(meal_plans_router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "environment": settings.environment}


@app.get("/")
def root() -> dict[str, str]:
    return {"app": settings.app_name}
