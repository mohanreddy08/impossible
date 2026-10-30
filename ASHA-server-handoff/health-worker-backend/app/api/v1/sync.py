import datetime as dt
from typing import Optional

from fastapi import APIRouter, Depends, Header, Query, Request
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import DomainError
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.api import SyncPullOut, SyncPushOut, SyncStatusOut
from app.core.principal import hash_installation
from app.services.accounts import service as accounts
from app.services.synchronization import service

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("/push", response_model=SyncPushOut, summary="Upload offline operations (idempotent; per-operation acknowledgement)")
def push(body: service.SyncPushIn, request: Request, db: Session = Depends(get_db), p: Principal = Depends(get_principal),
         s: Settings = Depends(get_settings)):
    out = service.push(db, p, body, s)
    try:                                       # per-phone sync status for the website; never affects the sync answer
        accounts.record_phone_sync(db, p, hash_installation(body.installation_id, s.device_hash_salt), request.headers.get("User-Agent"),
                                   out["received"], out["acknowledged_count"])
    except Exception:                          # noqa: BLE001
        db.rollback()
    return out


@router.get("/pull", response_model=SyncPullOut, summary="Download records changed since a timestamp")
def pull(since: Optional[dt.datetime] = None, entity_types: str = "household,visit,referral", limit: int = Query(200, ge=1, le=500),
         db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    types = [t.strip() for t in entity_types.split(",") if t.strip()]
    if not types or any(t not in ("household", "visit", "referral") for t in types):
        raise DomainError("entity_types must be a comma list of household,visit,referral", code="BAD_FILTER", status_code=422)
    return service.pull(db, p, since=since, entity_types=types, limit=limit)


@router.get("/status", response_model=SyncStatusOut, summary="Operation counts for one installation (id sent in the X-Installation-Id header, never in the URL)")
def status(installation_id: Optional[str] = Header(None, alias="X-Installation-Id"), db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    return service.status(db, p, s, installation_id)
