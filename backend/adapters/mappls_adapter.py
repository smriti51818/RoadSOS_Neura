"""Mappls (MapMyIndia) adapter — India-specific nearby service search.

Trust score: 4 — government-backed commercial API.
Used as the primary source for all India queries.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import httpx

from .base_adapter import BaseAdapter

logger = logging.getLogger("uvicorn.error")

MAPPLS_NEARBY_URL = (
    "https://apis.mappls.com/advancedmaps/v1/{api_key}/nearby_search"
)
MAPPLS_TIMEOUT = 5.0  # seconds

# Maps RoadSoS category → Mappls keyword search string
CATEGORY_KEYWORDS: dict[str, str] = {
    "hospital": "hospital,clinic,medical",
    "police": "police station",
    "ambulance": "ambulance",
    "fire": "fire station",
    "towing": "vehicle towing,car towing",
    "breakdown": "car repair,vehicle repair",
    "puncture": "tyre shop,puncture repair",
}


class MapplsAdapter(BaseAdapter):
    """Fetches services from the Mappls Nearby Search API.

    Accepts api_key as a constructor argument; falls back to the
    MAPPLS_API_KEY environment variable if not supplied.
    Returns an empty list immediately if no key is available.
    """

    def __init__(self, api_key: str | None = None) -> None:
        self._api_key: str | None = api_key or os.getenv("MAPPLS_API_KEY")
        if not self._api_key:
            logger.warning(
                "[MapplsAdapter] No API key provided — adapter disabled. "
                "Set MAPPLS_API_KEY env var or pass api_key to constructor."
            )

    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Fetch nearby services for each category from the Mappls API.

        Sends one request per category and merges results.
        Returns an empty list if the API key is missing or any request fails.
        """
        if not self._api_key:
            return []

        results: list[dict[str, Any]] = []
        radius_metres = radius_km * 1000

        for category in categories:
            keywords = CATEGORY_KEYWORDS.get(category)
            if not keywords:
                continue

            try:
                places = await self._fetch_category(
                    lat, lng, radius_metres, keywords
                )
            except Exception as exc:
                logger.warning(
                    f"[MapplsAdapter] Error for category={category}: {exc}"
                )
                continue

            for place in places:
                place_lat = place.get("latitude")
                place_lng = place.get("longitude")
                if place_lat is None or place_lng is None:
                    continue

                results.append(
                    self._build_result(
                        name=place.get("placeName", ""),
                        category=category,
                        lat=float(place_lat),
                        lng=float(place_lng),
                        phone_primary=place.get("phone"),
                        address=place.get("placeAddress"),
                        country_code="IN",
                        source="mappls",
                        trust_score=4,
                        origin_lat=lat,
                        origin_lng=lng,
                    )
                )

        return results

    async def _fetch_category(
        self,
        lat: float,
        lng: float,
        radius_metres: int,
        keywords: str,
    ) -> list[dict[str, Any]]:
        """Call Mappls nearby search for a single keyword set."""
        url = MAPPLS_NEARBY_URL.format(api_key=self._api_key)
        params = {
            "keywords": keywords,
            "refLocation": f"{lat},{lng}",
            "radius": radius_metres,
            "region": "IND",
        }
        async with httpx.AsyncClient(timeout=MAPPLS_TIMEOUT) as client:
            resp = await client.get(url, params=params)
            resp.raise_for_status()
        return resp.json().get("suggestedLocations", [])
