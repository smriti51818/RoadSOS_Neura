"""Deduplicates service records from multiple adapters.

Two records are considered duplicates if:
  1. Their GPS coordinates are within 100 metres of each other, AND
  2. Their names are ≥ 70% similar (character-level Jaccard after stopword removal).

When duplicates are found the record with the highest trust_score is kept.
Tie-breaking prefers the record with a phone number, then one with an address.
"""

import math
from typing import Any


class Deduplicator:
    """Removes duplicate service records produced by multiple adapters."""

    DISTANCE_THRESHOLD_M: float = 100.0
    NAME_SIMILARITY_THRESHOLD: float = 0.70

    def deduplicate(self, services: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Return a deduplicated service list.

        Algorithm:
        1. Sort by trust_score descending — higher quality processed first.
        2. For each unassigned record create a cluster; sweep remaining
           records and absorb those that are duplicates.
        3. Emit the best record from each cluster.

        The result is deterministic for the same input.

        Args:
            services: Raw combined results from all adapters.

        Returns:
            Deduplicated list — one canonical record per physical location.
        """
        sorted_services = sorted(
            services, key=lambda s: -s.get("trust_score", 1)
        )

        assigned = [False] * len(sorted_services)
        result: list[dict[str, Any]] = []

        for i, anchor in enumerate(sorted_services):
            if assigned[i]:
                continue

            cluster: list[dict[str, Any]] = [anchor]
            assigned[i] = True

            for j in range(i + 1, len(sorted_services)):
                if assigned[j]:
                    continue
                if self._are_duplicates(anchor, sorted_services[j]):
                    cluster.append(sorted_services[j])
                    assigned[j] = True

            result.append(self._best_record(cluster))

        return result

    def _are_duplicates(
        self,
        service_a: dict[str, Any],
        service_b: dict[str, Any],
    ) -> bool:
        """Return True if two service records represent the same physical place."""
        distance_m = self._distance_metres(
            service_a.get("lat", 0.0),
            service_a.get("lng", 0.0),
            service_b.get("lat", 0.0),
            service_b.get("lng", 0.0),
        )
        if distance_m > self.DISTANCE_THRESHOLD_M:
            return False

        similarity = self._name_similarity(
            service_a.get("name", ""),
            service_b.get("name", ""),
        )
        return similarity >= self.NAME_SIMILARITY_THRESHOLD

    def _distance_metres(
        self,
        lat1: float,
        lng1: float,
        lat2: float,
        lng2: float,
    ) -> float:
        """Haversine distance between two coordinates in metres."""
        r = 6_371_000.0  # Earth radius in metres
        dlat = math.radians(lat2 - lat1)
        dlng = math.radians(lng2 - lng1)
        a = (
            math.sin(dlat / 2) ** 2
            + math.cos(math.radians(lat1))
            * math.cos(math.radians(lat2))
            * math.sin(dlng / 2) ** 2
        )
        return r * 2 * math.asin(math.sqrt(max(0.0, a)))

    def _name_similarity(self, name_a: str, name_b: str) -> float:
        """Character-level Jaccard similarity after stopword removal (0.0–1.0).

        Common generic words (hospital, police, station …) are stripped
        before comparison so "Dharavi Police Station" and
        "Dharavi Police Chowki" still match.
        """
        _STOP_WORDS = {
            "hospital",
            "police",
            "station",
            "centre",
            "center",
            "clinic",
            "fire",
            "ambulance",
            "government",
            "govt",
            "the",
            "of",
            "and",
            "chowki",
            "thana",
        }

        def clean(name: str) -> str:
            words = name.lower().split()
            kept = [w for w in words if w not in _STOP_WORDS]
            return " ".join(kept)

        a = clean(name_a)
        b = clean(name_b)

        if not a or not b:
            # If both collapse to empty after stopword removal, treat as match
            return 1.0 if (not a and not b) else 0.0

        set_a = set(a.replace(" ", ""))
        set_b = set(b.replace(" ", ""))

        longer = max(len(set_a), len(set_b))
        if longer == 0:
            return 0.0

        intersection = len(set_a & set_b)
        return intersection / longer

    def _best_record(self, services: list[dict[str, Any]]) -> dict[str, Any]:
        """From a cluster of duplicates, return the most complete record.

        Priority (highest first):
        1. Highest trust_score
        2. Has phone_primary
        3. Has address
        4. First in list (already sorted by trust desc → prefer earliest)
        """

        def _priority(s: dict[str, Any]) -> tuple[int, int, int]:
            return (
                s.get("trust_score", 1),
                1 if s.get("phone_primary") else 0,
                1 if s.get("address") else 0,
            )

        return max(services, key=_priority)
