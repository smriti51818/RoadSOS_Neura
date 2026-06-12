"""Geo-adaptive service fetcher — the core algorithm of RoadSoS.

Fetches verified emergency services from the right data sources for any
location on Earth, in parallel, with graceful degradation.

Pipeline:
  1. Resolve country and context from coordinates (Nominatim or pre-supplied).
  2. Select appropriate adapters from the country config.
  3. Fetch from all adapters concurrently — each has a hard timeout.
  4. Merge and deduplicate results across adapters.
  5. Filter by trust score (emergency: ≥ 3, browse: ≥ 2).
  6. Rank by distance, cap at max_per_category per category.
  7. Return a structured response dict — never raises.
"""

from __future__ import annotations

import asyncio
import logging
import math
from datetime import datetime, timezone
from typing import Any

from adapters.base_adapter import BaseAdapter
from adapters.hdx_adapter import HDXAdapter
from adapters.healthsites_adapter import HealthsitesAdapter
from adapters.mappls_adapter import MapplsAdapter
from adapters.nhs_cqc_adapter import NHSCQCAdapter
from adapters.osm_adapter import OSMAdapter
from core.deduplicator import Deduplicator
from core.location_resolver import LocationResolver
from core.result_ranker import ResultRanker
from core.trust_scorer import TrustScorer

logger = logging.getLogger(__name__)

# Per-adapter timeout.  Must exceed the Overpass QL [timeout:] value (25 s)
# plus network round-trip headroom.  Overpass on the public mirror is the
# slowest adapter — everything else (Mappls, Healthsites) is much faster.
DEFAULT_ADAPTER_TIMEOUT: float = 28.0

# Default categories fetched when none are specified
DEFAULT_CATEGORIES = ["police", "hospital", "ambulance", "fire", "towing"]


