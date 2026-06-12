"""Services router — nearby search, emergency numbers, and data quality reports."""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException, Query, Request

from core.database import get_pool

from schemas.service_schemas import (
    EmergencyNumbersResponse,
    NearbyServicesResponse,
    ReportRequest,
    ReportResponse,
    ServiceResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["services"])


# ── Endpoints ─────────────────────────────────────────────────────────────────


@router.get("/nearby", response_model=NearbyServicesResponse)
async def get_nearby_services(
    request: Request,
    lat: float = Query(..., description="User latitude"),
    lng: float = Query(..., description="User longitude"),
    category: str | None = Query(
        None,
        description=(
            "Single category or comma-separated list. "
            "None = all emergency categories. "
            "Options: hospital, police, ambulance, fire, towing, breakdown, puncture."
        ),
    ),
    country_code: str | None = Query(
        None,
        description="ISO 3166-1 alpha-2 country code. None = auto-detect from coordinates.",
    ),
    emergency_mode: bool = Query(
        True,
        description="True = only return trust_score ≥ 3 results.",
    ),
) -> NearbyServicesResponse:
    """Fetch verified emergency services near the user's coordinates.

    Returns services ranked by distance with trust scores.
    Automatically selects the best data sources for the detected country.
    Falls back gracefully to OSM when specialised sources are unavailable.
    """
    # Parse comma-separated categories
    categories: list[str] | None = None
    if category:
        categories = [c.strip() for c in category.split(",") if c.strip()]

    fetcher = request.app.state.service_fetcher
    result = await fetcher.fetch(
        lat=lat,
        lng=lng,
        categories=categories,
        country_code=country_code,
        emergency_mode=emergency_mode,
    )

    # Convert raw dicts → Pydantic response models
    service_responses = [
        ServiceResponse(**s) for s in result["services"]
    ]
    by_category_responses: dict[str, list[ServiceResponse]] = {
        cat: [ServiceResponse(**s) for s in services]
        for cat, services in result["services_by_category"].items()
    }

    return NearbyServicesResponse(
        services=service_responses,
        services_by_category=by_category_responses,
        source=result["source"],
        cached=result["cached"],
        count=result["count"],
        country_code=result["country_code"],
        search_radius_km=result["search_radius_km"],
        fetched_at=result["fetched_at"],
    )


@router.get(
    "/emergency-numbers/{country_code}",
    response_model=EmergencyNumbersResponse,
)
async def get_emergency_numbers(
    country_code: str,
    request: Request,
) -> EmergencyNumbersResponse:
    """Return verified emergency phone numbers for a country.

    Data sourced from local JSON — always available, zero network dependency.
    Falls back to DEFAULT (unified: 112) if the country is not in the database.
    """
    emergency_numbers = getattr(request.app.state, "emergency_numbers", [])
    country_config = getattr(request.app.state, "country_config", {})

    country_upper = country_code.upper()

    # Search the emergency_numbers list (JSON array)
    numbers: dict | None = None
    if isinstance(emergency_numbers, list):
        for entry in emergency_numbers:
            if entry.get("country_code", "").upper() == country_upper:
                numbers = entry
                break
    elif isinstance(emergency_numbers, dict):
        numbers = emergency_numbers.get(country_upper)

    is_default = numbers is None
    if is_default:
        numbers = {
            "country_code": country_upper,
            "country_name": "Unknown",
            "unified": "112",
        }

    # Merge with country_config for India-specific numbers (nhai, traffic, etc.)
    config = country_config.get(country_upper) or country_config.get("DEFAULT") or {}
    config_numbers: dict = config.get("emergency_numbers", {})

    return EmergencyNumbersResponse(
        country_code=country_upper,
        country_name=numbers.get("country_name", "Unknown"),
        police=numbers.get("police") or config_numbers.get("police"),
        ambulance=numbers.get("ambulance") or config_numbers.get("ambulance"),
        fire=numbers.get("fire") or config_numbers.get("fire"),
        unified=numbers.get("unified") or config_numbers.get("unified") or "112",
        women=config_numbers.get("women"),
        nhai=config_numbers.get("nhai"),
        traffic=config_numbers.get("traffic"),
        is_default=is_default,
    )


@router.post("/report", response_model=ReportResponse)
async def report_service(
    body: ReportRequest,
    request: Request,
) -> ReportResponse:
    """Record a data quality report for a service listing.

    Accepted report types: wrong_number, closed, moved, duplicate.
    Reports are logged for the data quality improvement pipeline.
    Supabase persistence added in Module 6.
    """
    now = datetime.now(timezone.utc).isoformat()
    logger.info(
        f"[ServiceReport] id={body.service_id} "
        f"type={body.report_type} at={now}"
    )

    # Persist report to Neon DB — fire and forget
    asyncio.create_task(_write_report(body.service_id, body.report_type))

    return ReportResponse(
        reported=True,
        service_id=body.service_id,
        report_type=body.report_type,
        reported_at=now,
    )


async def _write_report(service_id: str, report_type: str) -> None:
    pool = get_pool()
    if pool is None:
        return
    try:
        async with pool.acquire() as conn:
            await conn.execute(
                "INSERT INTO user_reports (service_id, report_type, reported_at) "
                "VALUES ($1::bigint, $2, NOW())",
                int(service_id),
                report_type,
            )
        logger.info(f"[DB] Report written: service={service_id} type={report_type}")
    except Exception as exc:
        logger.error(f"[DB] Report write error (non-fatal): {exc}")
