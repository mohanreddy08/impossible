"""Website accounts, per-phone API keys, the admin-action audit and server settings."""
import datetime as dt
from typing import Optional

from sqlalchemy import JSON, Boolean, CheckConstraint, DateTime, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, utcnow


class User(Base):
    """A person who signs in to the website. Passwords are stored only as argon2id hashes."""
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    username: Mapped[str] = mapped_column(String(64), unique=True)
    display_name: Mapped[str] = mapped_column(String(128))
    role: Mapped[str] = mapped_column(String(16), index=True)
    worker_id: Mapped[Optional[str]] = mapped_column(String(32))          # ASHA accounts only: the worker whose records they see
    password_hash: Mapped[str] = mapped_column(String(256))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    token_version: Mapped[int] = mapped_column(Integer, default=1)        # bump = every open session of this user ends
    failed_logins: Mapped[int] = mapped_column(Integer, default=0)
    locked_until: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    language: Mapped[str] = mapped_column(String(4), default="en")
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    last_login_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    __table_args__ = (
        CheckConstraint("role IN ('admin','supervisor','asha')", name="ck_user_role"),
        CheckConstraint("role <> 'asha' OR worker_id IS NOT NULL", name="ck_user_asha_worker"),
    )


class PhoneKey(Base):
    """One long random API key per phone. Only a SHA-256 of the key is stored (the key has 256 random bits, so a slow hash adds
    nothing and a fast one allows an indexed lookup on every request). The key itself is shown once, at creation."""
    __tablename__ = "phone_keys"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    key_id: Mapped[str] = mapped_column(String(16), unique=True)          # public part, also the first characters of the key
    key_hash: Mapped[str] = mapped_column(String(64), unique=True)
    label: Mapped[str] = mapped_column(String(64))
    worker_id: Mapped[str] = mapped_column(String(32), index=True)
    created_by: Mapped[str] = mapped_column(String(64))
    created_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    revoked_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    revoked_by: Mapped[Optional[str]] = mapped_column(String(64))
    last_seen_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    last_sync_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    last_installation_hash: Mapped[Optional[str]] = mapped_column(String(64))
    client_agent: Mapped[Optional[str]] = mapped_column(String(96))        # User-Agent / app version as sent by the phone
    pushes: Mapped[int] = mapped_column(Integer, default=0)
    ops_received: Mapped[int] = mapped_column(Integer, default=0)
    ops_acknowledged: Mapped[int] = mapped_column(Integer, default=0)


class AdminAudit(Base):
    """Every admin action, every export and every phone-number reveal. Holds no health text and no phone numbers."""
    __tablename__ = "admin_audit"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow, index=True)
    actor: Mapped[str] = mapped_column(String(64), index=True)
    action: Mapped[str] = mapped_column(String(32), index=True)
    target: Mapped[Optional[str]] = mapped_column(String(64))
    details: Mapped[Optional[dict]] = mapped_column(JSON)


class AppSetting(Base):
    __tablename__ = "app_settings"
    key: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(String(512))
    updated_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    updated_by: Mapped[Optional[str]] = mapped_column(String(64))
