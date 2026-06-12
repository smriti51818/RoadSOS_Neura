"""Ranks, filters, and caps service results for the API response.

Ranking pipeline:
  1. Ensure every result has distance_km populated.
  2. Filter by trust score (emergency: ≥ 3, browse: ≥ 2).
  3. Sort: distance_km ascending, trust_score descending.
  4. Group by category.
  5. Cap each category at max_per_category (default 5).
  6. Flatten back to a single sorted list.
"""

from __future__ import annotations

import math
from typing import Any


class ResultRanker:
    """Ranks, filters, and caps service results ready for the API response."""

    def rank_and_cap(
        self,
        services: list[dict[str, Any]],
        user_lat: float,
        user_lng: float,
        emergency_mode: bool = True,
        max_per_category: int = 5,
    ) -> tuple[list[dict[str, Any]], dict[str, list[dict[str, Any]]]]:
        """Filter, sort, and cap results.

        Args:
            services: Deduplicated service list.
            user_lat: User's latitude.
            user_lng: User's longitude.
            emergency_mode: True → filter trust_score ≥ 3.
            max_per_category: Maximum results returned per category.

        Returns:
            A tuple of:
            - flat_list: All results sorted by distance then trust.
            - by_category: Results grouped and capped by category.
        """
        # Step 1: Guarantee every result has distance_km
        self._ensure_distances(services, user_lat, user_lng)

        # Step 2: Trust score filter
        min_trust = 3 if emergency_mode else 2
        filtered = [s for s in services if s.get("trust_score", 1) >= min_trust]

        # Step 3: Sort flat list
        filtered.sort(
            key=lambda s: (
                s.get("distance_km") if s.get("distance_km") is not None else float("inf"),
                -s.get("trust_score", 1),
            )
        )

        # Step 4: Group by category
        by_category: dict[str, list[dict[str, Any]]] = {}
        for service in filtered:
            cat = service.get("category", "unknown")
            by_category.setdefault(cat, []).append(service)

        # Step 5: Cap each category
        for cat in by_category:
            by_category[cat] = by_category[cat][:max_per_category]

        # Step 6: Rebuild flat list from capped categories (preserves sort order)
        flat: list[dict[str, Any]] = []
        for services_in_cat in by_category.values():
            flat.extend(services_in_cat)

        flat.sort(
            key=lambda s: (
                s.get("distance_km") if s.get("distance_km") is not None else float("inf"),
                -s.get("trust_score", 1),
            )
        )

        return flat, by_category

    def _ensure_distances(
        self,
        services: list[dict[str, Any]],
        user_lat: float,
        user_lng: float,
    ) -> list[dict[str, Any]]:
        """Add distance_km to any service that is missing it.

        Modifies dicts in-place and returns the same list.
        """
        for s in services:
            if s.get("distance_km") is None:
                s["distance_km"] = self._haversine(
                    user_lat, user_lng,
                    s.get("lat", 0.0),
                    s.get("lng", 0.0),
                )
        return services

    def _haversine(
        self,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float,
    ) -> float:
        """Return great-circle distance in km between two GPS coordinates."""
        r = 6371.0
        dlat = math.radians(lat2 - lat1)
        dlng = math.radians(lng2 - lng1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(dlng / 2) ** 2
        )
        return r * 2 * math.asin(math.sqrt(max(0.0, a)))

    def get_priority_categories(
        self,
        emergency_type: str,
        victim_details: list[dict[str, Any]] | None = None,
    ) -> list[str]:
        """Return an ordered list of service categories for the given emergency.

        Ordering logic:
          accident + people_injured  → ambulance, hospital, police
          accident + vehicle_only    → police, towing
          fire                       → fire, ambulance, police
          medical                    → ambulance, hospital, police
          unsafe                     → police, helpline

        Additional rules:
          Any victim with condition='trapped' or help_type='fire_rescue'
          → prepend 'fire' to the list.

          Any victim with age_group='child_0_12' does not change ordering
          but the caller should flag pediatric alert.

        Args:
            emergency_type: One of accident, fire, medical, unsafe.
            victim_details: Optional list of victim dicts with 'condition'
                           and 'help_type' keys.

        Returns:
            Ordered list of category strings.
        """
        victims = victim_details or []

        has_trapped = any(
            v.get("condition") == "trapped"
            or v.get("help_type") in ("fire_rescue", "both")
            for v in victims
        )

        if emergency_type == "fire" or has_trapped:
            return ["fire", "ambulance", "hospital", "police"]

        if emergency_type in ("accident", "medical"):
            return ["ambulance", "hospital", "police"]

        if emergency_type == "unsafe":
            return ["police", "helpline"]

        # Default — return all emergency categories
        return ["ambulance", "hospital", "police", "fire"]
