"""Offline router — serves decision trees and offline data packs."""

from datetime import datetime, timezone

from fastapi import APIRouter, Request

router = APIRouter(tags=["offline"])


@router.get("/pack/{region_id}")
async def get_offline_pack(region_id: str):
    """Return offline data pack for a region.

    Stub in Module 1 — fully implemented in Module 5.
    Region IDs follow the pattern: {country_code}_{state_code} e.g. IN_MH, IN_KA.
    """
    return {
        "region_id": region_id,
        "services": [],
        "emergency_numbers": {},
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "record_count": 0,
        "note": "Full offline pack implemented in Module 5",
    }


@router.get("/decision-trees")
async def get_decision_trees(request: Request):
    """Return the full offline decision-tree JSON loaded at startup.

    This endpoint is fully implemented — it returns real data.
    The Flutter AI service falls back to this when Gemini is unavailable.
    """
    trees = getattr(request.app.state, "decision_trees", {})
    return trees
