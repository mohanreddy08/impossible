import datetime as dt
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.config import Settings, get_settings
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.common import Page
from app.schemas.domain import Category, FollowUpOut, VisitCreate, VisitOut, VisitStatus, VisitUpdate
from app.services.visits import service

router = APIRouter(tags=["visits"])


@router.get("/visits", response_model=Page[VisitOut])
def list_visits(worker_id: Optional[str] = None, household_id: Optional[str] = None, status: Optional[VisitStatus] = None, category: Optional[Category] = None,
                date_from: Optional[dt.date] = None, date_to: Optional[dt.date] = None, limit: int = LIMIT, offset: int = OFFSET,
                db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    rows, total = service.list_visits(db, p, worker_id=worker_id, household_id=household_id, status=status, category=category, date_from=date_from, date_to=date_to, limit=limit, offset=offset)
    return Page(items=rows, total=total, limit=limit, offset=offset)


@router.post("/visits", response_model=VisitOut, status_code=201)
def create_visit(body: VisitCreate, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    v = service.create(db, p, body, s); db.commit(); return v


@router.patch("/visits/{visit_id}", response_model=VisitOut)
def patch_visit(visit_id: str, body: VisitUpdate, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    v = service.update(db, p, visit_id, body, s); db.commit(); return v


@router.get("/follow-ups", response_model=Page[FollowUpOut], summary="Outstanding follow-up tasks (PLANNED visits) with the reason each is listed")
def list_follow_ups(bucket: Optional[str] = None, as_of: Optional[dt.date] = None, on_date: Optional[dt.date] = None, worker_id: Optional[str] = None,
                    household_id: Optional[str] = None, category: Optional[Category] = None, limit: int = LIMIT, offset: int = OFFSET,
                    db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    if bucket not in (None, "OVERDUE", "DUE_TODAY", "UPCOMING"):
        from app.core.errors import DomainError
        raise DomainError("bucket must be OVERDUE, DUE_TODAY or UPCOMING", code="BAD_FILTER", status_code=422)
    items, total = service.followups(db, p, s, as_of=as_of, bucket=bucket, worker_id=worker_id, on_date=on_date, household_id=household_id, category=category, limit=limit, offset=offset)
    return Page(items=items, total=total, limit=limit, offset=offset)
