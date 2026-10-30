"""The supervisor website: server-rendered Jinja2 pages (templates and static files live in ../health-worker-web).

Pages read data through the same service functions as the JSON API, as the signed-in user (same role scoping). Interactive pieces
(map, Ask, reveal, status changes, admin forms) call the JSON API with fetch(); no inline scripts, so the CSP can forbid them."""
import datetime as dt
import json
import os
from typing import Any, Dict, Optional
from urllib.parse import quote, urlparse

from fastapi import APIRouter, Depends, Form, Request
from fastapi.responses import HTMLResponse, RedirectResponse, Response
from fastapi.templating import Jinja2Templates
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import DomainError, TooManyRequests, Unauthorized
from app.core.hardening import auth_failures, client_ip
from app.core.security import SESSION_COOKIE, session_user, set_session_cookie
from app.db.session import get_db
from app.services.accounts import server_info
from app.services.accounts import service as accounts
from app.services.dashboard import service as dash

PAGE_CSP = ("default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; font-src 'self'; "
            "object-src 'none'; base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
LANGS = ("en", "te")
router = APIRouter(include_in_schema=False)
_i18n: Dict[str, Dict[str, str]] = {}
_templates: Dict[str, Jinja2Templates] = {}


def _web_dir(s: Settings) -> str:
    return s.resolved_web_dir


def templates(s: Settings) -> Jinja2Templates:
    d = _web_dir(s)
    if d not in _templates:
        t = Jinja2Templates(directory=os.path.join(d, "templates"))
        t.env.globals["urgency_icon"] = {"URGENT": "▲", "DUE": "■", "THIS_WEEK": "◆", "NONE": "●"}
        t.env.filters["ist"] = _ist
        t.env.filters["tojson_attr"] = lambda v: json.dumps(v, ensure_ascii=False, default=str)
        _templates[d] = t
    return _templates[d]


def _ist(v: Any) -> str:
    """Stored timestamps are naive UTC; show India time (UTC+05:30, no daylight saving)."""
    if not v:
        return "—"
    if isinstance(v, str):
        try:
            v = dt.datetime.fromisoformat(v)
        except ValueError:
            return v
    if isinstance(v, dt.datetime):
        return (v + dt.timedelta(hours=5, minutes=30)).strftime("%d %b %Y %H:%M") + " IST"
    return v.strftime("%d %b %Y") if isinstance(v, dt.date) else str(v)


def strings(s: Settings, lang: str) -> Dict[str, str]:
    if lang not in _i18n:
        base = json.load(open(os.path.join(_web_dir(s), "i18n", "en.json"), encoding="utf-8"))
        if lang != "en":
            base.update(json.load(open(os.path.join(_web_dir(s), "i18n", lang + ".json"), encoding="utf-8")))
        _i18n[lang] = base
    return _i18n[lang]


def _lang(request: Request, user=None, db: Optional[Session] = None) -> str:
    c = request.cookies.get("lang")
    if c in LANGS:
        return c
    if user is not None and user.language in LANGS:
        return user.language
    if db is not None:
        v = accounts.get_setting(db, "default_language", "en")
        if v in LANGS:
            return v
    return "en"


def _render(request: Request, s: Settings, name: str, ctx: dict, status: int = 200, user=None, db=None) -> HTMLResponse:
    lang = _lang(request, user, db)
    tr = strings(s, lang)
    full = dict(request=request, t=lambda k: tr.get(k, k), lang=lang, user=user, demo_today=s.demo_today, path=request.url.path,
                principal=accounts.principal_for_user(user) if user else None, **ctx)
    r = templates(s).TemplateResponse(request, name, full, status_code=status)
    r.headers["content-security-policy"] = PAGE_CSP
    r.headers["referrer-policy"] = "same-origin"      # "no-referrer" (the API default) makes browsers send Origin: null on form posts
    return r


class _Login(Exception):
    def __init__(self, next_url: str):
        self.next_url = next_url


def page_user(request: Request, db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    """Pages always need a real website session (even with AUTH_MODE=disabled, which only relaxes the JSON API)."""
    try:
        u, _ = session_user(request, db, s)
    except (Unauthorized, DomainError):
        u = None
    if not u:
        raise _Login(request.url.path + (("?" + request.url.query) if request.url.query else ""))
    return u


def _safe_next(n: Optional[str]) -> str:
    if not n or not n.startswith("/") or n.startswith("//") or "\\" in n:
        return "/"
    return n


def _same_origin(request: Request) -> bool:
    """CSRF guard for the few HTML form posts: the browser's Origin (or Referer) must be this site."""
    src = request.headers.get("origin") or request.headers.get("referer")
    if not src:
        return True                        # old browsers omit both; SameSite=Strict cookies still protect the session
    o = urlparse(src)
    return o.netloc == request.url.netloc


def install(app) -> None:
    from fastapi.staticfiles import StaticFiles

    s = get_settings()
    static = os.path.join(_web_dir(s), "static")
    if os.path.isdir(static):
        app.mount("/static", StaticFiles(directory=static), name="static")
    app.include_router(router)

    @app.exception_handler(_Login)
    async def _to_login(request: Request, e: _Login):
        return RedirectResponse("/login?next=" + quote(e.next_url, safe="/"), status_code=303)


def error_page(request: Request, code: int, message: str) -> HTMLResponse:
    s = request.app.dependency_overrides.get(get_settings, get_settings)()
    try:
        return _render(request, s, "error.html", dict(code=code, message=message), status=code)
    except Exception:                                             # noqa: BLE001  templates missing: plain text
        return HTMLResponse("<h1>%d</h1>" % code, status_code=code)


# ---------------------------------------------------------------- sign-in
@router.get("/login")
def login_page(request: Request, next: Optional[str] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    return _render(request, s, "login.html", dict(next=_safe_next(next), error=None), db=db)


@router.post("/login")
def login_post(request: Request, username: str = Form(..., max_length=64), password: str = Form(..., max_length=256), next: str = Form("/"),
               db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    if not _same_origin(request):
        return _render(request, s, "login.html", dict(next="/", error="error.csrf"), status=403, db=db)
    fails, ip = auth_failures(request.app), client_ip(request.scope)
    try:
        if s.failed_auth_per_minute > 0 and fails.count("login:" + ip) >= s.failed_auth_per_minute:
            raise TooManyRequests("too many attempts")
        u = accounts.login(db, username, password, s)
    except TooManyRequests:
        return _render(request, s, "login.html", dict(next=_safe_next(next), error="login.locked"), status=429, db=db)
    except Unauthorized:
        fails.add("login:" + ip)
        return _render(request, s, "login.html", dict(next=_safe_next(next), error="login.wrong"), status=401, db=db)
    token, ttl = accounts.issue_token(u, s)
    r = RedirectResponse(_safe_next(next), status_code=303)
    set_session_cookie(r, request, token, ttl)
    return r


@router.post("/logout")
def logout_post(request: Request, db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    try:
        u, _ = session_user(request, db, s)
    except (Unauthorized, DomainError):
        u = None
    if u and _same_origin(request):
        u.token_version += 1
        accounts.audit(db, "user:" + u.username, "logout", u.username)
        db.commit()
    r = RedirectResponse("/login", status_code=303)
    r.delete_cookie(SESSION_COOKIE, path="/")
    return r


@router.get("/lang/{code}")
def set_lang(code: str, request: Request, next: Optional[str] = None):
    r = RedirectResponse(_safe_next(next), status_code=303)
    if code in LANGS:
        r.set_cookie("lang", code, max_age=365 * 86400, samesite="lax", secure=request.url.scheme == "https", path="/")
    return r


# ---------------------------------------------------------------- pages
def _day(request: Request, s: Settings) -> dt.date:
    try:
        return dt.date.fromisoformat(request.query_params.get("date", "")) if request.query_params.get("date") else dash.today(s)
    except ValueError:
        return dash.today(s)


@router.get("/")
def overview(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    return _render(request, s, "overview.html", dict(o=dash.overview(db, p, dash.today(s))), user=u)


@router.get("/visits")
def visits(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    ashas = dash.ashas(db, p)
    w = request.query_params.get("worker_id") or (p.worker_id if p.role == "worker" else (ashas[0]["worker_id"] if ashas else None))
    day = _day(request, s)
    return _render(request, s, "visits.html", dict(ashas=ashas, worker_id=w, day=day, vl=dash.visit_list(db, p, day, w)), user=u)


@router.get("/map")
def map_page(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    vs = [v for v in dash.villages(db, p) if v["has_map"]]
    sel = request.query_params.get("village") or (vs[0]["village_id"] if vs else None)
    return _render(request, s, "map.html", dict(villages=vs, village=sel, day=dash.today(s)), user=u)


@router.get("/households")
def households(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    qp = request.query_params
    page = max(0, int(qp.get("page", "0") or 0)) if (qp.get("page") or "0").isdigit() else 0
    f = dict(village_id=qp.get("village_id") or None, worker_id=qp.get("worker_id") or None, urgency=qp.get("urgency") or None,
             q=(qp.get("q") or "")[:40] or None)
    if p.role == "worker":
        f["worker_id"] = None
    items, total = dash.households(db, p, dash.today(s), limit=50, offset=page * 50, **f)
    return _render(request, s, "households.html", dict(items=items, total=total, page=page, f=f, villages=dash.villages(db, p), ashas=dash.ashas(db, p)), user=u)


@router.get("/households/{household_id}")
def household(household_id: str, request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    h = dash.household_detail(db, p, dash.today(s), household_id)
    return _render(request, s, "household.html", dict(h=h), user=u)


@router.get("/referrals")
def referrals(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    qp = request.query_params
    open_only = qp.get("all") != "1"
    refs, rtotal = dash.referrals_feed(db, p, open_only=open_only, limit=100)
    esc, etotal = dash.escalations(db, p, limit=100)
    return _render(request, s, "referrals.html", dict(refs=refs, rtotal=rtotal, esc=esc, etotal=etotal, open_only=open_only,
                                                      notes=dash.ESCALATION_NOTES, today=dash.today(s)), user=u)


@router.get("/ask")
def ask_page(request: Request, u=Depends(page_user), s: Settings = Depends(get_settings)):
    return _render(request, s, "ask.html", {}, user=u)


@router.get("/reports")
def reports(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    p = accounts.principal_for_user(u)
    return _render(request, s, "reports.html", dict(r=dash.report_summary(db, p, dash.today(s)), ashas=dash.ashas(db, p)), user=u)


@router.get("/admin")
def admin(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    if u.role != "admin":
        return _render(request, s, "error.html", dict(code=403, message="error.admin_only"), status=403, user=u)
    p = accounts.principal_for_user(u)
    url, source = server_info.resolve_public_url(db, s, str(request.base_url).rstrip("/"))
    audit_rows, _ = accounts.list_audit(db, 30)
    return _render(request, s, "admin.html", dict(users=accounts.list_users(db), phones=dash.sync_status(db, p), ashas=dash.ashas(db, p),
                                                  public_url=url, url_source=source, qr=server_info.qr_svg(url) if url else None,
                                                  audit=audit_rows), user=u)


@router.get("/settings")
def settings_page(request: Request, u=Depends(page_user), db: Session = Depends(get_db), s: Settings = Depends(get_settings)):
    url, source = server_info.resolve_public_url(db, s, str(request.base_url).rstrip("/"))
    return _render(request, s, "settings.html", dict(public_url=url, url_source=source, qr=server_info.qr_svg(url) if url else None,
                                                     retention=accounts.retention_days(db, s), stored_url=accounts.get_setting(db, "public_url") or ""), user=u)


@router.get("/favicon.ico")
def favicon():
    return Response(status_code=204)
