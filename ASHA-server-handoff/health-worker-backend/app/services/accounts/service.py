"""Accounts, sessions, phone keys, admin audit and server settings. No web framework imports (tested)."""
import datetime as dt
import hashlib
import re
import secrets
from typing import Any, Dict, List, Optional, Tuple

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import Conflict, DomainError, NotFound, TooManyRequests, Unauthorized
from app.core.principal import Principal
from app.db.base import utcnow
from app.db.models import AdminAudit, AppSetting, PhoneKey, QaAudit, User

ROLES = ("admin", "supervisor", "asha")
_ph = PasswordHasher()                     # argon2id with the library's current recommended parameters
_DUMMY_HASH = _ph.hash("timing-equaliser-not-a-password")
KEY_PREFIX = "asha_"
USERNAME_RX = re.compile(r"^[a-z0-9_.-]{3,64}$")
WORKER_RX = re.compile(r"^[A-Za-z0-9_-]{2,32}$")
MIN_PASSWORD = 10


# ---------------------------------------------------------------- passwords
def hash_password(pw: str) -> str:
    if len(pw) < MIN_PASSWORD:
        raise DomainError("password must be at least %d characters" % MIN_PASSWORD, code="WEAK_PASSWORD", status_code=422)
    return _ph.hash(pw)


def _verify(stored: str, pw: str) -> bool:
    try:
        return _ph.verify(stored, pw)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


# ---------------------------------------------------------------- sessions (JWT)
def principal_for_user(u: User) -> Principal:
    role = {"asha": "worker", "supervisor": "supervisor", "admin": "admin"}[u.role]
    return Principal(role, u.worker_id if u.role == "asha" else None, "user:" + u.username)


def issue_token(u: User, s: Settings, now: Optional[dt.datetime] = None) -> Tuple[str, int]:
    now = now or dt.datetime.now(dt.timezone.utc)
    ttl = s.session_minutes * 60
    claims = {"sub": str(u.id), "usr": u.username, "role": u.role, "tv": u.token_version, "iat": int(now.timestamp()),
              "exp": int(now.timestamp()) + ttl, "typ": "session"}
    return jwt.encode(claims, s.secret_key, algorithm="HS256"), ttl


def read_token(db: Session, token: str, s: Settings) -> Tuple[User, Dict[str, Any]]:
    try:
        c = jwt.decode(token, s.secret_key, algorithms=["HS256"], options={"require": ["exp", "sub", "tv"]})
    except jwt.PyJWTError:
        raise Unauthorized("session expired or invalid; sign in again")
    if c.get("typ") != "session":
        raise Unauthorized("session expired or invalid; sign in again")
    u = db.get(User, int(c["sub"]))
    if not u or not u.is_active or u.token_version != c["tv"]:
        raise Unauthorized("session expired or invalid; sign in again")
    return u, c


def login(db: Session, username: str, password: str, s: Settings) -> User:
    u = db.scalar(select(User).where(User.username == username.strip().lower()))
    now = utcnow()
    if not u:
        _verify(_DUMMY_HASH, password)                  # same work for unknown users: no username probing by timing
        raise Unauthorized("wrong username or password")
    if u.locked_until and u.locked_until > now:
        raise TooManyRequests("too many wrong passwords; this account is locked for a few minutes")
    if not u.is_active or not _verify(u.password_hash, password):
        u.failed_logins = (u.failed_logins or 0) + 1
        if u.failed_logins >= s.login_failures_before_lock:
            u.locked_until, u.failed_logins = now + dt.timedelta(minutes=s.login_lock_minutes), 0
            audit(db, "system", "account_locked", u.username)
        db.commit()
        raise Unauthorized("wrong username or password")
    if _ph.check_needs_rehash(u.password_hash):
        u.password_hash = _ph.hash(password)
    u.failed_logins, u.locked_until, u.last_login_at = 0, None, now
    audit(db, "user:" + u.username, "login", u.username)
    db.commit()
    return u


# ---------------------------------------------------------------- users
def list_users(db: Session) -> List[User]:
    return list(db.scalars(select(User).order_by(User.role, User.username)))


