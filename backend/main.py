"""RoadSoS FastAPI backend — entry point."""

import json
import logging
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.middleware.sessions import SessionMiddleware

from core.database import connect as db_connect
from core.database import disconnect as db_disconnect
from core.service_fetcher import ServiceFetcher
from routers import emergency, offline, services

logger = logging.getLogger("uvicorn.error")

DATA_DIR = Path(__file__).parent / "data"


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Load all static data files on startup — fail gracefully if missing."""
    for filename, attr in [
        ("country_config.json", "country_config"),
        ("emergency_numbers.json", "emergency_numbers"),
        ("decision_trees.json", "decision_trees"),
    ]:
        path = DATA_DIR / filename
        try:
            with open(path, encoding="utf-8") as f:
                setattr(app.state, attr, json.load(f))
            logger.info(f"[RoadSoS] Loaded {filename}")
        except FileNotFoundError:
            setattr(app.state, attr, {})
            logger.warning(f"[RoadSoS] {filename} not found — using empty dict")
        except json.JSONDecodeError as exc:
            setattr(app.state, attr, {})
            logger.error(f"[RoadSoS] {filename} is invalid JSON: {exc}")

    # Instantiate ServiceFetcher singleton — stored in app.state for reuse
    try:
        app.state.service_fetcher = ServiceFetcher(
            country_config=app.state.country_config,
            mappls_api_key=os.getenv("MAPPLS_API_KEY"),
            healthsites_api_key=os.getenv("HEALTHSITES_API_KEY"),
            cqc_api_key=os.getenv("CQC_API_KEY"),
        )
        logger.info("[RoadSoS] ServiceFetcher ready")
    except Exception as exc:
        logger.error(f"[RoadSoS] ServiceFetcher init failed: {exc}")
        app.state.service_fetcher = None

    # Connect to Neon DB — non-fatal if NEON_DATABASE_URL is not set
    await db_connect()

    logger.info("[RoadSoS] API startup complete")
    yield

    # Graceful shutdown
    await db_disconnect()
    logger.info("[RoadSoS] API shutdown")


app = FastAPI(
    title="RoadSoS API",
    version="1.0.0",
    description="Road Safety Emergency Response — IIT Madras Hackathon 2026",
    lifespan=lifespan,
)

# Session middleware must be added before CORS
app.add_middleware(
    SessionMiddleware,
    secret_key=os.getenv("SECRET_KEY", "roadsos-dev-secret-change-in-prod"),
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://10.0.2.2:3000",
        "*",  # Permissive for hackathon demo
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers — specific paths registered before parameterised ones
app.include_router(services.router, prefix="/api/services")
app.include_router(emergency.router, prefix="/api/emergency")
app.include_router(offline.router, prefix="/api/offline")


@app.get("/health", tags=["meta"])
async def health_check():
    """Liveness probe — returns status and current UTC timestamp."""
    return {
        "status": "ok",
        "version": "1.0.0",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/", tags=["meta"])
async def root():
    return {
        "app": "RoadSoS API",
        "status": "running",
        "docs": "/docs",
    }


@app.exception_handler(404)
async def not_found_handler(request: Request, exc: Exception):
    return JSONResponse(
        status_code=404,
        content={"error": "Not found", "path": str(request.url.path)},
    )


@app.exception_handler(500)
async def server_error_handler(request: Request, exc: Exception):
    # Never expose tracebacks to clients in production
    logger.error(f"[RoadSoS] 500 on {request.url.path}: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error. Please try again."},
    )
