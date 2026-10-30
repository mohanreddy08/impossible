import datetime as dt
from typing import List, Optional, Tuple

from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import Conflict, Forbidden, NotFound
from app.core.principal import Principal, scoped_worker
from app.db.base import utcnow
from app.db.models import Household, Visit
from app.repositories import audit
from app.schemas.domain import HouseholdCreate, HouseholdUpdate
from app.services._common import check_version, new_id, today


def get(db: Session, p: Principal, household_id: str) -> Household:
    h = db.get(Household, household_id)
    if not h or (p.role == "worker" and h.assigned_worker_id != p.worker_id):
        raise NotFound("household not found")           # 404 (not 403) so existence is not leaked
    return h


def list_households(db: Session, p: Principal, *, q=None, village_id=None, worker_id=None, status=None, category=None,
                    due_before: Optional[dt.date] = None, limit=50, offset=0) -> Tuple[List[Household], int]:
    stmt = select(Household)
    w = scoped_worker(p, worker_id)
    if w: stmt = stmt.where(Household.assigned_worker_id == w)
    if village_id: stmt = stmt.where(Household.village_id == village_id)
    if status: stmt = stmt.where(Household.record_status == status)
    if category: stmt = stmt.where(Household.eligible_followup_categories.like("%|" + category + "|%"))
    if due_before: stmt = stmt.where(Household.next_visit_due_date <= due_before)
    if q: stmt = stmt.where(Household.household_id.like("%" + q.replace("%", "") + "%"))
    total = db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = db.scalars(stmt.order_by(Household.household_id).limit(limit).offset(offset)).all()
    return rows, total


def _cats(cats): return "|" + "|".join(dict.fromkeys(cats)) + "|"


def create(db: Session, p: Principal, data: HouseholdCreate, settings: Settings, source="api") -> Household:
    if p.role == "worker" and data.assigned_worker_id != p.worker_id:
        raise Forbidden("workers may only create households assigned to themselves")
    hid = data.household_id or new_id("HH")
    if db.get(Household, hid):
        raise Conflict("household_id already exists", code="DUPLICATE_ID")
    cats = data.eligible_followup_categories
    if data.scheduled_followup_category and data.scheduled_followup_category not in cats:
        raise Conflict("scheduled_followup_category must be one of the household's eligible categories", code="CATEGORY_NOT_ELIGIBLE", status_code=422)
    h = Household(household_id=hid, village_id=data.village_id, assigned_worker_id=data.assigned_worker_id,
                  household_member_count=data.household_member_count, eligible_followup_categories=_cats(cats),
                  scheduled_followup_category=data.scheduled_followup_category, record_status="NO_VISIT_DUE", last_updated=utcnow(), version=1)
    db.add(h)
    audit.record(db, p.name, "CREATE", "household", hid, None, 1, source)
    db.flush()
    return h


def update(db: Session, p: Principal, household_id: str, data: HouseholdUpdate, source="api") -> Household:
    h = get(db, p, household_id)
    check_version(h.version, data.version, "household")
    changes = data.model_dump(exclude_unset=True, exclude={"version"})
    if p.role == "worker" and changes.get("assigned_worker_id", p.worker_id) != p.worker_id:
        raise Forbidden("workers may not reassign households")
    if "eligible_followup_categories" in changes:
        h.eligible_followup_categories = _cats(changes.pop("eligible_followup_categories"))
        changes["eligible_followup_categories"] = True
    cats = [c for c in h.eligible_followup_categories.split("|") if c]
    sched = changes.get("scheduled_followup_category")
    if sched and sched not in cats:
        raise Conflict("scheduled_followup_category must be one of the household's eligible categories", code="CATEGORY_NOT_ELIGIBLE", status_code=422)
    for k, v in changes.items():
        if k != "eligible_followup_categories": setattr(h, k, v)
    h.version += 1
    h.last_updated = utcnow()
    audit.record(db, p.name, "UPDATE", "household", h.household_id, changes.keys(), h.version, source)
    db.flush()
    return h
