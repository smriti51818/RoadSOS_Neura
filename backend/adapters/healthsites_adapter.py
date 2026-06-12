"""Healthsites.io adapter — global health facility data.

Healthsites is a Digital Public Good: curated from government imports,
OSM community edits, and direct facility validation.
Particularly strong where OSM is sparse (developing nations).

API docs: https://healthsites.io/api/docs/
Authentication: Free OSM account → API token (healthsites.io/user/api-access/)

Trust score: 4 (curated government imports + OSM validation).
"""

from __future__ import annotations

import logging
import math
from typing import Any

import httpx

from .base_adapter import BaseAdapter

logger = logging.getLogger("uvicorn.error")


class HealthsitesAdapter(BaseAdapter):
    """Fetches global health facilities from the Healthsites.io API.

    Only queries medical categories (hospital, ambulance).
    Returns an empty list gracefully when no API key is configured.
    """

    BASE_URL = "https://healthsites.io/api/v3"
    SUPPORTED_CATEGORIES = frozenset({"hospital", "ambulance", "medical"})

    def __init__(self, api_key: str | None = None) -> None:
        """Initialise the adapter.

        Args:
            api_key: Healthsites.io API token. Free at healthsites.io
                     (requires OSM login). If None the adapter is disabled.
        """
        self.api_key = api_key
        if not api_key:
            logger.warning(
                "[HealthsitesAdapter] No API key — adapter disabled. "
                "Get a free key at healthsites.io (OSM login required)."
            )

    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Fetch health facilities near the given coordinates.

        Only medical categories are queried — other categories return [].
        Returns [] if no API key is configured.
        """
        if not self.api_key:
            return []

        medical = [c for c in categories if c in self.SUPPORTED_CATEGORIES]
        if not medical:
            return []

        try:
            return await self._fetch_facilities(lat, lng, radius_km)
        except Exception as exc:
            logger.error(f"[HealthsitesAdapter] Failed: {exc}")
            return []

    async def _fetch_facilities(
        self,
        lat: float,
        lng: float,
        radius_km: int,
    ) -> list[dict[str, Any]]:
        """Query the Healthsites facilities endpoint using a bounding box.

        Args:
            lat: Centre latitude.
            lng: Centre longitude.
            radius_km: Search radius to derive the bounding box.

        Returns:
            List of normalised service dicts.
        """
        lat_delta = radius_km / 111.0
        lng_delta = radius_km / (
            111.0 * abs(math.cos(math.radians(lat))) + 1e-9
        )
        bbox = (
            f"{lng - lng_delta},{lat - lat_delta},"
            f"{lng + lng_delta},{lat + lat_delta}"
        )

        url = f"{self.BASE_URL}/facilities/"
        params: dict[str, Any] = {
            "api-key": self.api_key,
            "bbox": bbox,
            "format": "json",
            "page_size": 50,
        }

        async with httpx.AsyncClient(timeout=5.0) as client:
            response = await client.get(url, params=params)
            response.raise_for_status()
            data = response.json()

        results: list[dict[str, Any]] = []
        for facility in data.get("results", []):
            parsed = self._parse_facility(facility, lat, lng)
            if parsed is not None:
                results.append(parsed)
        return results

    def _parse_facility(
        self,
        facility: dict[str, Any],
        origin_lat: float,
        origin_lng: float,
    ) -> dict[str, Any] | None:
        """Parse a single Healthsites GeoJSON feature into a service dict.

        Returns None if essential data (name or coordinates) is missing.
        """
        props = facility.get("properties", {})
        name = props.get("name", "").strip()
        if not name:
            return None

        geometry = facility.get("geometry", {})
        coords = geometry.get("coordinates")
        if not coords or len(coords) < 2 or coords[0] is None:
            return None

        # GeoJSON coordinates are [longitude, latitude]
        facility_lng, facility_lat = coords[0], coords[1]

        amenity = props.get("amenity", "hospital")
        category = (
            "hospital"
            if amenity in ("hospital", "clinic", "doctors", "pharmacy")
            else "ambulance"
        )

        phone = props.get("phone") or props.get("contact:phone") or None

        return self._build_result(
            name=name,
            category=category,
            lat=float(facility_lat),
            lng=float(facility_lng),
            phone_primary=phone if phone else None,
            address=None,
            country_code="",  # not returned by API — resolved by LocationResolver
            source="healthsites",
            trust_score=4,
            origin_lat=origin_lat,
            origin_lng=origin_lng,
        )
