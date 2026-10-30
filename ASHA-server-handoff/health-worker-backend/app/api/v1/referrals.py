import datetime as dt
from typing import Optional

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.config import Settings, get_settings
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.common import Page
from app.schemas.domain import RecordState, ReferralCreate, ReferralOut, ReferralStatus, ReferralUpdate, ServiceCategory
from app.services.referrals import service

router = APIRouter(prefix="/referrals", tags=["referrals"])


@router.get("", response_model=Page[ReferralOut])
def list_referrals(facility_id: Optional[str] = None, status: Optional[ReferralStatus] = None, household_id: Optional[str] = None,
                   service_category: Optional[ServiceCategory] = None, record_state: Optional[RecordState] = None, created_from: Optional[dt.date] = None,
                   created_to: Optional[dt.date] = None, limit: int = LIMIT, offset: int = OFFSET, db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    rows, total = service.list_referrals(db, p, facility_id=facility_id, status=status, household_id=household_id, service_category=service_category,
                                         record_state=record_state, created_from=created_from, created_to=created_to, limit=limit, offset=offset)
    return Page(items=rows, total=total, limit=limit, offset=offset)


@router.post("", response_model=ReferralOut, status_code=201)
def create_referral(body: ReferralCreate, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    r, _ = service.create(db, p, body, s); db.commit(); return r


@router.patch("/{referral_id}", response_model=ReferralOut)
def patch_referral(referral_id: str, body: ReferralUpdate, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    r = service.update(db, p, referral_id, body, s); db.commit(); return r
