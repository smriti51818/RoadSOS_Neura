"""Pydantic v2 schemas for service-related API endpoints."""

from __future__ import annotations

from datetime import datetime, timezone

from pydantic import BaseModel, ConfigDict, field_validator, model_validator


class ServiceResponse(BaseModel):
    """Single service result returned to the Flutter client."""

    model_config = ConfigDict(extra="ignore")

    id: str | None = None
    name: str
    category: str
    subcategory: str | None = None
    lat: float
    lng: float
    phone_primary: str | None = None
    phone_secondary: str | None = None
    address: str | None = None
    country_code: str
    state_code: str | None = None
    is_24hr: bool = True
    trust_score: int

    # Computed by model_validator below
    trust_label: str = ""
    source: str
    verified_date: str | None = None
    distance_km: float | None = None

    # Computed by model_validator below
    distance_label: str | None = None

    @model_validator(mode="after")
    def compute_labels(self) -> "ServiceResponse":
        """Compute human-readable labels from numeric fields."""
        _trust_labels = {
            5: "Govt Verified",
            4: "Verified",
            3: "Community Verified",
            2: "Unverified",
            1: "Unreviewed",
        }
        self.trust_label = _trust_labels.get(self.trust_score, "Unreviewed")

        if self.distance_km is not None:
            if self.distance_km < 1.0:
                metres = int(self.distance_km * 1000)
                self.distance_label = f"{metres}m"
            else:
                self.distance_label = f"{self.distance_km:.1f} km"

        return self


class NearbyServicesResponse(BaseModel):
    """Response for GET /api/services/nearby."""

    services: list[ServiceResponse]
    services_by_category: dict[str, list[ServiceResponse]]

    # "live" | "cache" | "mixed" | "pending"
    source: str
    cached: bool
    count: int
    country_code: str
    search_radius_km: int

    # ISO 8601 timestamp
    fetched_at: str


class EmergencyNumbersResponse(BaseModel):
    """Response for GET /api/services/emergency-numbers/{code}."""

    country_code: str
    country_name: str
    police: str | None = None
    ambulance: str | None = None
    fire: str | None = None
    unified: str
    women: str | None = None
    nhai: str | None = None
    traffic: str | None = None

    # True when the country was not found and DEFAULT config was used
    is_default: bool = False


class ReportRequest(BaseModel):
    """POST /api/services/report request body."""

    service_id: str
    report_type: str

    @field_validator("report_type")
    @classmethod
    def validate_report_type(cls, v: str) -> str:
        allowed = {"wrong_number", "closed", "moved", "duplicate"}
        if v not in allowed:
            raise ValueError(
                f"report_type must be one of {sorted(allowed)}"
            )
        return v


class ReportResponse(BaseModel):
    """POST /api/services/report response body."""

    reported: bool
    service_id: str
    report_type: str
    reported_at: str
