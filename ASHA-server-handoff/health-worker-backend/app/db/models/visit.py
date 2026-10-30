import datetime as dt
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, String, Time
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class Visit(Base):
    __tablename__ = "visits"
    visit_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.household_id"), index=True)
    worker_id: Mapped[str] = mapped_column(String(32), index=True)
    scheduled_date: Mapped[dt.date] = mapped_column(Date, index=True)
    actual_visit_date: Mapped[Optional[dt.date]] = mapped_column(Date)
    # time of day the worker went (local time as entered on the phone; no time zone is stored). Only on COMPLETED visits. Optional.
    actual_visit_time: Mapped[Optional[dt.time]] = mapped_column(Time)
    visit_status: Mapped[str] = mapped_column(String(16), index=True)
    visit_reason: Mapped[str] = mapped_column(String(32))
    followup_required: Mapped[Optional[bool]] = mapped_column(Boolean)   # NULL for PLANNED visits
    next_followup_date: Mapped[Optional[dt.date]] = mapped_column(Date)
    referral_status: Mapped[str] = mapped_column(String(24), default="NONE")
    # intentionally not an FK: referrals.visit_id already points here (avoids a circular FK)
    referral_id: Mapped[Optional[str]] = mapped_column(String(32))
    recorded_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    version: Mapped[int] = mapped_column(Integer, default=1)
    synthetic_record: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (
        CheckConstraint("visit_status IN ('PLANNED','COMPLETED','MISSED','RESCHEDULED','CANCELLED')", name="ck_visit_status"),
        CheckConstraint("referral_status IN ('NONE','RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')", name="ck_visit_ref_status"),
        Index("ix_visits_status_sched", "visit_status", "scheduled_date"),
    )
