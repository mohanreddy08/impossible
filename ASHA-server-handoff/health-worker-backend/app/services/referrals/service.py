import datetime as dt
from typing import List, Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import Conflict, DomainError, Forbidden, NotFound
from app.core.principal import Principal
from app.db.base import utcnow
from app.db.models import Facility, Household, Referral, Visit
from app.domain import REFERRAL_TRANSITIONS
from app.repositories import audit
from app.schemas.domain import ReferralCreate, ReferralUpdate
from app.services._common import check_version, new_id, today


def _scope(p: Principal, hh_worker: str):
    return p.role != "worker" or hh_worker == p.worker_id


def get(db: Session, p: Principal, referral_id: str) -> Referral:
    r = db.get(Referral, referral_id)
    if r:
        h = db.get(Household, r.household_id)
        if h and not _scope(p, h.assigned_worker_id):
            r = None
    if not r:
        raise NotFound("referral not found")
    return r


def list_referrals(db: Session, p: Principal, *, facility_id=None, status=None, household_id=None, service_category=None, record_state=None,
                   created_from: Optional[dt.date] = None, created_to: Optional[dt.date] = None, limit=50, offset=0) -> Tuple[List[Referral], int]:
    stmt = select(Referral)
    if p.role == "worker":
        stmt = stmt.join(Household, Household.household_id == Referral.household_id).where(Household.assigned_worker_id == p.worker_id)
    for col, val in ((Referral.facility_id, facility_id), (Referral.referral_status, status), (Referral.household_id, household_id),
                     (Referral.service_category, service_category), (Referral.record_state, record_state)):
        if val: stmt = stmt.where(col == val)
    if created_from: stmt = stmt.where(Referral.referral_created_date >= created_from)
    if created_to: stmt = stmt.where(Referral.referral_created_date <= created_to)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    return db.scalars(stmt.order_by(Referral.referral_created_date.desc(), Referral.referral_id).limit(limit).offset(offset)).all(), total


def _mirror_visit(db: Session, r: Referral):
    v = db.get(Visit, r.visit_id)
    if v and r.record_state == "ACTIVE":
        v.referral_id, v.referral_status = r.referral_id, r.referral_status
    elif v and v.referral_id == r.referral_id:           # cancelled/invalid: visit no longer shows a live referral
        v.referral_id, v.referral_status = None, "NONE"
    if v:
        v.version += 1
        v.updated_at = utcnow()


def create(db: Session, p: Principal, data: ReferralCreate, settings: Settings, source="api", allow_duplicate_flag=False) -> Tuple[Referral, Optional[str]]:
    """Returns (referral, duplicate_of). With allow_duplicate_flag (sync path) a duplicate is stored as state DUPLICATE
    instead of being rejected, so no client data is lost."""
    h = db.get(Household, data.household_id)
    if not h or not _scope(p, h.assigned_worker_id):
        raise NotFound("household not found")
    v = db.get(Visit, data.visit_id)
    if not v or v.household_id != h.household_id:
        raise DomainError("visit not found for this household", code="VISIT_MISMATCH", status_code=422)
    if v.visit_status != "COMPLETED":
        raise DomainError("a referral can only be recorded against a COMPLETED visit", code="VISIT_NOT_COMPLETED", status_code=422)
    if not db.get(Facility, data.facility_id):
        raise DomainError("unknown facility_id", code="UNKNOWN_FACILITY", status_code=422)
    created = data.referral_created_date or today(settings)
    if created > today(settings):
        raise DomainError("referral_created_date cannot be in the future", code="FUTURE_DATE", status_code=422)
    if data.referral_status == "PLANNED":
        if not data.planned_visit_date or data.planned_visit_date < created:
            raise DomainError("PLANNED referrals need planned_visit_date on/after the creation date", code="PLANNED_DATE_REQUIRED", status_code=422)
    elif data.planned_visit_date:
        raise DomainError("RECOMMENDED referrals must not have planned_visit_date", code="PLANNED_DATE_NOT_ALLOWED", status_code=422)
    rid = data.referral_id or new_id("REF")
    if db.get(Referral, rid):
        raise Conflict("referral_id already exists", code="DUPLICATE_ID")
    active = db.scalar(select(Referral).where(Referral.household_id == h.household_id, Referral.visit_id == v.visit_id,
                                              Referral.service_category == data.service_category, Referral.record_state == "ACTIVE"))
    state, dup = "ACTIVE", None
    if active:
        if not allow_duplicate_flag:
            raise Conflict("an active referral already exists for this visit and service", code="DUPLICATE_REFERRAL", details=dict(existing_referral_id=active.referral_id))
        state, dup = "DUPLICATE", active.referral_id
    r = Referral(referral_id=rid, household_id=h.household_id, visit_id=v.visit_id, facility_id=data.facility_id, service_category=data.service_category,
                 referral_created_date=created, planned_visit_date=data.planned_visit_date, referral_status=data.referral_status,
                 attendance_confirmed=False, record_state=state, duplicate_of=dup, last_updated=utcnow(), version=1)
    db.add(r); db.flush()
    if state == "ACTIVE":
        _mirror_visit(db, r)
    audit.record(db, p.name, "CREATE", "referral", rid, None, 1, source)
    return r, dup


