"""Server side of offline sync. Every operation is processed in its own savepoint+commit, so a failure never
rolls back previously acknowledged operations. An operation is only 'acknowledged' after its commit succeeds."""
import datetime as dt
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import DomainError, Forbidden, NotFound
from app.core.principal import Principal, hash_installation
from app.db.base import utcnow
from app.db.models import Household, Referral, SyncOperation, Visit
from app.schemas.domain import (HouseholdCreate, HouseholdUpdate, ReferralCreate, ReferralUpdate, VisitCreate, VisitUpdate)
from app.services.households import service as hh
from app.services.referrals import service as rf
from app.services.visits import service as vs

MAX_BATCH = 200
MODELS = {"household": (Household, "household_id"), "visit": (Visit, "visit_id"), "referral": (Referral, "referral_id")}
# Fields that must never be silently overwritten by a stale client (clinical / referral state).
PROTECTED = {
    "household": {"assigned_worker_id", "next_visit_due_date", "last_visit_date", "scheduled_followup_category", "record_status"},
    "visit": {"visit_status", "actual_visit_date", "actual_visit_time", "followup_required", "next_followup_date", "referral_status", "referral_id"},
    "referral": {"referral_status", "planned_visit_date", "attendance_confirmed", "attendance_confirmation_date", "attendance_record_id", "record_state", "facility_id"},
}


class SyncOpIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    op_id: str = Field(..., min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_.:-]+$")
    idempotency_key: Optional[str] = Field(None, min_length=8, max_length=96)
    entity_type: str = Field(..., pattern="^(household|visit|referral)$")
    entity_id: str = Field(..., min_length=3, max_length=64)
    op_type: str = Field(..., pattern="^(create|update)$")
    base_version: Optional[int] = Field(None, ge=1)
    client_created_at: Optional[dt.datetime] = None
    client_updated_at: Optional[dt.datetime] = None
    payload: Dict[str, Any]


class SyncPushIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    installation_id: str = Field(..., min_length=8, max_length=64)
    operations: List[Dict[str, Any]] = Field(..., max_length=MAX_BATCH)


def _naive(d):
    return d.astimezone(dt.timezone.utc).replace(tzinfo=None) if d and d.tzinfo else d


def _result(row: SyncOperation, duplicate=False, op_id=None, warnings=None):
    return dict(op_id=op_id or row.op_id, status=row.status, acknowledged=row.status == "ACKNOWLEDGED" and row.acknowledged_at is not None,
                duplicate=duplicate, server_version=row.server_version, error_code=row.error_code, error_message=(row.result or {}).get("message"),
                conflict=row.conflict, warnings=(row.result or {}).get("warnings", warnings or []))


def _apply(db: Session, p: Principal, op: SyncOpIn, settings: Settings):
    """Apply one op. Returns (server_version, conflict|None, warnings)."""
    Model, key = MODELS[op.entity_type]
    payload = dict(op.payload)
    if op.op_type == "create":
        payload[key] = op.entity_id
        warnings = []
        if op.entity_type == "household":
            ent = hh.create(db, p, HouseholdCreate(**payload), settings, "sync")
        elif op.entity_type == "visit":
            ent = vs.create(db, p, VisitCreate(**payload), settings, "sync")
        else:
            ent, dup = rf.create(db, p, ReferralCreate(**payload), settings, "sync", allow_duplicate_flag=True)
            if dup: warnings.append("DUPLICATE_FLAGGED:duplicate_of=%s" % dup)
        return ent.version, None, warnings
    # update
    cur = db.get(Model, op.entity_id)
    if not cur:
        raise NotFound("%s not found" % op.entity_type)
    if op.base_version is None:
        raise DomainError("base_version is required for updates", code="BASE_VERSION_REQUIRED", status_code=422)
    if op.base_version > cur.version:
        raise DomainError("base_version is ahead of the server", code="INVALID_BASE_VERSION", status_code=422)
    touched = set(payload) - {"version"}
    meta = None
    if op.base_version < cur.version:
        prot = touched & PROTECTED[op.entity_type]
        if prot:
            # stale client touching protected fields: do NOT apply; keep both sides for review
            raise _Conflict(dict(server_version=cur.version, base_version=op.base_version, fields=sorted(prot),
                                 server_values={f: _jsonable(getattr(cur, f, None)) for f in prot}, client_values={f: _jsonable(payload[f]) for f in prot},
                                 client_updated_at=op.client_updated_at.isoformat() if op.client_updated_at else None,
                                 resolution="NOT_APPLIED_FLAGGED_FOR_REVIEW"))
        meta = dict(superseded={f: _jsonable(getattr(cur, f, None)) for f in touched if hasattr(cur, f)}, resolution="MERGED_UNPROTECTED_FIELDS")
    payload["version"] = cur.version            # base check done above; service re-checks against live version
    if op.entity_type == "household": ent = hh.update(db, p, op.entity_id, HouseholdUpdate(**payload), "sync")
    elif op.entity_type == "visit": ent = vs.update(db, p, op.entity_id, VisitUpdate(**payload), settings, "sync")
    else: ent = rf.update(db, p, op.entity_id, ReferralUpdate(**payload), settings, "sync")
    return ent.version, meta, []


