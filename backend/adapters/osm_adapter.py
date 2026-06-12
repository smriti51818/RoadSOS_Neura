"""OSM Overpass adapter — fetches service records from OpenStreetMap.

Trust score: 3 (community verified).
Used as the global fallback for all countries.

Query strategy:
  - Uses `nwr` (node/way/relation) instead of `node` alone.
    In India and most cities, hospitals, police stations and fire brigades are
    mapped as *way* (building outline) or *relation*, not a bare point node.
    `nwr` catches all three types in one round-trip.
  - Uses `out center;` so every way/relation element carries a `center`
    dict with its centroid lat/lon instead of a full geometry blob.
  - Sends query as form data (application/x-www-form-urlencoded) which
    every Overpass instance accepts reliably.

Timeout alignment:
  - Overpass QL [timeout:20]   → server-side computation budget
  - httpx read=22              → wait up to 22 s for the HTTP response
  - ServiceFetcher wrapper     → 28 s asyncio.wait_for (headroom for network)
"""

from __future__ import annotations

import logging
from typing import Any

import httpx

from .base_adapter import BaseAdapter

logger = logging.getLogger("uvicorn.error")

# Primary Overpass endpoint — official instance, rate-limited per IP.
# Switch to a mirror by setting OVERPASS_URL in your .env if this is slow.
OVERPASS_URL = "https://overpass-api.de/api/interpreter"

# httpx timeout config — read must exceed the QL [timeout:] value
OVERPASS_TIMEOUT = httpx.Timeout(connect=5.0, read=22.0, write=5.0, pool=5.0)

# Maps RoadSoS category → Overpass QL filter.
# nwr = node | way | relation — catches building outlines AND point nodes.
CATEGORY_TAGS: dict[str, str] = {
    "hospital":  'nwr["amenity"~"hospital|clinic|doctors"]',
    "police":    'nwr["amenity"="police"]',
    "ambulance": 'nwr["emergency"="ambulance_station"]',
    "fire":      'nwr["amenity"="fire_station"]',
    "towing":    'nwr["shop"="car_repair"]',
    "breakdown": 'nwr["shop"~"car_repair|tyres|car_parts"]',
    "puncture":  'nwr["shop"~"tyres|bicycle|car_repair"]',
}


class OSMAdapter(BaseAdapter):
    """Fetches services from the OpenStreetMap Overpass API.

    Trust score: 3 (community verified).
    Used as the global fallback for all countries.
    """

    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Query Overpass for all requested categories in one request.

        Returns an empty list on timeout or any other error — never raises.
        """
        radius_metres = radius_km * 1000
        query = self._build_overpass_query(lat, lng, radius_metres, categories)
        if query is None:
            return []

        logger.info(f"[OSMAdapter] Query ({radius_km}km):\n{query}")

        try:
            async with httpx.AsyncClient(timeout=OVERPASS_TIMEOUT) as client:
                resp = await client.post(
                    OVERPASS_URL,
                    # Standard form-encoded POST — accepted by every Overpass mirror
                    data={"data": query},
                    headers={"User-Agent": "RoadSoS-App/1.0 (roadsos@hackathon.dev)"},
                )
                resp.raise_for_status()
                elements = resp.json().get("elements", [])

        except httpx.TimeoutException:
            logger.warning("[OSMAdapter] Overpass query timed out")
            return []
        except httpx.HTTPStatusError as exc:
            logger.warning(f"[OSMAdapter] HTTP {exc.response.status_code} from Overpass")
            return []
        except Exception as exc:
            logger.warning(f"[OSMAdapter] Overpass error: {type(exc).__name__}: {exc}")
            return []

        results = self._parse_elements(elements, lat, lng)
        logger.info(
            f"[OSMAdapter] {len(elements)} elements → {len(results)} services"
        )
        return results

    # ── Query builder ──────────────────────────────────────────────────────────

    def _build_overpass_query(
        self,
        lat: float,
        lng: float,
        radius_metres: int,
        categories: list[str],
    ) -> str | None:
        """Build an Overpass QL query string for the requested categories.

        Returns None if no supported categories are requested.

        Uses `out center;` so every way/relation element includes a
        `center` dict — gives us a single representative lat/lon without
        fetching full geometry.
        """
        filters = "\n  ".join(
            f"{CATEGORY_TAGS[c]}(around:{radius_metres},{lat},{lng});"
            for c in categories
            if c in CATEGORY_TAGS
        )
        if not filters:
            return None

        return (
            f"[out:json][timeout:20];\n"
            f"(\n  {filters}\n);\n"
            f"out center;"
        )

    # ── Parser ─────────────────────────────────────────────────────────────────

    def _parse_elements(
        self,
        elements: list[dict[str, Any]],
        origin_lat: float,
        origin_lng: float,
    ) -> list[dict[str, Any]]:
        """Parse raw Overpass elements (node/way/relation) into service dicts.

        Ways and relations carry their centroid in a nested `center` dict;
        nodes carry `lat`/`lon` at the top level.
        """
        results: list[dict[str, Any]] = []
        for el in elements:
            tags = el.get("tags", {})

            # --- resolve coordinates -----------------------------------------
            if el.get("type") == "node":
                el_lat = el.get("lat")
                el_lng = el.get("lon")
            else:
                # way / relation → centroid from `out center;`
                center = el.get("center", {})
                el_lat = center.get("lat")
                el_lng = center.get("lon")

            if el_lat is None or el_lng is None:
                continue

            # --- extract fields -----------------------------------------------
            name = tags.get("name") or tags.get("name:en") or ""
            phone = (
                tags.get("contact:phone")
                or tags.get("phone")
                or tags.get("contact:mobile")
            )
            address = tags.get("addr:full") or tags.get("addr:street")
            category = self._infer_category(tags)

            results.append(
                self._build_result(
                    name=name,
                    category=category,
                    lat=float(el_lat),
                    lng=float(el_lng),
                    phone_primary=phone,
                    address=address,
                    country_code="",   # resolved by LocationResolver
                    source="osm",
                    trust_score=3,
                    origin_lat=origin_lat,
                    origin_lng=origin_lng,
                )
            )
        return results

    # ── Helpers ────────────────────────────────────────────────────────────────

    @staticmethod
    def _infer_category(tags: dict[str, str]) -> str:
        """Infer the RoadSoS category from an Overpass element's tags."""
        amenity   = tags.get("amenity", "")
        emergency = tags.get("emergency", "")
        shop      = tags.get("shop", "")

        if amenity in ("hospital", "clinic", "doctors"):
            return "hospital"
        if amenity == "police":
            return "police"
        if amenity == "fire_station":
            return "fire"
        if emergency == "ambulance_station":
            return "ambulance"
        if shop in ("car_repair", "tyres", "car_parts"):
            return "breakdown"
        return "unknown"
