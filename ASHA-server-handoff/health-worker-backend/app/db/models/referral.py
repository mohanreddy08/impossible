import datetime as dt
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, ForeignKey, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class Facility(Base):
    __tablename__ = "facilities"
    facility_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    synthetic_record: Mapped[bool] = mapped_column(Boolean, default=True)


class Referral(Base):
    __tablename__ = "referrals"
    referral_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    household_id: Mapped[str] = mapped_column(ForeignKey("households.household_id"), index=True)
    visit_id: Mapped[str] = mapped_column(ForeignKey("visits.visit_id"), index=True)
    facility_id: Mapped[str] = mapped_column(ForeignKey("facilities.facility_id"), index=True)
    service_category: Mapped[str] = mapped_column(String(24))
    referral_created_date: Mapped[dt.date] = mapped_column(Date, index=True)
    planned_visit_date: Mapped[Optional[dt.date]] = mapped_column(Date)
    referral_status: Mapped[str] = mapped_column(String(24), index=True)
    attendance_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    attendance_confirmation_date: Mapped[Optional[dt.date]] = mapped_column(Date)
    attendance_record_id: Mapped[Optional[str]] = mapped_column(String(32))
    record_state: Mapped[str] = mapped_column(String(12), default="ACTIVE", index=True)
    duplicate_of: Mapped[Optional[str]] = mapped_column(String(32))
    last_updated: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    version: Mapped[int] = mapped_column(Integer, default=1)
    synthetic_record: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (
        CheckConstraint("referral_status IN ('RECOMMENDED','PLANNED','ATTENDANCE_CONFIRMED')", name="ck_referral_status"),
        CheckConstraint("record_state IN ('ACTIVE','CANCELLED','INVALID','DUPLICATE')", name="ck_referral_state"),
        # attendance can only be confirmed together with an attendance record + date
        CheckConstraint("attendance_confirmed = (referral_status = 'ATTENDANCE_CONFIRMED')", name="ck_referral_attendance_flag"),
        Index("ix_referrals_fac_created", "facility_id", "referral_created_date"),
    )
