"""Authentication/authorisation hooks.

Three kinds of caller, checked in this order:
  1. website users: a short-lived JWT session (cookie set by POST /api/v1/auth/login, or `Authorization: Bearer <token>`).
     Cookie-authenticated writes must carry `X-Requested-With: fetch` (a custom header a cross-site form cannot send: CSRF guard).
  2. phones: `X-API-Key` = a per-phone key created on the website (stored hashed, revocable), or a static key from API_KEYS.
  3. auth_mode=disabled: everything else acts as a local-development admin (refused in production).

auth_mode=disabled  -> every request acts as a local-development admin. NEVER use outside local development
                       (startup refuses app_env=production with auth disabled).
auth_mode=api_key   -> clients send X-API-Key. Keys come from API_KEYS="role|worker_id|key;..." (roles: worker, admin,
                       hospital). A 'worker' key is bound to one worker_id and only sees that worker's records.
Replace with OAuth2/JWT or your identity provider before a real deployment."""
import hashlib
import hmac
import logging
from typing import List

from typing import Optional

from fastapi import Depends, Request, Response
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import DomainError, Forbidden, TooManyRequests, Unauthorized
from app.db.session import get_db
from app.services.accounts import service as accounts
from app.core.hardening import auth_failures, client_ip, key_fingerprint
from app.core.principal import Principal, hash_installation, scoped_worker  # noqa: F401  (re-exported)


def parse_keys(raw: str) -> List[tuple]:
    out = []
    for part in [p for p in raw.split(";") if p.strip()]:
        bits = part.strip().split("|")
        if len(bits) != 3 or bits[0] not in ("worker", "admin", "hospital") or not bits[2]:
            raise ValueError("API_KEYS entries must look like role|worker_id|key")
        if bits[0] == "worker" and not bits[1]:
            raise ValueError("worker keys need a worker_id")
        out.append((bits[0], bits[1] or None, bits[2]))
    return out


SESSION_COOKIE = "asha_session"
SAFE_METHODS = ("GET", "HEAD", "OPTIONS")


def set_session_cookie(response: Response, request: Request, token: str, max_age: int) -> None:
    secure = request.url.scheme == "https"
    response.set_cookie(SESSION_COOKIE, token, max_age=max_age, httponly=True, secure=secure, samesite="strict", path="/")


def session_user(request: Request, db: Session, settings: Settings, response: Optional[Response] = None):
    """(user, principal) from the session cookie or bearer token, or (None, None). Raises 401 for a present but invalid token."""
    auth = request.headers.get("Authorization", "")
    from_cookie = False
    token = auth[7:].strip() if auth.lower().startswith("bearer ") else None
    if not token:
        token = request.cookies.get(SESSION_COOKIE)
        from_cookie = bool(token)
    if not token:
        return None, None
    try:
        user, claims = accounts.read_token(db, token, settings)
    except Unauthorized:
        if settings.auth_mode == "disabled" and not auth:
            return None, None          # a stale cookie in local development: fall back to the dev principal
        raise
    if from_cookie and request.method not in SAFE_METHODS and request.headers.get("X-Requested-With") != "fetch":
        raise DomainError("missing X-Requested-With header (cross-site request refused)", code="CSRF_CHECK_FAILED", status_code=403)
    if response is not None and from_cookie:
        import time
        remaining = claims["exp"] - time.time()
        if remaining < settings.session_minutes * 30:                  # less than half left: renew while the user is active
            new, ttl = accounts.issue_token(user, settings)
            set_session_cookie(response, request, new, ttl)
    return user, accounts.principal_for_user(user)


def get_principal(request: Request, response: Response, settings: Settings = Depends(get_settings), db: Session = Depends(get_db)) -> Principal:
    _, user_p = session_user(request, db, settings, response)
    if user_p:
        return user_p
    supplied = request.headers.get("X-API-Key", "")
    if settings.auth_mode == "disabled" and not supplied:
        return Principal("admin", None, "dev-anonymous")
    fails, ip = auth_failures(request.app), client_ip(request.scope)
    if settings.failed_auth_per_minute > 0 and fails.count(ip) >= settings.failed_auth_per_minute:
        raise TooManyRequests("too many failed attempts from this address; try again in a minute")   # even a correct key waits: brute-force protection
    found = None
    for role, wid, key in parse_keys(settings.api_keys):
        if hmac.compare_digest(hashlib.sha256(supplied.encode()).digest(), hashlib.sha256(key.encode()).digest()):
            found = Principal(role, wid, "%s:%s" % (role, wid or "*"))
    if not found and supplied:
        found = accounts.principal_for_phone_key(db, supplied)
    if not found and settings.auth_mode == "disabled":
        return Principal("admin", None, "dev-anonymous")
    if not found:
        fails.add(ip)
        # never the key itself: only a short one-way fingerprint so repeated guesses can be correlated
        logging.getLogger("security").warning("auth failure ip=%s key_fp=%s path=%s", ip, key_fingerprint(supplied), request.url.path)
        raise Unauthorized("missing or invalid API key")
    return found


def require_roles(*roles):
    """Principal roles: worker (ASHA phone or ASHA website user), supervisor, admin, hospital."""
    def dep(p: Principal = Depends(get_principal)) -> Principal:
        if p.role not in roles:
            raise Forbidden("role '%s' may not perform this action" % p.role)
        return p
    return dep
