import datetime as dt
from typing import Optional

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.config import Settings, get_settings
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.common import Page
from app.schemas.domain import Category, HouseholdCreate, HouseholdOut, HouseholdUpdate
from app.services.households import service

router = APIRouter(prefix="/households", tags=["households"])


@router.get("", response_model=Page[HouseholdOut])
def list_households(q: Optional[str] = None, village_id: Optional[str] = None, worker_id: Optional[str] = None, status: Optional[str] = None,
                    category: Optional[Category] = None, due_before: Optional[dt.date] = None, limit: int = LIMIT, offset: int = OFFSET,
                    db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    rows, total = service.list_households(db, p, q=q, village_id=village_id, worker_id=worker_id, status=status, category=category, due_before=due_before, limit=limit, offset=offset)
    return Page(items=rows, total=total, limit=limit, offset=offset)


@router.get("/{household_id}", response_model=HouseholdOut)
def get_household(household_id: str, db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    return service.get(db, p, household_id)


@router.post("", response_model=HouseholdOut, status_code=201)
def create_household(body: HouseholdCreate, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    h = service.create(db, p, body, s); db.commit(); return h


@router.patch("/{household_id}", response_model=HouseholdOut)
def patch_household(household_id: str, body: HouseholdUpdate, db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    h = service.update(db, p, household_id, body); db.commit(); return h
