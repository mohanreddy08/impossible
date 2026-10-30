from typing import Optional

from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import TooManyRequests, Unauthorized
from app.core.hardening import auth_failures, client_ip
from app.core.security import SESSION_COOKIE, Principal, get_principal, session_user, set_session_cookie
from app.db.session import get_db
from app.schemas.dashboard import EmptyIn, LoginIn, LoginOut, UserOut
from app.services.accounts import service as accounts

router = APIRouter(prefix="/auth", tags=["auth (website)"])


@router.post("/login", response_model=LoginOut,
             summary="Website sign-in: sets a short-lived HttpOnly session cookie and also returns the token (for Bearer use). Open endpoint.")
def login(body: LoginIn, request: Request, response: Response, db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    fails, ip = auth_failures(request.app), client_ip(request.scope)
    if s.failed_auth_per_minute > 0 and fails.count("login:" + ip) >= s.failed_auth_per_minute:
        raise TooManyRequests("too many failed sign-ins from this address; try again in a minute")
    try:
        u = accounts.login(db, body.username, body.password, s)
    except Unauthorized:
        fails.add("login:" + ip)
        raise
    token, ttl = accounts.issue_token(u, s)
    set_session_cookie(response, request, token, ttl)
    return LoginOut(access_token=token, expires_in=ttl, user=UserOut.model_validate(u))


@router.post("/logout", response_model=dict, summary="End this website session (and every other open session of this user)")
def logout(body: Optional[EmptyIn] = None, *, request: Request, response: Response, db: Session = Depends(get_db), s: Settings = Depends(get_settings),
           p: Principal = Depends(get_principal)):
    u, _ = session_user(request, db, s)
    if u:
        u.token_version += 1
        accounts.audit(db, p.name, "logout", u.username)
        db.commit()
    response.delete_cookie(SESSION_COOKIE, path="/")
    return {"status": "signed out"}


@router.get("/me", response_model=dict, summary="Who is signed in (role and worker scope)")
def me(request: Request, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    u, _ = session_user(request, db, s)
    return {"principal": p.name, "role": p.role, "worker_id": p.worker_id, "user": UserOut.model_validate(u).model_dump(mode="json") if u else None}
