import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError
from starlette.middleware.cors import CORSMiddleware
from starlette.middleware.gzip import GZipMiddleware
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.core.errors import DomainError
from app.core.hardening import Hardening
from app.core.security import parse_keys
from app.web import routes as web

logging.basicConfig(level=logging.INFO)   # NOTE: request bodies / health text are never logged


def _err(status, code, message, details=None):
    return JSONResponse(status_code=status, content={"error": {"code": code, "message": message, "details": details}})


def create_app() -> FastAPI:
    s = get_settings()
    if s.app_env == "production" and s.auth_mode == "disabled":
        raise RuntimeError("Refusing to start: AUTH_MODE=disabled is for local development only.")
    if s.app_env == "production" and set(s.eligible_statuses) != {"VERIFIED"}:
        raise RuntimeError("Refusing to start: production may only retrieve VERIFIED protocol passages (got %s)." % ",".join(s.eligible_statuses))
    if s.app_env == "production":
        if s.device_hash_salt == "dev-only-salt-change-me" or len(s.device_hash_salt) < 16:
            raise RuntimeError("Refusing to start: set DEVICE_HASH_SALT to a long random secret (the default is public).")
        if s.secret_key == "dev-only-secret-change-me" or len(s.secret_key) < 32:
            raise RuntimeError("Refusing to start: set SECRET_KEY to at least 32 random characters (e.g. `openssl rand -hex 32`).")
        for _role, _wid, key in parse_keys(s.api_keys):
            if len(key) < 24:
                raise RuntimeError("Refusing to start: every API key must be at least 24 random characters in production.")
    docs_on = s.docs_enabled and s.app_env != "production"       # API documentation is never published from a production server
    app = FastAPI(title="Frontline Health-Worker Companion API", version="0.3.0",
                  docs_url="/docs" if docs_on else None, redoc_url=None, openapi_url="/openapi.json" if docs_on else None,
                  description="Optional server for the offline-first app and the supervisor website. SYNTHETIC DATA. Core features work on-device "
                              "without this API. Website endpoints: /api/v1/auth, /api/v1/dashboard, /api/v1/admin, /api/v1/ask.")
    # Field phones are often on 2G/weak 4G: JSON sync pages compress ~14x, so compress any response over 1 KB.
    app.add_middleware(GZipMiddleware, minimum_size=1024)
    if s.site_origin:
        # CORS is closed by default (the website is served from this same origin, phones are not browsers). Only the configured site
        # origin may call the API from a browser on another origin.
        app.add_middleware(CORSMiddleware, allow_origins=[s.site_origin.rstrip("/")], allow_credentials=True,
                           allow_methods=["GET", "POST", "PATCH"], allow_headers=["Content-Type", "Authorization", "X-Requested-With"], max_age=600)
    app.add_middleware(Hardening)
    app.include_router(api_router)
    web.install(app)

    @app.get("/health", tags=["meta"])
    def health():
        # in production the mode is not advertised; in development it tells the developer that auth is off
        return {"status": "ok"} if s.app_env == "production" else {"status": "ok", "auth_mode": s.auth_mode}

    def _wants_html(request: Request) -> bool:
        return not request.url.path.startswith(("/api/", "/health", "/docs", "/openapi")) and "text/html" in request.headers.get("accept", "")

    @app.exception_handler(DomainError)
    async def _domain(request: Request, e: DomainError):
        if _wants_html(request):
            return web.error_page(request, e.status_code, e.message)
        r = _err(e.status_code, e.code, e.message, e.details)
        if e.status_code == 429:
            r.headers["Retry-After"] = "60"
        return r

    @app.exception_handler(RequestValidationError)
    async def _validation(_: Request, e: RequestValidationError):
        details = [dict(loc=[str(x) for x in x["loc"]], message=x["msg"], type=x["type"]) for x in e.errors()]
        return _err(422, "VALIDATION_ERROR", "request validation failed", details)

    @app.exception_handler(StarletteHTTPException)
    async def _http(request: Request, e: StarletteHTTPException):
        if _wants_html(request):
            return web.error_page(request, e.status_code, str(e.detail))
        return _err(e.status_code, "HTTP_%d" % e.status_code, str(e.detail))

    @app.exception_handler(IntegrityError)
    async def _integrity(_: Request, e: IntegrityError):
        return _err(409, "INTEGRITY_ERROR", "the request violates a data integrity constraint")

    @app.exception_handler(Exception)
    async def _unhandled(_: Request, e: Exception):
        logging.getLogger("api").exception("unhandled error")
        return _err(500, "INTERNAL_ERROR", "unexpected server error")

    return app


app = create_app()
