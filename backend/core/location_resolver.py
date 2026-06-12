"""Geo-adaptive location resolver — maps GPS coordinates to a country config."""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Any

import httpx

logger = logging.getLogger("uvicorn.error")

NOMINATIM_URL = "https://nominatim.openstreetmap.org/reverse"
NOMINATIM_TIMEOUT = 5  # seconds
NOMINATIM_USER_AGENT = "RoadSoS-App/1.0 (roadsos@hackathon.dev)"

DATA_DIR = Path(__file__).parent.parent / "data"


class LocationResolver:
    """Resolves GPS coordinates to a country config entry.

    Uses Nominatim for online reverse geocoding.
    Falls back to DEFAULT config if Nominatim is unavailable.
    """

    def __init__(
        self,
        country_config: dict[str, Any] | None = None,
    ) -> None:
        """Initialise the resolver.

        Args:
            country_config: Pre-loaded country config dict (e.g. from
                            app.state).  When None the config is loaded
                            from the bundled JSON file.
        """
        if country_config is not None:
            self._country_config: dict[str, Any] = country_config
            return

        config_path = DATA_DIR / "country_config.json"
        try:
            with open(config_path, encoding="utf-8") as f:
                self._country_config = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError) as exc:
            logger.warning(f"[LocationResolver] Could not load country_config.json: {exc}")
            self._country_config = {}

    async def resolve(self, lat: float, lng: float) -> dict[str, Any]:
        """Resolve coordinates to a full country context dict.

        Returns a dict with:
            country_code, country_name, state, city,
            is_rural, urban_radius_km, rural_radius_km,
            map_provider, data_sources
        """
        country_code = "IN"
        country_name = "India"
        state: str | None = None
        city: str | None = None

        try:
            async with httpx.AsyncClient(timeout=NOMINATIM_TIMEOUT) as client:
                resp = await client.get(
                    NOMINATIM_URL,
                    params={"lat": lat, "lon": lng, "format": "json"},
                    headers={"User-Agent": NOMINATIM_USER_AGENT},
                )
            resp.raise_for_status()
            data = resp.json()
            country_code = self._extract_country_code(data)
            country_name = data.get("address", {}).get("country", country_name)
            state = data.get("address", {}).get("state")
            city = (
                data.get("address", {}).get("city")
                or data.get("address", {}).get("town")
                or data.get("address", {}).get("village")
            )
        except httpx.TimeoutException:
            logger.warning(
                f"[LocationResolver] Nominatim timeout for ({lat}, {lng}) — using DEFAULT"
            )
        except Exception as exc:
            logger.warning(
                f"[LocationResolver] Nominatim error for ({lat}, {lng}): {exc} — using DEFAULT"
            )

        config = self.get_config(country_code)
        is_rural = False  # TODO Module 2: population density detection

        return {
            "country_code": country_code,
            "country_name": country_name,
            "state": state,
            "city": city,
            "is_rural": is_rural,
            "urban_radius_km": config.get("urban_radius_km", 10),
            "rural_radius_km": config.get("rural_radius_km", 100),
            "map_provider": config.get("map_provider", "osm"),
            "data_sources": config.get("data_sources", ["osm"]),
        }

    def get_config(self, country_code: str) -> dict[str, Any]:
        """Return the config for [country_code], falling back to DEFAULT."""
        return (
            self._country_config.get(country_code.upper())
            or self._country_config.get("DEFAULT")
            or {
                "map_provider": "osm",
                "data_sources": ["osm"],
                "urban_radius_km": 10,
                "rural_radius_km": 100,
            }
        )

    def get_search_radius(self, country_code: str, is_rural: bool) -> int:
        """Return the appropriate search radius in km for the context."""
        config = self.get_config(country_code)
        if is_rural:
            return int(config.get("rural_radius_km", 100))
        return int(config.get("urban_radius_km", 10))

    def _extract_country_code(self, nominatim_response: dict[str, Any]) -> str:
        """Extract ISO 3166-1 alpha-2 country code from a Nominatim JSON response."""
        try:
            code = nominatim_response.get("address", {}).get("country_code", "")
            return code.upper() if code else "IN"
        except Exception:
            return "IN"
