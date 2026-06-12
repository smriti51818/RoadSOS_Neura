"""Unit tests for the ServiceFetcher core algorithm.

All HTTP calls are mocked — no real network requests are made.
Run: cd backend && pytest tests/test_service_fetcher.py -v
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from core.service_fetcher import ServiceFetcher

# ── Test fixtures ──────────────────────────────────────────────────────────────

MOCK_COUNTRY_CONFIG = {
    "IN": {
        "name": "India",
        "emergency_numbers": {
            "police": "100",
            "ambulance": "108",
            "fire": "101",
            "unified": "112",
        },
        "map_provider": "mappls",
        "data_sources": ["osm"],
        "urban_radius_km": 5,
        "rural_radius_km": 50,
        "is_supported": True,
    },
    "DEFAULT": {
        "emergency_numbers": {"unified": "112"},
        "map_provider": "osm",
        "data_sources": ["osm"],
        "urban_radius_km": 10,
        "rural_radius_km": 100,
        "is_supported": True,
    },
}

MOCK_HOSPITAL = {
    "name": "KEM Hospital",
    "category": "hospital",
    "lat": 19.076,
    "lng": 72.877,
    "phone_primary": "02224136051",
    "phone_secondary": None,
    "address": "Acharya Donde Marg, Parel, Mumbai",
    "country_code": "IN",
    "state_code": "MH",
    "source": "osm",
    "trust_score": 3,
    "distance_km": 1.2,
    "is_24hr": True,
    "subcategory": None,
}

MOCK_POLICE = {
    "name": "Dharavi Police Station",
    "category": "police",
    "lat": 19.043,
    "lng": 72.853,
    "phone_primary": "02224044000",
    "phone_secondary": None,
    "address": "Dharavi, Mumbai",
    "country_code": "IN",
    "state_code": "MH",
    "source": "osm",
    "trust_score": 3,
    "distance_km": 0.8,
    "is_24hr": True,
    "subcategory": None,
}

MOCK_SERVICES = [MOCK_HOSPITAL, MOCK_POLICE]


def make_fetcher(**kwargs) -> ServiceFetcher:
    """Create a ServiceFetcher with a fast timeout for tests."""
    return ServiceFetcher(
        country_config=MOCK_COUNTRY_CONFIG,
        adapter_timeout=kwargs.get("adapter_timeout", 2.0),
    )


# ── Tests ──────────────────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_fetch_returns_structured_result():
    """fetch() must always return a dict with all required keys."""
    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=MOCK_SERVICES),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    required_keys = {
        "services",
        "services_by_category",
        "source",
        "cached",
        "count",
        "country_code",
        "search_radius_km",
        "fetched_at",
    }
    assert required_keys.issubset(result.keys())
    assert result["count"] == len(result["services"])
    assert result["country_code"] == "IN"


@pytest.mark.asyncio
async def test_fetch_groups_by_category():
    """Services must be grouped by category in services_by_category."""
    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=MOCK_SERVICES),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    by_cat = result["services_by_category"]
    assert "hospital" in by_cat
    assert "police" in by_cat

    for s in by_cat["hospital"]:
        assert s["category"] == "hospital"

    for s in by_cat["police"]:
        assert s["category"] == "police"


@pytest.mark.asyncio
async def test_fetch_empty_when_all_adapters_fail():
    """When all adapters raise exceptions the result must be an empty list."""
    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(side_effect=RuntimeError("network failure")),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    assert result["services"] == []
    assert result["count"] == 0


@pytest.mark.asyncio
async def test_fetch_timeout_handled_gracefully():
    """A slow adapter must time out — the fetcher should still return quickly."""

    async def slow_fetch(*args, **kwargs):
        await asyncio.sleep(30)
        return []

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(side_effect=slow_fetch),
    ):
        fetcher = make_fetcher(adapter_timeout=0.1)

        import time
        t0 = time.monotonic()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")
        elapsed = time.monotonic() - t0

    assert result["services"] == []
    assert elapsed < 2.0, f"Fetch took too long: {elapsed:.2f}s"


@pytest.mark.asyncio
async def test_deduplication_removes_same_place():
    """Two records for the same location from different sources → one result."""
    kem_osm = {**MOCK_HOSPITAL, "source": "osm", "trust_score": 3, "distance_km": 1.2}
    kem_mappls = {
        **MOCK_HOSPITAL,
        "source": "mappls",
        "trust_score": 4,
        "distance_km": 1.2,
        # Very close — 40m away
        "lat": MOCK_HOSPITAL["lat"] + 0.0004,
        "lng": MOCK_HOSPITAL["lng"],
    }
    combined = [kem_osm, kem_mappls]

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=combined),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    hospitals = [s for s in result["services"] if s["category"] == "hospital"]
    # Should be deduplicated to one
    assert len(hospitals) == 1
    # Higher trust_score (mappls=4) should win
    assert hospitals[0]["trust_score"] == 4


@pytest.mark.asyncio
async def test_emergency_mode_filters_low_trust():
    """In emergency mode, only trust_score ≥ 3 must appear in results."""
    services = [
        {**MOCK_HOSPITAL, "trust_score": 1, "name": "Trust1"},
        {**MOCK_HOSPITAL, "trust_score": 2, "name": "Trust2"},
        {**MOCK_HOSPITAL, "trust_score": 3, "name": "Trust3", "lat": 19.1},
        {**MOCK_HOSPITAL, "trust_score": 4, "name": "Trust4", "lat": 19.2},
    ]

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=services),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(
            19.076, 72.877, country_code="IN", emergency_mode=True
        )

    for s in result["services"]:
        assert s["trust_score"] >= 3, (
            f"trust_score={s['trust_score']} should not appear in emergency mode"
        )


@pytest.mark.asyncio
async def test_browse_mode_includes_trust_2():
    """In browse mode (emergency_mode=False), trust_score ≥ 2 must be included."""
    services = [
        {**MOCK_HOSPITAL, "trust_score": 2, "name": "Trust2"},
        {**MOCK_HOSPITAL, "trust_score": 3, "name": "Trust3", "lat": 19.1},
    ]

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=services),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(
            19.076, 72.877, country_code="IN", emergency_mode=False
        )

    trust_scores = {s["trust_score"] for s in result["services"]}
    assert 2 in trust_scores, "Trust score 2 should be included in browse mode"


@pytest.mark.asyncio
async def test_results_sorted_by_distance():
    """Results must be ordered by distance_km ascending."""
    services = [
        {**MOCK_HOSPITAL, "name": "Far", "distance_km": 5.0, "lat": 19.12},
        {**MOCK_HOSPITAL, "name": "Near", "distance_km": 1.0, "lat": 19.08},
        {**MOCK_HOSPITAL, "name": "Mid", "distance_km": 3.0, "lat": 19.10},
    ]

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=services),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    distances = [s["distance_km"] for s in result["services"]]
    assert distances == sorted(distances), (
        f"Results not sorted by distance: {distances}"
    )


@pytest.mark.asyncio
async def test_results_capped_at_5_per_category():
    """No more than 5 results per category should be returned."""
    hospitals = [
        {
            **MOCK_HOSPITAL,
            "name": f"Hospital {i}",
            "lat": 19.076 + i * 0.01,
            "distance_km": float(i),
        }
        for i in range(10)
    ]

    with patch(
        "core.service_fetcher.OSMAdapter.fetch",
        new=AsyncMock(return_value=hospitals),
    ):
        fetcher = make_fetcher()
        result = await fetcher.fetch(19.076, 72.877, country_code="IN")

    hospital_results = result["services_by_category"].get("hospital", [])
    assert len(hospital_results) <= 5, (
        f"Got {len(hospital_results)} hospitals, expected ≤ 5"
    )
