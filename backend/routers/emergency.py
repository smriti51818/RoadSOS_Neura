"""Emergency router — session lifecycle and location ping endpoints.

All writes go to Neon DB via the asyncpg pool in core.database.
Writes are non-blocking (asyncio.create_task) so the Flutter client
gets its response immediately without waiting for the database.
"""

import asyncio
import json
import logging
import uuid
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException

from core.database import get_pool
from schemas.emergency_schemas import (
    EmergencyPingRequest,
    EmergencyPingResponse,
    EmergencyResolveRequest,
    EmergencyResolveResponse,
    EmergencyStartRequest,
    EmergencyStartResponse,
)

logger = logging.getLogger(__name__)

router = APIRouter(tags=["emergency"])

# ── SQL ────────────────────────────────────────────────────────────────────────

_INSERT_SESSION = """
INSERT INTO emergency_sessions
    (session_id, emergency_type, victim_type,
     lat, lng, country_code, victim_count, victim_details, user_phone,
     is_active, started_at, updated_at)
VALUES
    ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9, TRUE, NOW(), NOW())
ON CONFLICT (session_id) DO UPDATE
    SET emergency_type = EXCLUDED.emergency_type,
        victim_type    = EXCLUDED.victim_type,
        lat            = EXCLUDED.lat,
        lng            = EXCLUDED.lng,
        is_active      = TRUE,
        updated_at     = NOW()
"""

_INSERT_PING = """
INSERT INTO location_pings (session_id, lat, lng, accuracy_m, pinged_at)
VALUES ($1, $2, $3, $4, NOW())
"""

_RESOLVE_SESSION = """
UPDATE emergency_sessions
   SET is_active   = FALSE,
       resolved_at = NOW(),
       updated_at  = NOW()
 WHERE session_id  = $1
"""

# ── Endpoints ──────────────────────────────────────────────────────────────────


@router.post("/start", response_model=EmergencyStartResponse)
async def start_emergency(body: EmergencyStartRequest) -> EmergencyStartResponse:
    """Open a new emergency session and return a session ID.

    The Neon DB write is fire-and-forget so the Flutter client is never
    blocked on database latency.
    """
    session_id = str(uuid.uuid4())

    logger.info(
        f"[Emergency] START — type={body.emergency_type} "
        f"victim={body.victim_type} "
        f"lat={body.lat:.4f} lng={body.lng:.4f} "
        f"session={session_id}"
    )

    priority_cats = body.priority_categories

    if body.has_pediatric_victims:
        logger.warning(f"[Emergency] PAEDIATRIC alert — session={session_id}")
    if body.has_trapped_victims:
        logger.warning(f"[Emergency] TRAPPED victim — session={session_id}")

    # Write to Neon — fire and forget, never blocks the response
    asyncio.create_task(_write_session(
        session_id=session_id,
        emergency_type=body.emergency_type,
        victim_type=body.victim_type,
        lat=body.lat,
        lng=body.lng,
        country_code=getattr(body, "country_code", "IN") or "IN",
        victim_count=body.victim_count,
        victim_details=_serialise_victims(body),
        user_phone=getattr(body, "user_phone", None),
    ))

    return EmergencyStartResponse(
        session_id=session_id,
        status="active",
        message="Emergency recorded. Help is coming.",
        priority_categories=priority_cats,
        has_pediatric_alert=body.has_pediatric_victims,
        has_trapped_alert=body.has_trapped_victims,
        has_senior_alert=body.has_senior_victims,
    )


@router.post("/ping", response_model=EmergencyPingResponse)
async def ping_emergency(body: EmergencyPingRequest) -> EmergencyPingResponse:
    """Receive a location update for an active emergency session."""
    if not body.session_id:
        raise HTTPException(status_code=422, detail="session_id must not be empty")

    now = datetime.now(timezone.utc).isoformat()
    logger.info(
        f"[Emergency] PING — session={body.session_id} "
        f"lat={body.lat:.4f} lng={body.lng:.4f} "
        f"accuracy={body.accuracy_m}m"
    )

    asyncio.create_task(_write_ping(
        session_id=body.session_id,
        lat=body.lat,
        lng=body.lng,
        accuracy_m=body.accuracy_m,
    ))

    return EmergencyPingResponse(
        received=True,
        pinged_at=now,
        session_id=body.session_id,
    )


@router.post("/resolve", response_model=EmergencyResolveResponse)
async def resolve_emergency(body: EmergencyResolveRequest) -> EmergencyResolveResponse:
    """Mark an emergency session as resolved."""
    if not body.session_id:
        raise HTTPException(status_code=422, detail="session_id must not be empty")

    now = datetime.now(timezone.utc).isoformat()
    logger.info(f"[Emergency] RESOLVE — session={body.session_id}")

    asyncio.create_task(_resolve_session(body.session_id))

    return EmergencyResolveResponse(
        resolved=True,
        session_id=body.session_id,
        resolved_at=now,
    )


# ── DB helpers (never raise — failures are logged and swallowed) ───────────────

async def _write_session(
    *,
    session_id: str,
    emergency_type: str,
    victim_type: str,
    lat: float,
    lng: float,
    country_code: str,
    victim_count: Optional[int],
    victim_details: Optional[str],
    user_phone: Optional[str],
) -> None:
    pool = get_pool()
    if pool is None:
        logger.debug("[DB] No pool — session write skipped")
        return
    try:
        async with pool.acquire() as conn:
            await conn.execute(
                _INSERT_SESSION,
                session_id, emergency_type, victim_type,
                lat, lng, country_code, victim_count, victim_details, user_phone,
            )
        logger.info(f"[DB] Session written to Neon: {session_id}")
    except Exception as exc:
        logger.error(f"[DB] Session write error (non-fatal): {exc}")


async def _write_ping(
    *,
    session_id: str,
    lat: float,
    lng: float,
    accuracy_m: Optional[float],
) -> None:
    pool = get_pool()
    if pool is None:
        return
    try:
        async with pool.acquire() as conn:
            await conn.execute(_INSERT_PING, session_id, lat, lng, accuracy_m)
        logger.debug(f"[DB] Ping written for {session_id}")
    except Exception as exc:
        logger.error(f"[DB] Ping write error (non-fatal): {exc}")


async def _resolve_session(session_id: str) -> None:
    pool = get_pool()
    if pool is None:
        return
    try:
        async with pool.acquire() as conn:
            await conn.execute(_RESOLVE_SESSION, session_id)
        logger.info(f"[DB] Session resolved in Neon: {session_id}")
    except Exception as exc:
        logger.error(f"[DB] Resolve error (non-fatal): {exc}")


def _serialise_victims(body: EmergencyStartRequest) -> Optional[str]:
    """Convert victim_details to a JSON string for the jsonb column."""
    try:
        details = getattr(body, "victim_details", None)
        if not details:
            return None
        if hasattr(details[0], "model_dump"):
            return json.dumps([d.model_dump() for d in details])
        return json.dumps([dict(d) for d in details])
    except Exception:
        return None
