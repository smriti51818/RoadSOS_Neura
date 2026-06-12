"""Abstract base adapter — all data source adapters extend this class."""

from __future__ import annotations

import math
from abc import ABC, abstractmethod
from typing import Any


class BaseAdapter(ABC):
    """Abstract base for all service data adapters (OSM, Mappls, HDX, etc.).

    Every concrete adapter must implement :meth:`fetch` and return a list of
    dicts with the required keys defined in :meth:`_build_result`.
    """

    @abstractmethod
    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Fetch nearby services from the data source.

        Args:
            lat: Origin latitude.
            lng: Origin longitude.
            radius_km: Search radius in kilometres.
            categories: List of service category strings to fetch.

        Returns:
            List of result dicts with the keys defined by :meth:`_build_result`.
        """
        ...

    def _haversine(
        self,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float,
    ) -> float:
        """Return the great-circle distance in km between two GPS coordinates."""
        r = 6371.0
        dlat = math.radians(lat2 - lat1)
        dlng = math.radians(lng2 - lng1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(dlng / 2) ** 2
        )
        return r * 2 * math.asin(math.sqrt(a))

    def _build_result(
        self,
        name: str,
        category: str,
        lat: float,
        lng: float,
        phone_primary: str | None,
        address: str | None,
        country_code: str,
        source: str,
        trust_score: int,
        origin_lat: float,
        origin_lng: float,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Build a normalised result dict with distance calculated from origin.

        All adapters must return dicts with this exact shape so the
        :class:`~core.service_fetcher.ServiceFetcher` can process them
        uniformly.

        Args:
            **kwargs: Additional fields passed through (e.g. phone_secondary,
                      state_code, is_24hr, subcategory).
        """
        return {
            "name": name or category.capitalize(),
            "category": category,
            "lat": lat,
            "lng": lng,
            "phone_primary": phone_primary,
            "phone_secondary": kwargs.get("phone_secondary"),
            "address": address,
            "country_code": country_code,
            "state_code": kwargs.get("state_code"),
            "source": source,
            "trust_score": trust_score,
            "is_24hr": kwargs.get("is_24hr", False),
            "subcategory": kwargs.get("subcategory"),
            "distance_km": self._haversine(origin_lat, origin_lng, lat, lng),
        }
