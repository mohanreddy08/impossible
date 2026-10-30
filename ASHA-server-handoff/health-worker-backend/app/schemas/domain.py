import datetime as dt
from typing import List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field, computed_field, field_validator

from app.schemas.common import ORM

Category = Literal["ANC", "IMMUNISATION", "NUTRITION", "HYPERTENSION", "DIABETES", "ROUTINE"]
ServiceCategory = Literal["ANC", "IMMUNISATION", "NUTRITION", "HYPERTENSION", "DIABETES", "GENERAL"]
VisitStatus = Literal["PLANNED", "COMPLETED", "MISSED", "RESCHEDULED", "CANCELLED"]
ReferralStatus = Literal["RECOMMENDED", "PLANNED", "ATTENDANCE_CONFIRMED"]
RecordState = Literal["ACTIVE", "CANCELLED", "INVALID", "DUPLICATE"]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# ---------- households ----------
class HouseholdCreate(Strict):
    household_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{3,32}$")
    village_id: str = Field(..., pattern=r"^[A-Za-z0-9_-]{2,32}$")
    assigned_worker_id: str = Field(..., pattern=r"^[A-Za-z0-9_-]{2,32}$")
    household_member_count: int = Field(..., ge=1, le=60)
    eligible_followup_categories: List[Category] = Field(default_factory=lambda: ["ROUTINE"])
    scheduled_followup_category: Optional[Category] = None


class HouseholdUpdate(Strict):
    village_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{2,32}$")
    assigned_worker_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{2,32}$")
    household_member_count: Optional[int] = Field(None, ge=1, le=60)
    eligible_followup_categories: Optional[List[Category]] = None
    scheduled_followup_category: Optional[Category] = None
    version: Optional[int] = Field(None, description="Expected current version (optimistic concurrency).")


class HouseholdOut(ORM):
    household_id: str
    village_id: str
    assigned_worker_id: str
    household_member_count: int
    eligible_followup_categories: List[str]
    last_visit_date: Optional[dt.date]
    next_visit_due_date: Optional[dt.date]
    scheduled_followup_category: Optional[str]
    record_status: str
    last_updated: dt.datetime
    version: int
    synthetic_record: bool

    @field_validator("eligible_followup_categories", mode="before")
    @classmethod
    def _split(cls, v):
        return [c for c in v.split("|") if c] if isinstance(v, str) else v


# ---------- visits ----------
class VisitCreate(Strict):
    visit_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{3,32}$")
    household_id: str
    worker_id: Optional[str] = None
    scheduled_date: dt.date
    actual_visit_date: Optional[dt.date] = None
    actual_visit_time: Optional[dt.time] = Field(None, description="Time of day the worker went (local time as entered, HH:MM). Only with a COMPLETED visit.")
    visit_status: VisitStatus = "PLANNED"
    visit_reason: Category = "ROUTINE"
    followup_required: Optional[bool] = None
    next_followup_date: Optional[dt.date] = None


class VisitUpdate(Strict):
    scheduled_date: Optional[dt.date] = None
    actual_visit_date: Optional[dt.date] = None
    actual_visit_time: Optional[dt.time] = None
    visit_status: Optional[VisitStatus] = None
    visit_reason: Optional[Category] = None
    followup_required: Optional[bool] = None
    next_followup_date: Optional[dt.date] = None
    create_followup_task: bool = Field(True, description="When completing with followup_required and next_followup_date, create the next PLANNED visit.")
    version: Optional[int] = None


class VisitOut(ORM):
    visit_id: str
    household_id: str
    worker_id: str
    scheduled_date: dt.date
    actual_visit_date: Optional[dt.date]
    actual_visit_time: Optional[dt.time] = None
    visit_status: str
    visit_reason: str
    followup_required: Optional[bool]
    next_followup_date: Optional[dt.date]
    referral_status: str
    referral_id: Optional[str]
    recorded_at: dt.datetime
    updated_at: dt.datetime
    version: int
    synthetic_record: bool


class FollowUpOut(BaseModel):
    visit_id: str
    household_id: str
    worker_id: str
    category: str
    scheduled_date: dt.date
    bucket: Literal["OVERDUE", "DUE_TODAY", "UPCOMING"]
    days_overdue: int
    explanation: str


# ---------- referrals ----------
class ReferralCreate(Strict):
    referral_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{3,32}$")
    household_id: str
    visit_id: str
    facility_id: str
    service_category: ServiceCategory
    referral_created_date: Optional[dt.date] = None
    referral_status: Literal["RECOMMENDED", "PLANNED"] = "RECOMMENDED"
    planned_visit_date: Optional[dt.date] = None


class ReferralUpdate(Strict):
    referral_status: Optional[ReferralStatus] = None
    planned_visit_date: Optional[dt.date] = None
    attendance_confirmation_date: Optional[dt.date] = None
    attendance_record_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{3,32}$")
    record_state: Optional[Literal["CANCELLED", "INVALID"]] = None
    version: Optional[int] = None


def referral_label(status: str, attendance_confirmed: bool, record_state: str = "ACTIVE") -> str:
    """Plain-language label. Only a confirmed hospital attendance record may be described as attended."""
    if record_state != "ACTIVE":
        return {"CANCELLED": "Referral cancelled", "INVALID": "Referral record invalid", "DUPLICATE": "Duplicate referral record (not counted)"}[record_state]
    if status == "ATTENDANCE_CONFIRMED" and attendance_confirmed:
        return "Hospital attendance confirmed by hospital record"
    if status == "PLANNED":
        return "Referral planned - attendance NOT confirmed"
    return "Referral recommended - not yet planned, attendance NOT confirmed"


class ReferralOut(ORM):
    referral_id: str
    household_id: str
    visit_id: str
    facility_id: str
    service_category: str
    referral_created_date: dt.date
    planned_visit_date: Optional[dt.date]
    referral_status: str
    attendance_confirmed: bool
    attendance_confirmation_date: Optional[dt.date]
    attendance_record_id: Optional[str]
    record_state: str
    duplicate_of: Optional[str]
    last_updated: dt.datetime
    version: int
    synthetic_record: bool

    @computed_field
    @property
    def status_label(self) -> str:
        return referral_label(self.referral_status, self.attendance_confirmed, self.record_state)
