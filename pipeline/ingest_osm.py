#!/usr/bin/env python3
"""OSM Overpass data ingestion pipeline.

Downloads nearby service records from OpenStreetMap for a given city
and outputs them as JSON or SQL INSERT statements for seeding Supabase.

Usage:
  python ingest_osm.py --city Mumbai  --lat 19.076 --lng 72.877 --radius 25
  python ingest_osm.py --city Delhi   --lat 28.644 --lng 77.216 --radius 30
  python ingest_osm.py --city Chennai --lat 13.083 --lng 80.270 --radius 25
  python ingest_osm.py --city Bengaluru --lat 12.972 --lng 77.595 --radius 25
"""

import argparse
import json
import math
import sys
from typing import Any

import requests

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
OVERPASS_TIMEOUT = 30  # seconds
USER_AGENT = "RoadSoS-Pipeline/1.0 (roadsos@hackathon.dev)"

CATEGORY_TAGS: dict[str, str] = {
    "hospital": 'node["amenity"~"hospital|clinic|doctors"]',
    "police": 'node["amenity"="police"]',
    "ambulance": 'node["emergency"="ambulance_station"]',
    "fire": 'node["amenity"="fire_station"]',
    "towing": 'node["shop"="car_repair"]',
    "breakdown": 'node["shop"~"car_repair|tyres|car_parts"]',
    "puncture": 'node["shop"~"tyres|bicycle|car_repair"]',
}

ALL_CATEGORIES = list(CATEGORY_TAGS.keys())


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
    return r * 2 * math.asin(math.sqrt(a))


def build_overpass_query(
    lat: float,
    lng: float,
    radius_km: int,
    categories: list[str],
) -> str:
    """Build an Overpass QL query for the given categories and bounding area."""
    radius_metres = radius_km * 1000
    node_filters = "\n  ".join(
        f'{CATEGORY_TAGS[c]}(around:{radius_metres},{lat},{lng});'
        for c in categories
        if c in CATEGORY_TAGS
    )
    return (
        f"[out:json][timeout:{OVERPASS_TIMEOUT}];\n"
        f"(\n  {node_filters}\n);\n"
        "out body;"
    )


def fetch_from_overpass(query: str) -> list[dict[str, Any]]:
    """POST query to Overpass API and return parsed elements."""
    print(f"  Querying Overpass API...", file=sys.stderr)
    resp = requests.post(
        OVERPASS_URL,
        data={"data": query},
        timeout=OVERPASS_TIMEOUT,
        headers={"User-Agent": USER_AGENT},
    )
    resp.raise_for_status()
    return resp.json().get("elements", [])


def parse_results(
    elements: list[dict[str, Any]],
    origin_lat: float,
    origin_lng: float,
) -> list[dict[str, Any]]:
    """Parse raw Overpass elements into normalised service records."""
    results = []
    for el in elements:
        tags = el.get("tags", {})
        el_lat = el.get("lat")
        el_lng = el.get("lon")
        if el_lat is None or el_lng is None:
            continue

        name = tags.get("name") or tags.get("name:en") or "Unknown"

        phone = (
            tags.get("contact:phone")
            or tags.get("phone")
            or tags.get("contact:mobile")
        )

        address = tags.get("addr:full") or tags.get("addr:street")

        amenity = tags.get("amenity", "")
        emergency_tag = tags.get("emergency", "")
        shop = tags.get("shop", "")

        if amenity in ("hospital", "clinic", "doctors"):
            category = "hospital"
        elif amenity == "police":
            category = "police"
        elif amenity == "fire_station":
            category = "fire"
        elif emergency_tag == "ambulance_station":
            category = "ambulance"
        elif shop:
            category = "breakdown"
        else:
            category = "unknown"

        distance = haversine(origin_lat, origin_lng, float(el_lat), float(el_lng))

        results.append({
            "osm_id": el.get("id"),
            "name": name,
            "category": category,
            "lat": float(el_lat),
            "lng": float(el_lng),
            "phone_primary": phone,
            "address": address,
            "country_code": "IN",
            "source": "osm",
            "trust_score": 3,
            "distance_km": round(distance, 2),
        })

    return results


def print_json(results: list[dict[str, Any]]) -> None:
    print(json.dumps(results, indent=2, ensure_ascii=False))


def print_sql(results: list[dict[str, Any]], city: str) -> None:
    """Print SQL INSERT statements for Supabase seeding."""
    for r in results:
        name = r["name"].replace("'", "''")
        address = (r["address"] or "").replace("'", "''")
        phone = r.get("phone_primary") or ""
        print(
            f"INSERT INTO services "
            f"(name, category, lat, lng, phone_primary, address, country_code, source, trust_score) "
            f"VALUES ("
            f"'{name}', '{r['category']}', {r['lat']}, {r['lng']}, "
            f"'{phone}', '{address}', 'IN', 'osm', 3"
            f") ON CONFLICT DO NOTHING; "
            f"-- {city}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Ingest OSM data for a given city into RoadSoS format",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--city", required=True, help="City name (for labelling)")
    parser.add_argument("--lat", type=float, required=True, help="City centre latitude")
    parser.add_argument("--lng", type=float, required=True, help="City centre longitude")
    parser.add_argument("--radius", type=int, default=10, help="Search radius in km")
    parser.add_argument(
        "--categories",
        nargs="+",
        default=ALL_CATEGORIES,
        choices=ALL_CATEGORIES,
        help="Service categories to fetch",
    )
    parser.add_argument(
        "--output",
        choices=["json", "insert"],
        default="json",
        help="Output format",
    )
    args = parser.parse_args()

    print(
        f"[RoadSoS Pipeline] Fetching {args.categories} near {args.city} "
        f"(lat={args.lat}, lng={args.lng}, radius={args.radius}km)...",
        file=sys.stderr,
    )

    query = build_overpass_query(args.lat, args.lng, args.radius, args.categories)
    elements = fetch_from_overpass(query)
    results = parse_results(elements, args.lat, args.lng)

    if args.output == "json":
        print_json(results)
    else:
        print_sql(results, args.city)

    print(
        f"[RoadSoS Pipeline] Fetched {len(results)} records for {args.city}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
