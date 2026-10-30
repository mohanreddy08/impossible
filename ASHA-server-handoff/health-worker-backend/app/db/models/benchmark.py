"""Evaluation data lives apart from production tables and is never served by the API."""
import datetime as dt

from sqlalchemy import JSON, DateTime, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class BenchmarkCase(Base):
    __tablename__ = "benchmark_cases"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    dataset: Mapped[str] = mapped_column(String(64), index=True)
    case_id: Mapped[str] = mapped_column(String(64))
    payload: Mapped[dict] = mapped_column(JSON)
    imported_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    __table_args__ = (UniqueConstraint("dataset", "case_id", name="uq_benchmark_dataset_case"),)
