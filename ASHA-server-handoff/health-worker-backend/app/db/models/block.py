"""The block's register (villages, ASHAs, people) loaded from the SYNTHETIC hackathon pack, plus the Q&A audit.

The sync tables (households, visits, referrals) are untouched: the extra per-house facts the website needs (house number, head, generated
map position, a synthetic phone number) live in household_profiles, so nothing new can leak into the phone's sync contract."""
import datetime as dt
from typing import Optional

from sqlalchemy import JSON, Boolean, CheckConstraint, Date, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class Village(Base):
    __tablename__ = "villages"
    village_id: Mapped[str] = mapped_column(String(32), primary_key=True)   # slug, e.g. "belwadi-tola" (or VIL-SYN-01 for the phone demo set)
    name: Mapped[str] = mapped_column(String(64))
    block: Mapped[str] = mapped_column(String(64))
    source: Mapped[str] = mapped_column(String(16))                         # 'block' (h5 pack) or 'phone-demo' (sync datasets)
    map_json: Mapped[Optional[dict]] = mapped_column(JSON)                  # GENERATED street layout; not a real place


class Asha(Base):
    __tablename__ = "ashas"
    worker_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    name: Mapped[str] = mapped_column(String(64))
    villages: Mapped[list] = mapped_column(JSON)
    source: Mapped[str] = mapped_column(String(16))


class HouseholdProfile(Base):
    __tablename__ = "household_profiles"
    household_id: Mapped[str] = mapped_column(ForeignKey("households.household_id"), primary_key=True)
    house_no: Mapped[Optional[str]] = mapped_column(String(16))
    head_member_id: Mapped[Optional[str]] = mapped_column(String(16))
    head_name: Mapped[Optional[str]] = mapped_column(String(64))
    lat: Mapped[Optional[float]] = mapped_column(Float)
    lng: Mapped[Optional[float]] = mapped_column(Float)
    phone_number: Mapped[Optional[str]] = mapped_column(String(20))       # SYNTHETIC (unallocated +91 5xxxx range); shown masked


class Member(Base):
    __tablename__ = "members"
    member_id: Mapped[str] = mapped_column(String(16), primary_key=True)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.household_id"), index=True)
    name: Mapped[str] = mapped_column(String(64))
    relation: Mapped[Optional[str]] = mapped_column(String(32))
    sex: Mapped[Optional[str]] = mapped_column(String(1))
    dob: Mapped[Optional[dt.date]] = mapped_column(Date)
    register: Mapped[dict] = mapped_column(JSON)                           # the register row exactly as in the pack (input to the VIS rules)


class QaAudit(Base):
    """One row per question asked through the server. The question text is NEVER stored: only the outcome, the cited section ids and
    the danger-sign rule ids. Escalations carry a small workflow (open -> acknowledged -> closed, with who handled them)."""
    __tablename__ = "qa_audit"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(64))
    channel: Mapped[str] = mapped_column(String(16))                      # web | api | phone-qa
    outcome: Mapped[str] = mapped_column(String(16), index=True)          # ESCALATED | REFUSED | ANSWERED
    cited_section_ids: Mapped[list] = mapped_column(JSON)
    rule_ids: Mapped[list] = mapped_column(JSON)
    escalate: Mapped[bool] = mapped_column(Boolean, default=False, index=True)
    refused: Mapped[bool] = mapped_column(Boolean, default=False)
    latency_ms: Mapped[Optional[float]] = mapped_column(Float)
    worker_id: Mapped[Optional[str]] = mapped_column(String(32))
    household_id: Mapped[Optional[str]] = mapped_column(String(32))
    status: Mapped[Optional[str]] = mapped_column(String(16), index=True)  # escalations only
    handled_by: Mapped[Optional[str]] = mapped_column(String(64))
    handled_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    note_code: Mapped[Optional[str]] = mapped_column(String(32))           # fixed choice list, never free text
    __table_args__ = (
        CheckConstraint("outcome IN ('ESCALATED','REFUSED','ANSWERED')", name="ck_qa_outcome"),
        CheckConstraint("status IS NULL OR status IN ('OPEN','ACKNOWLEDGED','CLOSED')", name="ck_qa_status"),
    )
