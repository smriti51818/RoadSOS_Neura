"""Trust scorer — assigns and filters verification levels for service records."""

from typing import Any


class TrustScorer:
    """Assigns a trust score (1–5) to a service based on its data source.

    Scores:
        5 — Government / official API (data.gov.in, NHA, HIFLD, NHS CQC)
        4 — Government-backed commercial (Mappls, Healthsites.io)
        3 — Community verified (OSM with phone-confirmed edits)
        2 — Developing-nation fallback (HDX / unverified OSM)
        1 — Crowdsourced / unknown — NEVER shown in emergency mode
    """

    _SOURCE_SCORES: dict[str, int] = {
        "data_gov_in": 5,
        "nha": 5,
        "all_india_health_centres": 5,
        "hifld": 5,
        "nhs_cqc": 5,
        "mappls": 4,
        "healthsites": 4,
        "osm_verified": 3,
        "osm": 3,
        "hdx": 2,
        "crowdsourced": 1,
    }

    def score(self, source: str) -> int:
        """Return the trust score for [source]. Unknown sources default to 1."""
        return self._SOURCE_SCORES.get(source.lower(), 1)

    def filter_for_emergency(self, services: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Return only services with trust_score >= 3.

        This filter is ALWAYS applied in emergency mode — lower-quality records
        must not be shown when a person's life may depend on the number.
        """
        return [s for s in services if s.get("trust_score", 1) >= 3]

    def filter_for_browse(self, services: list[dict[str, Any]]) -> list[dict[str, Any]]:
        """Return only services with trust_score >= 2 (non-emergency browse mode)."""
        return [s for s in services if s.get("trust_score", 1) >= 2]

    def sort_by_distance_and_trust(
        self, services: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        """Sort services: distance ascending, then trust score descending.

        Records with no distance_km are sorted to the end.
        """
        def sort_key(s: dict[str, Any]) -> tuple[float, int]:
            dist = s.get("distance_km")
            trust = s.get("trust_score", 1)
            return (dist if dist is not None else float("inf"), -trust)

        return sorted(services, key=sort_key)
