"""Pydantic v2 schemas for emergency lifecycle endpoints."""

from __future__ import annotations

from pydantic import BaseModel, field_validator


class VictimDetailSchema(BaseModel):
    """Per-victim details collected during the triage flow."""

    age_group: str
    condition: str
    help_type: str

    @field_validator("age_group")
    @classmethod
    def validate_age_group(cls, v: str) -> str:
        allowed = {"child_0_12", "teen_13_17", "adult_18_60", "senior_60_plus"}
        if v not in allowed:
            raise ValueError(f"age_group must be one of {sorted(allowed)}")
        return v

    @field_validator("condition")
    @classmethod
    def validate_condition(cls, v: str) -> str:
        allowed = {"conscious", "unconscious", "bleeding", "trapped"}
        if v not in allowed:
            raise ValueError(f"condition must be one of {sorted(allowed)}")
        return v

    @field_validator("help_type")
    @classmethod
    def validate_help_type(cls, v: str) -> str:
        allowed = {"ambulance", "fire_rescue", "both"}
        if v not in allowed:
            raise ValueError(f"help_type must be one of {sorted(allowed)}")
        return v

    @property
    def needs_pediatric_unit(self) -> bool:
        """Child under 13 → route to paediatric trauma unit."""
        return self.age_group == "child_0_12"

    @property
    def needs_fire_rescue(self) -> bool:
        """Trapped or fire-rescue help requested → alert fire brigade."""
        return self.help_type in ("fire_rescue", "both") or self.condition == "trapped"

    @property
    def is_senior(self) -> bool:
        """Senior citizen → flag for dispatcher priority handling."""
        return self.age_group == "senior_60_plus"

    @property
    def is_high_priority(self) -> bool:
        """Unconscious or trapped → requires immediate response."""
        return self.condition in ("unconscious", "trapped")


class EmergencyStartRequest(BaseModel):
    """POST /api/emergency/start request body."""

    lat: float
    lng: float
    emergency_type: str
    victim_type: str
    user_phone: str | None = None
    victim_count: int | None = None
    victim_details: list[VictimDetailSchema] = []

    @field_validator("emergency_type")
    @classmethod
    def validate_emergency_type(cls, v: str) -> str:
        allowed = {"accident", "fire", "medical", "unsafe"}
        if v not in allowed:
            raise ValueError(f"emergency_type must be one of {sorted(allowed)}")
        return v

    @field_validator("victim_type")
    @classmethod
    def validate_victim_type(cls, v: str) -> str:
        allowed = {"people_injured", "vehicle_only", "self", "bystander"}
        if v not in allowed:
            raise ValueError(f"victim_type must be one of {sorted(allowed)}")
        return v

    @property
    def has_pediatric_victims(self) -> bool:
        return any(v.needs_pediatric_unit for v in self.victim_details)

    @property
    def has_trapped_victims(self) -> bool:
        return any(v.needs_fire_rescue for v in self.victim_details)

    @property
    def has_senior_victims(self) -> bool:
        return any(v.is_senior for v in self.victim_details)

    @property
    def priority_categories(self) -> list[str]:
        """Ordered service categories to fetch based on emergency context.

        Used by the service fetcher to surface the most relevant results first.
        """
        if self.victim_type == "vehicle_only":
            return ["police", "towing"]

        cats: list[str] = []
        if self.emergency_type in ("accident", "medical"):
            cats.append("ambulance")
            cats.append("hospital")
        if self.emergency_type == "fire" or self.has_trapped_victims:
            cats.append("fire")
        if "police" not in cats:
            cats.append("police")
        return cats


class EmergencyStartResponse(BaseModel):
    """POST /api/emergency/start response body."""

    session_id: str
    status: str
    message: str
    priority_categories: list[str]
    nearest_police_hint: str | None = None
    has_pediatric_alert: bool = False
    has_trapped_alert: bool = False
    has_senior_alert: bool = False


class EmergencyPingRequest(BaseModel):
    """POST /api/emergency/ping request body."""

    session_id: str
    lat: float
    lng: float
    accuracy_m: float | None = None


class EmergencyPingResponse(BaseModel):
    """POST /api/emergency/ping response body."""

    received: bool
    pinged_at: str
    session_id: str


class EmergencyResolveRequest(BaseModel):
    """POST /api/emergency/resolve request body."""

    session_id: str


class EmergencyResolveResponse(BaseModel):
    """POST /api/emergency/resolve response body."""

    resolved: bool
    session_id: str
    resolved_at: str
