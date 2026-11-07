from fastapi import FastAPI

from app.api.routes.health import router as health_router
from app.api.routes.predict import router as predict_router


app = FastAPI(
    title="Smart Bakery ML Service",
    version="1.0.0",
)

app.include_router(health_router)
app.include_router(predict_router)
