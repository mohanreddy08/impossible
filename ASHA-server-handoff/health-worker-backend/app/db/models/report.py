import datetime as dt

from sqlalchemy import JSON, DateTime, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class ReportRecord(Base):
    __tablename__ = "reports"
    report_id: Mapped[str] = mapped_column(String(32), primary_key=True)
    facility_id: Mapped[str] = mapped_column(String(32), index=True)
    content_hash: Mapped[str] = mapped_column(String(64), index=True)
    scope: Mapped[str] = mapped_column(String(64), default="all", server_default="all", index=True)   # 'all' or 'worker:<id>'

    generated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    payload: Mapped[dict] = mapped_column(JSON)