def create_user(db: Session, actor: Principal, *, username: str, display_name: str, role: str, password: str,
                worker_id: Optional[str] = None, language: str = "en") -> User:
    username = username.strip().lower()
    if not USERNAME_RX.match(username):
        raise DomainError("username: 3-64 characters a-z 0-9 _ . -", code="BAD_USERNAME", status_code=422)
    if role not in ROLES:
        raise DomainError("role must be admin, supervisor or asha", code="BAD_ROLE", status_code=422)
    if role == "asha" and not (worker_id and WORKER_RX.match(worker_id)):
        raise DomainError("an ASHA account needs the ASHA's worker id", code="WORKER_ID_REQUIRED", status_code=422)
    if db.scalar(select(User).where(User.username == username)):
        raise Conflict("that username is taken", code="DUPLICATE_USERNAME")
    u = User(username=username, display_name=display_name.strip()[:128] or username, role=role, worker_id=worker_id if role == "asha" else None,
             password_hash=hash_password(password), language=language if language in ("en", "te") else "en")
    db.add(u)
    db.flush()
    audit(db, actor.name, "user_create", username, {"role": role})
    return u


def update_user(db: Session, actor: Principal, user_id: int, *, is_active: Optional[bool] = None, password: Optional[str] = None,
                role: Optional[str] = None, display_name: Optional[str] = None, language: Optional[str] = None) -> User:
    u = db.get(User, user_id)
    if not u:
        raise NotFound("user not found")
    changed = []
    if role is not None and role != u.role:
        if role not in ROLES or (role == "asha" and not u.worker_id):
            raise DomainError("invalid role for this account", code="BAD_ROLE", status_code=422)
        _keep_one_admin(db, u, demoting=u.role == "admin")
        u.role = role
        changed.append("role")
    if is_active is not None and is_active != u.is_active:
        if not is_active:
            _keep_one_admin(db, u, demoting=u.role == "admin")
        u.is_active = is_active
        changed.append("is_active")
    if password is not None:
        u.password_hash = hash_password(password)
        u.failed_logins, u.locked_until = 0, None
        changed.append("password")
    if display_name is not None:
        u.display_name = display_name.strip()[:128] or u.username
        changed.append("display_name")
    if language is not None and language in ("en", "te"):
        u.language = language
        changed.append("language")
    if {"role", "is_active", "password"} & set(changed):
        u.token_version += 1                         # every open session of this user ends now
    audit(db, actor.name, "user_update", u.username, {"fields": changed})
    return u


def _keep_one_admin(db: Session, u: User, demoting: bool) -> None:
    if demoting and db.scalar(select(func.count()).select_from(User).where(User.role == "admin", User.is_active.is_(True), User.id != u.id)) == 0:
        raise Conflict("this is the last active admin account", code="LAST_ADMIN")


# ---------------------------------------------------------------- phone keys
def _key_hash(key: str) -> str:
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def create_phone_key(db: Session, actor: Principal, *, worker_id: str, label: str) -> Tuple[PhoneKey, str]:
    if not WORKER_RX.match(worker_id or ""):
        raise DomainError("worker id: 2-32 characters A-Z a-z 0-9 _ -", code="BAD_WORKER_ID", status_code=422)
    key_id = secrets.token_hex(4)
    key = "%s%s_%s" % (KEY_PREFIX, key_id, secrets.token_urlsafe(32))       # 256 random bits after the public id
    row = PhoneKey(key_id=key_id, key_hash=_key_hash(key), label=(label or "phone").strip()[:64], worker_id=worker_id, created_by=actor.name)
    db.add(row)
    db.flush()
    audit(db, actor.name, "phone_key_create", key_id, {"worker_id": worker_id})
    return row, key


def revoke_phone_key(db: Session, actor: Principal, key_id: str) -> PhoneKey:
    row = db.scalar(select(PhoneKey).where(PhoneKey.key_id == key_id))
    if not row:
        raise NotFound("phone key not found")
    if not row.revoked_at:
        row.revoked_at, row.revoked_by = utcnow(), actor.name
        audit(db, actor.name, "phone_key_revoke", key_id, {"worker_id": row.worker_id})
    return row


