"""HDX (Humanitarian Data Exchange) adapter stub.

Trust score: 2 — developing-nation fallback data.

TODO Module 6: Connect to Humanitarian Data Exchange
HDX provides health facility data for 50+ developing nations.
Data source: data.humdata.org

Download country CSVs and seed into Supabase.
This adapter will query Supabase for HDX-sourced records.
Trust score: 2-3 depending on dataset age.

Countries with best coverage:
    Kenya, Nigeria, Tanzania, Ethiopia, Uganda, Ghana, South Africa.

Implementation plan:
1. Download HDX health facility CSVs per country
2. Seed to Supabase services table with source='hdx', trust_score=2
3. This adapter queries Supabase by bounding box and category
4. Returns results with distance calculated via _haversine
"""

from typing import Any

from .base_adapter import BaseAdapter


class HDXAdapter(BaseAdapter):
    """Queries HDX-sourced records from the Supabase services table.

    Stub in Module 1 — returns empty list until Module 6 populates the DB.
    """

    async def fetch(
        self,
        lat: float,
        lng: float,
        radius_km: int,
        categories: list[str],
    ) -> list[dict[str, Any]]:
        """Return HDX health facility records near the given coordinates."""
        # TODO Module 6: query Supabase for HDX records by bounding box
        return []
