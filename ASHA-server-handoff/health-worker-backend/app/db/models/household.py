import datetime as dt
from typing import Optional

from sqlalchemy import Boolean, CheckConstraint, Date, DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class Household(Base):
    __tablename__ = "households"
    household_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    village_id: Mapped[str] = mapped_column(String(32), index=True)
    assigned_worker_id: Mapped[str] = mapped_column(String(32), index=True)
    household_member_count: Mapped[int] = mapped_column(Integer)
    # stored as "|ANC|ROUTINE|" so LIKE '%|ANC|%' filters work on SQLite and PostgreSQL
    eligible_followup_categories: Mapped[str] = mapped_column(String(128), default="||")
    last_visit_date: Mapped[Optional[dt.date]] = mapped_column(Date)
    next_visit_due_date: Mapped[Optional[dt.date]] = mapped_column(Date, index=True)
    scheduled_followup_category: Mapped[Optional[str]] = mapped_column(String(32))
    record_status: Mapped[str] = mapped_column(String(16), index=True)
    last_updated: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow, index=True)
    version: Mapped[int] = mapped_column(Integer, default=1)
    synthetic_record: Mapped[bool] = mapped_column(Boolean, default=True)
    __table_args__ = (
        CheckConstraint("household_member_count >= 1", name="ck_household_members"),
        CheckConstraint("record_status IN ('UPCOMING','DUE_TODAY','OVERDUE','COMPLETED','NO_VISIT_DUE')", name="ck_household_status"),
    )