def principal_for_phone_key(db: Session, supplied: str) -> Optional[Principal]:
    """The phone sends its key in X-API-Key (unchanged contract). Returns None when it is not an active phone key."""
    if not supplied.startswith(KEY_PREFIX) or len(supplied) > 128:
        return None
    row = db.scalar(select(PhoneKey).where(PhoneKey.key_hash == _key_hash(supplied)))
    if not row or row.revoked_at:
        return None
    now = utcnow()
    p = Principal("worker", row.worker_id, "phone:" + row.key_id)
    if not row.last_seen_at or (now - row.last_seen_at).total_seconds() >= 60:     # at most one write a minute per phone
        try:
            row.last_seen_at = now
            db.commit()
        except Exception:                      # noqa: BLE001  bookkeeping only: a busy database must never fail the phone's request
            db.rollback()
    return p


def record_phone_sync(db: Session, p: Principal, installation_hash: str, agent: Optional[str], received: int, acknowledged: int) -> None:
    if not p.name.startswith("phone:"):
        return
    row = db.scalar(select(PhoneKey).where(PhoneKey.key_id == p.name[6:]))
    if not row:
        return
    row.last_sync_at = row.last_seen_at = utcnow()
    row.last_installation_hash = installation_hash
    row.client_agent = (agent or "")[:96] or None
    row.pushes += 1
    row.ops_received += received
    row.ops_acknowledged += acknowledged
    db.commit()


def list_phone_keys(db: Session) -> List[PhoneKey]:
    return list(db.scalars(select(PhoneKey).order_by(PhoneKey.revoked_at.is_not(None), PhoneKey.worker_id, PhoneKey.created_at)))


# ---------------------------------------------------------------- admin audit
def audit(db: Session, actor: str, action: str, target: Optional[str] = None, details: Optional[dict] = None) -> None:
    db.add(AdminAudit(actor=actor[:64], action=action[:32], target=(target or "")[:64] or None, details=details))


def list_audit(db: Session, limit: int = 100, offset: int = 0, action: Optional[str] = None) -> Tuple[List[AdminAudit], int]:
    q = select(AdminAudit)
    if action:
        q = q.where(AdminAudit.action == action)
    total = db.scalar(select(func.count()).select_from(q.subquery())) or 0
    return list(db.scalars(q.order_by(AdminAudit.at.desc(), AdminAudit.id.desc()).limit(limit).offset(offset))), total


# ---------------------------------------------------------------- settings
SETTING_KEYS = {"retention_days", "public_url", "default_language"}


def get_setting(db: Session, key: str, default: Optional[str] = None) -> Optional[str]:
    row = db.get(AppSetting, key)
    return row.value if row else default


def set_setting(db: Session, actor: Principal, key: str, value: str) -> None:
    if key not in SETTING_KEYS:
        raise DomainError("unknown setting", code="UNKNOWN_SETTING", status_code=422)
    row = db.get(AppSetting, key)
    if row:
        row.value, row.updated_at, row.updated_by = value, utcnow(), actor.name
    else:
        db.add(AppSetting(key=key, value=value, updated_by=actor.name))
    audit(db, actor.name, "setting_change", key, {"value": value if key != "public_url" else value[:120]})


def retention_days(db: Session, s: Settings) -> int:
    try:
        return max(7, int(get_setting(db, "retention_days", str(s.retention_days)) or s.retention_days))
    except ValueError:
        return s.retention_days


def purge_old_audit(db: Session, s: Settings) -> Dict[str, int]:
    """Deletes Q&A audit and admin audit rows older than the retention period (open escalations are kept)."""
    cut = utcnow() - dt.timedelta(days=retention_days(db, s))
    a = db.execute(delete(QaAudit).where(QaAudit.at < cut, (QaAudit.status.is_(None)) | (QaAudit.status != "OPEN"))).rowcount
    b = db.execute(delete(AdminAudit).where(AdminAudit.at < cut)).rowcount
    db.commit()
    return {"qa_audit": a or 0, "admin_audit": b or 0}
