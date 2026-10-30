import datetime as dt
from typing import List, Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import Conflict, DomainError, NotFound
from app.core.principal import Principal, scoped_worker
from app.db.base import utcnow
from app.db.models import Household, Visit
from app.repositories import audit
from app.schemas.domain import FollowUpOut, VisitCreate, VisitUpdate
from app.services._common import check_version, new_id, today
from app.services.households import service as hh_service

TERMINAL = {"COMPLETED", "CANCELLED"}


def get(db: Session, p: Principal, visit_id: str) -> Visit:
    v = db.get(Visit, visit_id)
    if not v or (p.role == "worker" and v.worker_id != p.worker_id):
        raise NotFound("visit not found")
    return v


def recompute_household(db: Session, household_id: str, settings: Settings, as_of: Optional[dt.date] = None) -> Household:
    """Re-derive last/next visit dates and record_status from the visit history (outstanding tasks recalculated)."""
    as_of = as_of or today(settings)
    h = db.get(Household, household_id)
    last = db.scalar(select(func.max(Visit.actual_visit_date)).where(Visit.household_id == household_id, Visit.visit_status == "COMPLETED"))
    nxt = db.execute(select(Visit.scheduled_date, Visit.visit_reason).where(Visit.household_id == household_id, Visit.visit_status == "PLANNED")
                     .order_by(Visit.scheduled_date, Visit.visit_id).limit(1)).first()
    h.last_visit_date = last
    h.next_visit_due_date = nxt[0] if nxt else None
    h.scheduled_followup_category = nxt[1] if nxt else None
    if nxt:
        h.record_status = "OVERDUE" if nxt[0] < as_of else "DUE_TODAY" if nxt[0] == as_of else "UPCOMING"
    elif last and (as_of - last).days <= settings.recent_completion_days:
        h.record_status = "COMPLETED"
    else:
        h.record_status = "NO_VISIT_DUE"
    h.version += 1
    h.last_updated = utcnow()
    return h


def list_visits(db: Session, p: Principal, *, worker_id=None, household_id=None, status=None, category=None,
                date_from: Optional[dt.date] = None, date_to: Optional[dt.date] = None, limit=50, offset=0) -> Tuple[List[Visit], int]:
    stmt = select(Visit)
    w = scoped_worker(p, worker_id)
    if w: stmt = stmt.where(Visit.worker_id == w)
    if household_id: stmt = stmt.where(Visit.household_id == household_id)
    if status: stmt = stmt.where(Visit.visit_status == status)
    if category: stmt = stmt.where(Visit.visit_reason == category)
    if date_from: stmt = stmt.where(Visit.scheduled_date >= date_from)
    if date_to: stmt = stmt.where(Visit.scheduled_date <= date_to)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    return db.scalars(stmt.order_by(Visit.scheduled_date.desc(), Visit.visit_id).limit(limit).offset(offset)).all(), total


def _validate(status, actual, scheduled, followup, nxt, settings, atime=None):
    if atime is not None and status != "COMPLETED":
        raise DomainError("actual_visit_time is only valid on COMPLETED visits", code="ACTUAL_TIME_NOT_ALLOWED", status_code=422)
    if status == "COMPLETED" and not actual:
        raise DomainError("a COMPLETED visit needs actual_visit_date", code="ACTUAL_DATE_REQUIRED", status_code=422)
    if status != "COMPLETED" and actual:
        raise DomainError("actual_visit_date is only valid on COMPLETED visits", code="ACTUAL_DATE_NOT_ALLOWED", status_code=422)
    if actual and actual > today(settings):
        raise DomainError("actual_visit_date cannot be in the future", code="FUTURE_ACTUAL_DATE", status_code=422)
    if actual and actual < scheduled - dt.timedelta(days=3650):
        raise DomainError("actual_visit_date is implausible", code="IMPLAUSIBLE_DATE", status_code=422)
    if nxt and nxt <= (actual or scheduled):
        raise DomainError("next_followup_date must be after the visit", code="NEXT_DATE_ORDER", status_code=422)
    if followup is False and nxt:
        raise DomainError("next_followup_date given but followup_required is false", code="FOLLOWUP_INCONSISTENT", status_code=422)
    if followup is True and not nxt and status == "COMPLETED":
        raise DomainError("followup_required needs next_followup_date", code="FOLLOWUP_INCONSISTENT", status_code=422)


def create(db: Session, p: Principal, data: VisitCreate, settings: Settings, source="api") -> Visit:
    h = hh_service.get(db, p, data.household_id)
    wid = data.worker_id or h.assigned_worker_id
    if p.role == "worker" and wid != p.worker_id:
        raise DomainError("workers may only create visits for themselves", code="FORBIDDEN", status_code=403)
    vid = data.visit_id or new_id("VIS")
    if db.get(Visit, vid):
        raise Conflict("visit_id already exists", code="DUPLICATE_ID")
    _validate(data.visit_status, data.actual_visit_date, data.scheduled_date, data.followup_required, data.next_followup_date, settings, data.actual_visit_time)
    v = Visit(visit_id=vid, household_id=h.household_id, worker_id=wid, scheduled_date=data.scheduled_date, actual_visit_date=data.actual_visit_date, actual_visit_time=data.actual_visit_time,
              visit_status=data.visit_status, visit_reason=data.visit_reason, followup_required=data.followup_required,
              next_followup_date=data.next_followup_date, referral_status="NONE", recorded_at=utcnow(), updated_at=utcnow(), version=1)
    db.add(v)
    db.flush()
    audit.record(db, p.name, "CREATE", "visit", vid, None, 1, source)
    recompute_household(db, h.household_id, settings)
    db.flush()
    return v


