import datetime as dt
from typing import Optional

from sqlalchemy import JSON, DateTime, Index, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class SyncOperation(Base):
    __tablename__ = "sync_operations"
    op_id: Mapped[str] = mapped_column(String(64), primary_key=True)          # client-generated
    idempotency_key: Mapped[str] = mapped_column(String(96), unique=True)
    installation_hash: Mapped[str] = mapped_column(String(64), index=True)     # salted hash, never the raw id
    entity_type: Mapped[str] = mapped_column(String(16))
    entity_id: Mapped[str] = mapped_column(String(64))
    op_type: Mapped[str] = mapped_column(String(16))
    base_version: Mapped[Optional[int]] = mapped_column(Integer)
    client_created_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    client_updated_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    received_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    status: Mapped[str] = mapped_column(String(16), index=True)
    acknowledged_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)  # set only after commit
    server_version: Mapped[Optional[int]] = mapped_column(Integer)
    error_code: Mapped[Optional[str]] = mapped_column(String(48))
    conflict: Mapped[Optional[dict]] = mapped_column(JSON)
    result: Mapped[Optional[dict]] = mapped_column(JSON)
    __table_args__ = (Index("ix_sync_entity", "entity_type", "entity_id"),)


class AuditLog(Base):
    """Who changed what. Stores field NAMES and versions, not clinical content."""
    __tablename__ = "audit_log"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(64))
    action: Mapped[str] = mapped_column(String(24))
    entity_type: Mapped[str] = mapped_column(String(24))
    entity_id: Mapped[str] = mapped_column(String(64))
    changed_fields: Mapped[Optional[list]] = mapped_column(JSON)
    new_version: Mapped[Optional[int]] = mapped_column(Integer)
    source: Mapped[str] = mapped_column(String(16), default="api")
    __table_args__ = (Index("ix_audit_entity", "entity_type", "entity_id"),)