class _Conflict(Exception):
    def __init__(self, meta): self.meta = meta


def _jsonable(v):
    return v.isoformat() if isinstance(v, (dt.date, dt.datetime, dt.time)) else v


def _lookup(db: Session, op_id: str, key: str):
    try:
        return db.get(SyncOperation, op_id) or db.scalar(select(SyncOperation).where(SyncOperation.idempotency_key == key))
    except Exception:                                                  # noqa: BLE001
        db.rollback()
        return None


def _store_outcome(db: Session, row: SyncOperation, op_id: str, key: str) -> dict:
    """Persist a REJECTED/CONFLICT outcome. If another request already committed this op (race), answer with ITS result."""
    try:
        db.add(row); db.commit()
        return _result(row)
    except Exception:                                                  # noqa: BLE001
        db.rollback()
        prior = _lookup(db, op_id, key)
        if prior:
            return _result(prior, duplicate=True, op_id=op_id)
        return _retryable(op_id)


def _owned_by(prior: SyncOperation, p: Principal, inst: str) -> bool:
    """An operation id belongs to the principal that first sent it. Older rows (no owner stored) fall back to the installation hash.
    Without this, worker B re-using worker A's op_id was answered with A's stored result (leaking its conflict details) and B's own
    data was silently discarded while B was told it was acknowledged."""
    if p.is_privileged:
        return True
    owner = (prior.result or {}).get("owner")
    return owner == p.name if owner else prior.installation_hash == inst


def _id_in_use(op_id: str, index: int) -> dict:
    return dict(op_id=op_id, index=index, status="REJECTED", acknowledged=False, duplicate=False, server_version=None, error_code="OPERATION_ID_IN_USE",
                error_message="this operation id was already used by another account; generate a new one", conflict=None, warnings=[])


def _retryable(op_id: str) -> dict:
    return dict(op_id=op_id, status="FAILED_RETRYABLE", acknowledged=False, duplicate=False, server_version=None, error_code="TEMPORARY_FAILURE",
                error_message="operation was not stored; resend it", conflict=None, warnings=[])


def _process_one(db: Session, p: Principal, op: SyncOpIn, key: str, base: dict, settings: Settings) -> dict:
    try:
        with db.begin_nested():
            ver, meta, warnings = _apply(db, p, op, settings)
            row = SyncOperation(**base, status="ACKNOWLEDGED", acknowledged_at=utcnow(), server_version=ver, conflict=meta if meta else None, result=dict(warnings=warnings, owner=p.name))
            db.add(row); db.flush()
        db.commit()                                                    # acknowledged ONLY if this commit succeeds
        return _result(row)
    except _Conflict as c:
        db.rollback()
        return _store_outcome(db, SyncOperation(**base, status="CONFLICT", error_code="VERSION_CONFLICT", conflict=c.meta,
                                                result=dict(message="stale update touches protected fields; not applied", owner=p.name)), op.op_id, key)
    except (DomainError, ValidationError, ValueError) as e:
        db.rollback()
        msg = e.message if isinstance(e, DomainError) else str(e)[:300]
        return _store_outcome(db, SyncOperation(**base, status="REJECTED", error_code=getattr(e, "code", "INVALID"), result=dict(message=msg, owner=p.name)), op.op_id, key)
    except Exception:                                                  # noqa: BLE001  commit/DB failure or a concurrent identical push
        db.rollback()
        prior = _lookup(db, op.op_id, key)
        return _result(prior, duplicate=True, op_id=op.op_id) if prior else _retryable(op.op_id)



