"""NHS Care Quality Commission adapter — UK hospital and ambulance data.

The CQC API (https://api.cqc.org.uk/public/v1) covers every registered
care provider in England and is updated daily.

⚠️  API key status (2024+):
    The CQC gateway now enforces a Subscription-Key header for high-volume
    usage.  Register free at:
    https://developer.cqc.org.uk/

    Without a key this adapter still attempts the call — low-traffic hackathon
    usage typically succeeds.  If 403s persist, set CQC_API_KEY in .env.

Trust score: 5 (government, daily updated).
"""

from __future__ import annotations

import logging
import math
import os
from typing import Any

import httpx

from .base_adapter import BaseAdapter

logger = logging.getLogger("uvicorn.error")


class NHSCQCAdapter(BaseAdapter):
    """Fetches UK health facility data from the NHS CQC API.

    Only activated when the resolved country_code is GB.
    Returns an empty list for any category CQC does not cover
    (police, fire, towing, breakdown, puncture).

    Args:
        api_key: Optional CQC Subscription-Key.  Falls back to the
                 CQC_API_KEY environment variable.  Works without a
                 key on low-traffic deployments.
    """

    BASE_URL = "https://api.cqc.org.uk/public/v1"

    # RoadSoS category → CQC careType parameter value
    # None means CQC does not provide data for this category
    CARE_TYPE_MAP: dict[str, str | None] = {
        "hospital": "Hospital",
        "ambulance": "Ambulance service",
        "fire": None,
        "police": None,
        "towing": None,
        "breakdown": None,
        "puncture": None,
        "helpline": None,
    }

    def __init__(self, api_key: str | None = None) -> None:
        self._api_key: str | None = api_key or os.getenv("CQC_API_KEY")
        if not self._api_key:
            logger.info(
                "[NHSCQCAdapter] No CQC_API_KEY set — running without subscription key. "
                "Register free at https://developer.cqc.org.uk/ if you hit 403 errors."
            )

    # ── Public interface ───────────────────────────────────────────────────────

    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Fetch UK care facilities from the CQC API.

        Filters by bounding box derived from the user's coordinates.
        Only fetches categories that CQC covers (hospital + ambulance).
        """
        supported = [
            c for c in categories
            if self.CARE_TYPE_MAP.get(c) is not None
        ]
        if not supported:
            return []

        results: list[dict[str, Any]] = []

        for category in supported:
            care_type = self.CARE_TYPE_MAP[category]
            if care_type is None:
                continue
            try:
                locations = await self._fetch_by_care_type(
                    lat, lng, radius_km, care_type
                )
                for loc in locations:
                    parsed = self._parse_location(loc, category, lat, lng)
                    if parsed is not None:
                        results.append(parsed)
            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                if status == 403:
                    logger.warning(
                        f"[NHSCQCAdapter] 403 Forbidden for careType={care_type}. "
                        "The CQC API may require a Subscription-Key. "
                        "Set CQC_API_KEY in .env — register free at "
                        "https://developer.cqc.org.uk/"
                    )
                elif status == 429:
                    logger.warning(
                        f"[NHSCQCAdapter] 429 Rate-limited for careType={care_type}. "
                        "Back off or set CQC_API_KEY."
                    )
                else:
                    logger.warning(
                        f"[NHSCQCAdapter] HTTP {status} for careType={care_type}: {exc}"
                    )
            except httpx.TimeoutException:
                logger.warning(
                    f"[NHSCQCAdapter] Timeout fetching careType={care_type}"
                )
            except Exception as exc:
                logger.warning(
                    f"[NHSCQCAdapter] Error fetching category={category}: {exc}"
                )

        return results

    # ── Private helpers ────────────────────────────────────────────────────────

    async def _fetch_by_care_type(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        care_type: str,
    ) -> list[dict[str, Any]]:
        """Fetch registered care locations of a specific CQC careType.

        CQC does not support radius search — we fetch the first page of
        results filtered by care type, then filter by bounding box client-side.
        Cap at 100 records per category to prevent slowdowns.
        """
        url = f"{self.BASE_URL}/locations"
        params: dict[str, Any] = {
            "careType": care_type,
            "perPage": 100,
            "page": 1,
        }
        headers: dict[str, str] = {
            "User-Agent": "RoadSoS-App/1.0 (roadsos@hackathon.dev)",
            "Accept": "application/json",
        }
        if self._api_key:
            headers["Subscription-Key"] = self._api_key

        async with httpx.AsyncClient(timeout=8.0) as client:
            response = await client.get(url, params=params, headers=headers)
            response.raise_for_status()
            data = response.json()

        all_locations = data.get("locations", [])

        # Client-side bounding box filter
        lat_delta = radius_km / 111.0
        lng_delta = radius_km / (111.0 * abs(math.cos(math.radians(lat))) + 1e-9)
        filtered: list[dict[str, Any]] = []
        for loc in all_locations:
            loc_lat = loc.get("onspd_latitude")
            loc_lng = loc.get("onspd_longitude")
            if loc_lat is None or loc_lng is None:
                continue
            if (
                abs(float(loc_lat) - lat) <= lat_delta
                and abs(float(loc_lng) - lng) <= lng_delta
            ):
                filtered.append(loc)

        return filtered

    def _parse_location(
        self,
        location: dict[str, Any],
        category: str,
        origin_lat: float,
        origin_lng: float,
    ) -> dict[str, Any] | None:
        """Parse a CQC location object into a normalised service dict.

        Returns None if the location is missing essential data or is not
        in Registered status.
        """
        if location.get("registrationStatus") != "Registered":
            return None

        name = location.get("name", "").strip()
        if not name:
            return None

        loc_lat = location.get("onspd_latitude")
        loc_lng = location.get("onspd_longitude")
        if not loc_lat or not loc_lng:
            return None

        phone = location.get("mainPhoneNumber")
        address_parts = [
            location.get("postalAddressLine1", ""),
            location.get("postalAddressTownCity", ""),
            location.get("postalCode", ""),
        ]
        address = ", ".join(p.strip() for p in address_parts if p.strip())

        return self._build_result(
            name=name,
            category=category,
            lat=float(loc_lat),
            lng=float(loc_lng),
            phone_primary=phone or None,
            address=address or None,
            country_code="GB",
            source="nhs_cqc",
            trust_score=5,
            origin_lat=origin_lat,
            origin_lng=origin_lng,
        )
