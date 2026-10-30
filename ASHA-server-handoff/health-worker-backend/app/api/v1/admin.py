from typing import List, Optional

from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.config import Settings, get_settings
from app.core.security import Principal, require_roles
from app.db.session import get_db
from app.schemas.dashboard import (EmptyIn, PageOut, PhoneKeyCreatedOut, PhoneKeyIn, PhoneKeyOut, ServerInfoOut, SettingsPatchIn,
                                   UserCreateIn, UserOut, UserPatchIn)
from app.services.accounts import server_info
from app.services.accounts import service as accounts
from app.services.dashboard.service import as_jsonable

router = APIRouter(prefix="/admin", tags=["admin"])
admin_only = require_roles("admin")
staff = require_roles("admin", "supervisor")


def _base(request: Request) -> str:
    return str(request.base_url).rstrip("/")


@router.get("/users", response_model=List[UserOut], summary="All website accounts (admin)")
def users(db: Session = Depends(get_db), _: Principal = Depends(admin_only)):
    return accounts.list_users(db)


@router.post("/users", response_model=UserOut, status_code=201, summary="Create a website account (admin). Password stored as argon2id.")
def create_user(body: UserCreateIn, db: Session = Depends(get_db), p: Principal = Depends(admin_only)):
    u = accounts.create_user(db, p, **body.model_dump())
    db.commit()
    return u


@router.patch("/users/{user_id}", response_model=UserOut, summary="Change role, activate/deactivate or reset the password (admin). Ends the user's sessions.")
def patch_user(user_id: int, body: UserPatchIn, db: Session = Depends(get_db), p: Principal = Depends(admin_only)):
    u = accounts.update_user(db, p, user_id, **body.model_dump(exclude_unset=True))
    db.commit()
    return u


@router.get("/phones", response_model=List[PhoneKeyOut], summary="Phone API keys (admin). The keys themselves are never shown again.")
def phones(db: Session = Depends(get_db), _: Principal = Depends(admin_only)):
    return accounts.list_phone_keys(db)


@router.post("/phones", response_model=PhoneKeyCreatedOut, status_code=201,
             summary="Generate a phone API key (admin). The key is in this response ONLY; the server keeps a hash.")
def create_phone(body: PhoneKeyIn, request: Request, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(admin_only)):
    row, key = accounts.create_phone_key(db, p, worker_id=body.worker_id, label=body.label)
    db.commit()
    url, _ = server_info.resolve_public_url(db, s, _base(request))
    return PhoneKeyCreatedOut(**PhoneKeyOut.model_validate(row, from_attributes=True).model_dump(), api_key=key, server_url=url)


@router.post("/phones/{key_id}/revoke", response_model=PhoneKeyOut, summary="Revoke a phone key (admin). The phone gets 401 from its next request.")
def revoke_phone(key_id: str, body: Optional[EmptyIn] = None, *, db: Session = Depends(get_db), p: Principal = Depends(admin_only)):
    row = accounts.revoke_phone_key(db, p, key_id)
    db.commit()
    return row


@router.get("/audit", response_model=PageOut, summary="Admin-action audit: sign-ins, account and key changes, exports, phone-number reveals (admin)")
def audit(action: Optional[str] = Query(None, max_length=32), limit: int = LIMIT, offset: int = OFFSET, db: Session = Depends(get_db),
          _: Principal = Depends(admin_only)):
    rows, total = accounts.list_audit(db, limit, offset, action)
    return PageOut(items=[as_jsonable(dict(id=r.id, at=r.at, actor=r.actor, action=r.action, target=r.target, details=r.details)) for r in rows],
                   total=total, limit=limit, offset=offset)


@router.get("/server-info", response_model=ServerInfoOut, summary="Public address for phones, whether it answers through the tunnel, and its QR code")
def server_info_route(request: Request, check: bool = True, db: Session = Depends(get_db), s: Settings = Depends(get_settings),
                      _: Principal = Depends(staff)):
    url, source = server_info.resolve_public_url(db, s, _base(request))
    ok, detail = server_info.check(url) if check else (None, "not checked")
    return ServerInfoOut(public_url=url, source=source, reachable=ok, checked_url=(url + "/health") if url else None, detail=detail,
                         qr_svg=server_info.qr_svg(url) if url else None, retention_days=accounts.retention_days(db, s),
                         default_language=accounts.get_setting(db, "default_language", "en") or "en", demo_today=s.demo_today)


@router.patch("/settings", response_model=dict, summary="Change retention, the public address shown to phones, the default language (admin)")
def patch_settings(body: SettingsPatchIn, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(admin_only)):
    ch = body.model_dump(exclude_unset=True)
    for k, v in ch.items():
        accounts.set_setting(db, p, k, "" if v is None else str(v).rstrip("/"))
    db.commit()
    purged = accounts.purge_old_audit(db, s) if "retention_days" in ch else None
    return {"changed": sorted(ch), "purged": purged}