def push(db: Session, p: Principal, req: SyncPushIn, settings: Settings) -> dict:
    inst = hash_installation(req.installation_id, settings.device_hash_salt)
    results, acked = [], 0
    for i, raw in enumerate(req.operations):
        try:
            op = SyncOpIn.model_validate(raw)
        except ValidationError as e:
            results.append(dict(op_id=raw.get("op_id") if isinstance(raw, dict) else None, index=i, status="REJECTED", acknowledged=False, duplicate=False,
                                server_version=None, error_code="MALFORMED_OPERATION", error_message="; ".join("%s: %s" % (".".join(map(str, x["loc"])), x["msg"]) for x in e.errors())[:300],
                                conflict=None, warnings=[]))
            continue
        key = op.idempotency_key or op.op_id
        prior = _lookup(db, op.op_id, key)
        if prior and not _owned_by(prior, p, inst):
            results.append(_id_in_use(op.op_id, i)); continue
        if prior and prior.status == "REJECTED":
            try:
                db.delete(prior); db.flush(); prior = None             # a rejected op changed nothing; allow re-evaluation (e.g. parent now exists)
            except Exception:                                          # noqa: BLE001
                db.rollback(); results.append(_result(prior, duplicate=True, op_id=op.op_id)); continue
        if prior:                                                      # repeated request -> same answer, no second write
            results.append(_result(prior, duplicate=True, op_id=op.op_id)); continue
        base = dict(op_id=op.op_id, idempotency_key=key, installation_hash=inst, entity_type=op.entity_type, entity_id=op.entity_id, op_type=op.op_type,
                    base_version=op.base_version, client_created_at=_naive(op.client_created_at), client_updated_at=_naive(op.client_updated_at), received_at=utcnow())
        results.append(_process_one(db, p, op, key, base, settings))
        if results[-1]["acknowledged"] and not results[-1]["duplicate"]:
            acked += 1
    return dict(received=len(req.operations), acknowledged_count=acked, results=results,
                note="Only operations with acknowledged=true are safely stored on the server; keep all others pending on the device and retry.")


def pull(db: Session, p: Principal, *, since: Optional[dt.datetime], entity_types: List[str], limit: int) -> dict:
    out: Dict[str, Any] = dict(server_time=utcnow().isoformat() + "Z")
    since = _naive(since)
    if "household" in entity_types:
        q = select(Household).order_by(Household.last_updated, Household.household_id).limit(limit)
        if since: q = q.where(Household.last_updated > since)
        if p.role == "worker": q = q.where(Household.assigned_worker_id == p.worker_id)
        out["households"] = db.scalars(q).all()
    if "visit" in entity_types:
        q = select(Visit).order_by(Visit.updated_at, Visit.visit_id).limit(limit)
        if since: q = q.where(Visit.updated_at > since)
        if p.role == "worker": q = q.where(Visit.worker_id == p.worker_id)
        out["visits"] = db.scalars(q).all()
    if "referral" in entity_types:
        q = select(Referral).order_by(Referral.last_updated, Referral.referral_id).limit(limit)
        if since: q = q.where(Referral.last_updated > since)
        if p.role == "worker":
            q = q.join(Household, Household.household_id == Referral.household_id).where(Household.assigned_worker_id == p.worker_id)
        out["referrals"] = db.scalars(q).all()
    return out


def status(db: Session, p: Principal, settings: Settings, installation_id: Optional[str]) -> dict:
    q = select(SyncOperation)
    if installation_id:
        q = q.where(SyncOperation.installation_hash == hash_installation(installation_id, settings.device_hash_salt))
    elif p.role == "worker":
        raise Forbidden("installation_id is required")
    rows = db.scalars(q).all()
    from collections import Counter
    c = Counter(r.status for r in rows)
    acks = [r.acknowledged_at for r in rows if r.acknowledged_at]
    return dict(total_operations=len(rows), by_status=dict(c), last_acknowledged_at=(max(acks).isoformat() + "Z") if acks else None,
                conflicts=c.get("CONFLICT", 0), rejected=c.get("REJECTED", 0))