class ServiceFetcher:
    """Fetches verified emergency services for any location globally.

    Instantiate once at app startup (stored in app.state) and reuse
    across requests — adapters are stateless.

    Args:
        country_config: Pre-loaded country_config.json dict from app.state.
        mappls_api_key: Mappls API key (India). None disables the adapter.
        healthsites_api_key: Healthsites.io API key (global fallback).
        cqc_api_key: NHS CQC Subscription-Key (optional, UK only).
            Register free at https://developer.cqc.org.uk/
        adapter_timeout: Per-adapter async timeout in seconds (default 28.0).
            Must exceed the Overpass QL [timeout:] value (25 s).
            Lower this in unit tests for fast failure.
    """

    def __init__(
        self,
        country_config: dict[str, Any] | None = None,
        mappls_api_key: str | None = None,
        healthsites_api_key: str | None = None,
        cqc_api_key: str | None = None,
        adapter_timeout: float = DEFAULT_ADAPTER_TIMEOUT,
    ) -> None:
        self.mappls_api_key = mappls_api_key
        self.healthsites_api_key = healthsites_api_key
        self.cqc_api_key = cqc_api_key
        self.adapter_timeout = adapter_timeout
        self.deduplicator = Deduplicator()
        self.ranker = ResultRanker()
        self.trust_scorer = TrustScorer()
        self.location_resolver = LocationResolver(country_config)

    async def fetch(
        self,
        lat: float,
        lng: float,
        categories: list[str] | None = None,
        country_code: str | None = None,
        emergency_mode: bool = True,
    ) -> dict[str, Any]:
        """Fetch nearby services for the given location.

        Args:
            lat: User latitude.
            lng: User longitude.
            categories: Service categories to fetch.
                        None → all emergency categories.
            country_code: Pre-resolved ISO country code.
                          None → auto-detect via Nominatim.
            emergency_mode: True → trust_score ≥ 3 filter applied.

        Returns:
            Dict with keys:
                services, services_by_category, source, cached,
                country_code, search_radius_km, count, fetched_at.
            Always returns a valid dict — never raises.
        """
        start = datetime.now(timezone.utc)

        try:
            return await self._fetch_internal(
                lat, lng, categories, country_code, emergency_mode
            )
        except Exception as exc:
            logger.error(f"[ServiceFetcher] Unexpected error: {exc}", exc_info=True)
            return self._empty_response(country_code or "IN", 10, start)

    async def _fetch_internal(
        self,
        lat: float,
        lng: float,
        categories: list[str] | None,
        country_code: str | None,
        emergency_mode: bool,
    ) -> dict[str, Any]:
        start = datetime.now(timezone.utc)

        # Step 1: Resolve location context
        is_rural = False
        if country_code is None:
            try:
                resolved = await self.location_resolver.resolve(lat, lng)
                country_code = resolved["country_code"]
                is_rural = resolved.get("is_rural", False)
            except Exception as exc:
                logger.warning(f"[ServiceFetcher] Location resolve failed: {exc}")
                country_code = "IN"

        config = self.location_resolver.get_config(country_code)
        radius_km = self.location_resolver.get_search_radius(country_code, is_rural)

        # Step 2: Default categories
        if categories is None:
            categories = list(DEFAULT_CATEGORIES)

        # Step 3: Select adapters
        data_sources = config.get("data_sources", ["osm"])
        adapters = self._select_adapters(country_code, data_sources)

        logger.info(
            f"[ServiceFetcher] country={country_code} "
            f"categories={categories} radius={radius_km}km "
            f"adapters=[{', '.join(type(a).__name__ for a in adapters)}]"
        )

        # Step 4: Parallel fetch
        all_results = await self._fetch_parallel(
            adapters, lat, lng, radius_km, categories
        )

        # Step 5: Deduplicate
        deduped = self.deduplicator.deduplicate(all_results)

        # Step 6: Rank and cap
        flat, by_category = self.ranker.rank_and_cap(
            deduped,
            user_lat=lat,
            user_lng=lng,
            emergency_mode=emergency_mode,
        )

        elapsed_ms = int(
            (datetime.now(timezone.utc) - start).total_seconds() * 1000
        )
        logger.info(
            f"[ServiceFetcher] Done: {len(flat)} results in {elapsed_ms}ms"
        )

        return {
            "services": flat,
            "services_by_category": by_category,
            "source": "live",
            "cached": False,
            "country_code": country_code,
            "search_radius_km": radius_km,
            "count": len(flat),
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }

    async def _fetch_parallel(
        self,
        adapters: list[BaseAdapter],
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Fetch from all adapters concurrently.

        Each adapter is wrapped in asyncio.wait_for with self.adapter_timeout.
        Failed or timed-out adapters are logged but do not propagate exceptions.
        """

        async def fetch_one(adapter: BaseAdapter) -> list[dict[str, Any]]:
            name = type(adapter).__name__
            try:
                results = await asyncio.wait_for(
                    adapter.fetch(lat, lng, radius_km, categories),
                    timeout=self.adapter_timeout,
                )
                logger.debug(f"[{name}] returned {len(results)} results")
                return results
            except asyncio.TimeoutError:
                logger.warning(
                    f"[{name}] timed out after {self.adapter_timeout}s"
                )
                return []
            except Exception as exc:
                logger.error(f"[{name}] failed: {type(exc).__name__}: {exc}")
                return []

        results_per_adapter: list[list[dict[str, Any]]] = await asyncio.gather(
            *[fetch_one(a) for a in adapters]
        )

        combined: list[dict[str, Any]] = []
        for batch in results_per_adapter:
            combined.extend(batch)
        return combined

    def _select_adapters(
        self,
        country_code: str,
        data_sources: list[str],
    ) -> list[BaseAdapter]:
        """Instantiate adapters based on the country config data_sources list.

        OSM is always appended as the final fallback to guarantee coverage.
        Adapters are returned in config-specified priority order.
        """
        # Lazy-instantiate only the adapters needed for this country
        source_map: dict[str, BaseAdapter | None] = {
            "mappls": (
                MapplsAdapter(self.mappls_api_key)
                if self.mappls_api_key
                else None
            ),
            "data_gov_in": None,   # Pipeline only — records already in DB
            "nha": None,           # Pipeline only — records already in DB
            "all_india_health_centres": None,  # Pipeline only
            "nhs_cqc": NHSCQCAdapter(self.cqc_api_key),
            "healthsites": (
                HealthsitesAdapter(self.healthsites_api_key)
                if self.healthsites_api_key
                else None
            ),
            "hifld_archive": None,  # Pipeline only — static CSV in DB
            "hdx": HDXAdapter(),
            "osm": OSMAdapter(),
        }

        adapters: list[BaseAdapter] = []
        seen: set[str] = set()

        for source in data_sources:
            if source in seen:
                continue
            seen.add(source)
            adapter = source_map.get(source)
            if adapter is not None:
                adapters.append(adapter)

        # Always include OSM as last-resort fallback
        if not any(isinstance(a, OSMAdapter) for a in adapters):
            adapters.append(OSMAdapter())

        return adapters

    @staticmethod
    def _empty_response(
        country_code: str,
        radius_km: int,
        start: datetime,
    ) -> dict[str, Any]:
        """Return a safe empty response dict for error cases."""
        return {
            "services": [],
            "services_by_category": {},
            "source": "error",
            "cached": False,
            "country_code": country_code,
            "search_radius_km": radius_km,
            "count": 0,
            "fetched_at": datetime.now(timezone.utc).isoformat(),
        }

    @staticmethod
    def haversine(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
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