def update(db: Session, p: Principal, referral_id: str, data: ReferralUpdate, settings: Settings, source="api") -> Referral:
    r = get(db, p, referral_id)
    check_version(r.version, data.version, "referral")
    ch = data.model_dump(exclude_unset=True, exclude={"version"})
    new_status = ch.get("referral_status", r.referral_status)
    if r.record_state != "ACTIVE":
        raise Conflict("referral is %s and can no longer change" % r.record_state, code="REFERRAL_NOT_ACTIVE")
    if new_status not in REFERRAL_TRANSITIONS[r.referral_status]:
        raise Conflict("transition %s -> %s is not allowed" % (r.referral_status, new_status), code="INVALID_TRANSITION")
    if ch.get("record_state"):
        if r.referral_status == "ATTENDANCE_CONFIRMED":
            raise Conflict("a referral with confirmed attendance cannot be cancelled/invalidated", code="INVALID_TRANSITION")
        r.record_state = ch["record_state"]
    if new_status == "PLANNED":
        pv = ch.get("planned_visit_date", r.planned_visit_date)
        if not pv or pv < r.referral_created_date:
            raise DomainError("PLANNED needs planned_visit_date on/after creation date", code="PLANNED_DATE_REQUIRED", status_code=422)
        r.planned_visit_date = pv
    elif "planned_visit_date" in ch and new_status == "RECOMMENDED":
        raise DomainError("RECOMMENDED referrals must not have planned_visit_date", code="PLANNED_DATE_NOT_ALLOWED", status_code=422)
    if new_status == "ATTENDANCE_CONFIRMED" and r.referral_status != "ATTENDANCE_CONFIRMED":
        if not p.is_privileged:                                   # admin, hospital or a supervisor (ANM / Medical Officer)
            raise Forbidden("only a hospital/admin principal may confirm attendance (it must come from a hospital attendance record)")
        rec, cd = ch.get("attendance_record_id"), ch.get("attendance_confirmation_date")
        if not rec or not cd:
            raise DomainError("attendance confirmation requires attendance_record_id and attendance_confirmation_date", code="ATTENDANCE_RECORD_REQUIRED", status_code=422)
        if cd < r.planned_visit_date or cd > today(settings):
            raise DomainError("attendance_confirmation_date must be between the planned date and today", code="CONFIRMATION_DATE_ORDER", status_code=422)
        r.attendance_confirmed, r.attendance_confirmation_date, r.attendance_record_id = True, cd, rec
    elif r.referral_status == "ATTENDANCE_CONFIRMED" and any(k in ch for k in ("planned_visit_date", "attendance_confirmation_date", "attendance_record_id")):
        raise Conflict("confirmed attendance records are immutable", code="CONFIRMED_IMMUTABLE")
    r.referral_status = new_status
    r.version += 1
    r.last_updated = utcnow()
    db.flush()
    _mirror_visit(db, r)
    audit.record(db, p.name, "UPDATE", "referral", r.referral_id, ch.keys(), r.version, source)
    db.flush()
    return r
