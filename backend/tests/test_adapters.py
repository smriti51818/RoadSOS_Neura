"""Unit tests for individual data source adapters.

All HTTP calls are mocked — no real network requests are made.
Run: cd backend && pytest tests/test_adapters.py -v
"""

import asyncio
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest

from adapters.nhs_cqc_adapter import NHSCQCAdapter
from adapters.osm_adapter import OSMAdapter

# ── OSMAdapter tests ───────────────────────────────────────────────────────────


def test_osm_adapter_builds_correct_query():
    """_build_overpass_query must include correct node filters and radius."""
    adapter = OSMAdapter()
    query = adapter._build_overpass_query(19.076, 72.877, 5000, ["hospital", "police"])

    assert query is not None
    assert "amenity" in query
    assert "hospital" in query
    assert "police" in query
    assert "around:5000" in query
    # Both categories present in one round-trip query
    assert query.count("around:5000") == 2


def test_osm_adapter_returns_none_query_for_unsupported_categories():
    """_build_overpass_query must return None when no categories are supported."""
    adapter = OSMAdapter()
    query = adapter._build_overpass_query(19.076, 72.877, 5000, ["unknown_cat"])
    assert query is None


def test_osm_adapter_parses_response_correctly():
    """_parse_elements must extract name, lat, lng, phone and set trust_score=3."""
    adapter = OSMAdapter()
    elements = [
        {
            "id": 123456,
            "type": "node",
            "lat": 19.076,
            "lon": 72.877,
            "tags": {
                "amenity": "hospital",
                "name": "KEM Hospital",
                "contact:phone": "+91-22-24136051",
                "addr:full": "Acharya Donde Marg, Parel",
            },
        }
    ]

    results = adapter._parse_elements(elements, 19.076, 72.877)

    assert len(results) == 1
    r = results[0]
    assert r["name"] == "KEM Hospital"
    assert r["lat"] == pytest.approx(19.076)
    assert r["lng"] == pytest.approx(72.877)
    assert r["phone_primary"] == "+91-22-24136051"
    assert r["trust_score"] == 3
    assert r["source"] == "osm"
    assert r["category"] == "hospital"


def test_osm_adapter_handles_missing_name():
    """When no name tag is present the category string should be used as fallback."""
    adapter = OSMAdapter()
    elements = [
        {
            "id": 999,
            "type": "node",
            "lat": 19.0,
            "lon": 72.8,
            "tags": {"amenity": "police"},
        }
    ]

    results = adapter._parse_elements(elements, 19.0, 72.8)

    assert len(results) == 1
    # Name should be empty string (category fallback applied in _build_result)
    assert results[0]["category"] == "police"


def test_osm_adapter_skips_elements_missing_coordinates():
    """Elements without lat/lon must be silently skipped."""
    adapter = OSMAdapter()
    elements = [
        {"id": 1, "type": "node", "tags": {"amenity": "hospital", "name": "A"}},
        {
            "id": 2,
            "type": "node",
            "lat": 19.0,
            "lon": 72.8,
            "tags": {"amenity": "hospital", "name": "B"},
        },
    ]

    results = adapter._parse_elements(elements, 19.0, 72.8)
    assert len(results) == 1
    assert results[0]["name"] == "B"


@pytest.mark.asyncio
async def test_osm_adapter_handles_timeout():
    """On TimeoutException the adapter must return [] without raising."""
    adapter = OSMAdapter()

    mock_response = MagicMock()
    mock_client = AsyncMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)
    mock_client.post = AsyncMock(side_effect=httpx.TimeoutException("timeout"))

    with patch("adapters.osm_adapter.httpx.AsyncClient", return_value=mock_client):
        result = await adapter.fetch(19.076, 72.877, 5, ["hospital"])

    assert result == []


@pytest.mark.asyncio
async def test_osm_adapter_handles_http_error():
    """On HTTP 500 the adapter must return [] without raising."""
    adapter = OSMAdapter()

    mock_client = AsyncMock()
    mock_client.__aenter__ = AsyncMock(return_value=mock_client)
    mock_client.__aexit__ = AsyncMock(return_value=False)

    error_response = MagicMock()
    error_response.raise_for_status.side_effect = httpx.HTTPStatusError(
        "500", request=MagicMock(), response=MagicMock()
    )
    mock_client.post = AsyncMock(return_value=error_response)

    with patch("adapters.osm_adapter.httpx.AsyncClient", return_value=mock_client):
        result = await adapter.fetch(19.076, 72.877, 5, ["hospital"])

    assert result == []


# ── NHSCQCAdapter tests ────────────────────────────────────────────────────────


@pytest.mark.asyncio
async def test_nhs_cqc_only_fetches_medical_categories():
    """Fetching non-CQC categories (police, towing) must return [] immediately."""
    adapter = NHSCQCAdapter()

    # If any HTTP call is made this mock will fail the test loudly
    with patch("adapters.nhs_cqc_adapter.httpx.AsyncClient") as mock_cls:
        result = await adapter.fetch(51.507, -0.127, 5, ["police", "towing"])

    assert result == []
    mock_cls.assert_not_called()


def test_nhs_cqc_parses_location_correctly():
    """_parse_location must extract name, coordinates, phone correctly."""
    adapter = NHSCQCAdapter()
    location = {
        "name": "St Thomas' Hospital",
        "registrationStatus": "Registered",
        "onspd_latitude": "51.4985",
        "onspd_longitude": "-0.1190",
        "mainPhoneNumber": "020 7188 7188",
        "postalAddressLine1": "Westminster Bridge Road",
        "postalAddressTownCity": "London",
        "postalCode": "SE1 7EH",
    }

    result = adapter._parse_location(location, "hospital", 51.507, -0.127)

    assert result is not None
    assert result["name"] == "St Thomas' Hospital"
    assert result["lat"] == pytest.approx(51.4985)
    assert result["lng"] == pytest.approx(-0.1190)
    assert result["phone_primary"] == "020 7188 7188"
    assert result["trust_score"] == 5
    assert result["source"] == "nhs_cqc"
    assert result["country_code"] == "GB"
    assert "Westminster Bridge Road" in result["address"]


def test_nhs_cqc_skips_non_registered():
    """Locations with registrationStatus != 'Registered' must return None."""
    adapter = NHSCQCAdapter()
    for status in ("Cancelled", "Deregistered", "Inactive", ""):
        location = {
            "name": "Closed Clinic",
            "registrationStatus": status,
            "onspd_latitude": "51.5",
            "onspd_longitude": "-0.1",
        }
        result = adapter._parse_location(location, "hospital", 51.5, -0.1)
        assert result is None, f"Expected None for registrationStatus='{status}'"


def test_nhs_cqc_skips_missing_coordinates():
    """Locations without GPS coordinates must return None."""
    adapter = NHSCQCAdapter()
    location = {
        "name": "Mystery Hospital",
        "registrationStatus": "Registered",
    }
    result = adapter._parse_location(location, "hospital", 51.5, -0.1)
    assert result is None


def test_nhs_cqc_skips_missing_name():
    """Locations without a name must return None."""
    adapter = NHSCQCAdapter()
    location = {
        "name": "",
        "registrationStatus": "Registered",
        "onspd_latitude": "51.5",
        "onspd_longitude": "-0.1",
    }
    result = adapter._parse_location(location, "hospital", 51.5, -0.1)
    assert result is None