def update(db: Session, p: Principal, visit_id: str, data: VisitUpdate, settings: Settings, source="api") -> Visit:
    v = get(db, p, visit_id)
    check_version(v.version, data.version, "visit")
    ch = data.model_dump(exclude_unset=True, exclude={"version", "create_followup_task"})
    if v.visit_status in TERMINAL and ch.get("visit_status", v.visit_status) != v.visit_status:
        raise Conflict("visit is already %s and cannot change status" % v.visit_status, code="VISIT_FINAL")
    merged = dict(visit_status=v.visit_status, actual=v.actual_visit_date, sched=v.scheduled_date, fu=v.followup_required, nxt=v.next_followup_date)
    merged.update({k: ch[k] for k in ("visit_status",) if k in ch})
    if "actual_visit_date" in ch: merged["actual"] = ch["actual_visit_date"]
    if "scheduled_date" in ch: merged["sched"] = ch["scheduled_date"]
    if "followup_required" in ch: merged["fu"] = ch["followup_required"]
    if "next_followup_date" in ch: merged["nxt"] = ch["next_followup_date"]
    if merged["visit_status"] != "COMPLETED" and "actual_visit_date" not in ch:
        merged["actual"] = None
        v.actual_visit_date = None
        v.actual_visit_time = None
    atime = ch["actual_visit_time"] if "actual_visit_time" in ch else v.actual_visit_time
    _validate(merged["visit_status"], merged["actual"], merged["sched"], merged["fu"], merged["nxt"], settings, atime)
    for k, val in ch.items():
        setattr(v, k, val)
    v.actual_visit_date = merged["actual"]
    v.version += 1
    v.updated_at = utcnow()
    audit.record(db, p.name, "UPDATE", "visit", v.visit_id, ch.keys(), v.version, source)
    db.flush()
    if (v.visit_status == "COMPLETED" and v.followup_required and v.next_followup_date and data.create_followup_task):
        exists = db.scalar(select(func.count()).select_from(Visit).where(Visit.household_id == v.household_id, Visit.visit_status == "PLANNED",
                                                                         Visit.scheduled_date == v.next_followup_date, Visit.visit_reason == v.visit_reason))
        if not exists:
            nv = Visit(visit_id=new_id("VIS"), household_id=v.household_id, worker_id=v.worker_id, scheduled_date=v.next_followup_date, visit_status="PLANNED",
                       visit_reason=v.visit_reason, referral_status="NONE", recorded_at=utcnow(), updated_at=utcnow(), version=1)
            db.add(nv); db.flush()
            audit.record(db, p.name, "CREATE", "visit", nv.visit_id, None, 1, source)
    recompute_household(db, v.household_id, settings)
    db.flush()
    return v


def followups(db: Session, p: Principal, settings: Settings, *, as_of: Optional[dt.date] = None, bucket=None, worker_id=None, on_date=None,
              household_id=None, category=None, limit=100, offset=0) -> Tuple[List[FollowUpOut], int]:
    as_of = as_of or today(settings)
    stmt = select(Visit).where(Visit.visit_status == "PLANNED")
    w = scoped_worker(p, worker_id)
    if w: stmt = stmt.where(Visit.worker_id == w)
    if household_id: stmt = stmt.where(Visit.household_id == household_id)
    if category: stmt = stmt.where(Visit.visit_reason == category)
    if on_date: stmt = stmt.where(Visit.scheduled_date == on_date)
    if bucket == "OVERDUE": stmt = stmt.where(Visit.scheduled_date < as_of)
    elif bucket == "DUE_TODAY": stmt = stmt.where(Visit.scheduled_date == as_of)
    elif bucket == "UPCOMING": stmt = stmt.where(Visit.scheduled_date > as_of)
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(Visit.scheduled_date, Visit.visit_id).limit(limit).offset(offset)).all()
    lasts = {hid: d for hid, d in db.execute(select(Household.household_id, Household.last_visit_date).where(Household.household_id.in_([r.household_id for r in rows])))} if rows else {}
    out = []
    for v in rows:
        b = "OVERDUE" if v.scheduled_date < as_of else "DUE_TODAY" if v.scheduled_date == as_of else "UPCOMING"
        days = (as_of - v.scheduled_date).days if b == "OVERDUE" else 0
        when = ("%d day(s) overdue" % days) if b == "OVERDUE" else "due today" if b == "DUE_TODAY" else "due in %d day(s)" % (v.scheduled_date - as_of).days
        last = lasts.get(v.household_id)
        out.append(FollowUpOut(visit_id=v.visit_id, household_id=v.household_id, worker_id=v.worker_id, category=v.visit_reason, scheduled_date=v.scheduled_date,
                               bucket=b, days_overdue=days,
                               explanation="Planned %s visit scheduled for %s is %s as of %s. Last completed visit: %s." % (v.visit_reason, v.scheduled_date, when, as_of, last or "none on record")))
    return out, total
