"""Transport-level hardening for the API (pure ASGI, no extra dependency): request-size limits, per-client rate limiting and
security headers. State lives on app.state so every app instance (and every test) is isolated.

Limits are in memory and per process: with several server processes put a shared limiter (or the platform's rate limiting) in front."""
import hashlib
import json
import time
from collections import deque
from typing import Deque, Dict

from app.core.config import get_settings

QA_BODY_LIMIT = 32_768          # a question is at most 2000 characters; nothing under /health-qa needs more
WINDOW = 60.0
SECURITY_HEADERS = [(b"x-content-type-options", b"nosniff"), (b"cache-control", b"no-store"), (b"x-frame-options", b"DENY"),
                    (b"referrer-policy", b"no-referrer"), (b"content-security-policy", b"default-src 'none'; frame-ancestors 'none'")]


def client_ip(scope) -> str:
    c = scope.get("client")
    return c[0] if c else "unknown"


def key_fingerprint(supplied: str) -> str:
    return hashlib.sha256(supplied.encode("utf-8", "replace")).hexdigest()[:12] if supplied else "none"


class SlidingWindow:
    def __init__(self, max_keys: int = 5000):
        self.hits: Dict[str, Deque[float]] = {}
        self.max_keys = max_keys

    def _prune(self, now: float):
        if len(self.hits) <= self.max_keys:
            return
        for k in [k for k, d in self.hits.items() if not d or now - d[-1] > WINDOW]:
            self.hits.pop(k, None)

    def count(self, key: str, now: float = None) -> int:
        now = now if now is not None else time.monotonic()
        d = self.hits.get(key)
        if not d:
            return 0
        while d and now - d[0] > WINDOW:
            d.popleft()
        return len(d)

    def add(self, key: str, now: float = None) -> int:
        now = now if now is not None else time.monotonic()
        self._prune(now)
        d = self.hits.setdefault(key, deque())
        while d and now - d[0] > WINDOW:
            d.popleft()
        d.append(now)
        return len(d)

    def retry_after(self, key: str, now: float = None) -> int:
        now = now if now is not None else time.monotonic()
        d = self.hits.get(key)
        return max(1, int(WINDOW - (now - d[0])) + 1) if d else 1


def auth_failures(app) -> SlidingWindow:
    if not hasattr(app.state, "auth_failures"):
        app.state.auth_failures = SlidingWindow()
    return app.state.auth_failures


def _settings(app):
    return app.dependency_overrides.get(get_settings, get_settings)()


class _TooLarge(Exception):
    pass


async def _json(send, status, code, message, extra_headers=()):
    body = json.dumps({"error": {"code": code, "message": message, "details": None}}).encode()
    headers = [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())] + SECURITY_HEADERS + list(extra_headers)
    await send({"type": "http.response.start", "status": status, "headers": headers})
    await send({"type": "http.response.body", "body": body})


class Hardening:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        s = _settings(scope["app"])
        path = scope["path"]
        headers = {k.decode("latin-1").lower(): v.decode("latin-1") for k, v in scope["headers"]}
        # 1. request size (declared length first, then the bytes actually received for chunked bodies)
        limit = QA_BODY_LIMIT if path.startswith("/api/v1/health-qa") else s.max_body_bytes
        declared = headers.get("content-length")
        if declared and declared.isdigit() and int(declared) > limit:
            return await _json(send, 413, "PAYLOAD_TOO_LARGE", "request body is too large")
        # 2. rate limit per client (API-key fingerprint, else address); /health stays open for load balancers
        if path != "/health" and s.rate_limit_per_minute > 0:
            app = scope["app"]
            if not hasattr(app.state, "rate"):
                app.state.rate = SlidingWindow()
            who = "k:" + key_fingerprint(headers.get("x-api-key", "")) if headers.get("x-api-key") else "ip:" + client_ip(scope)
            is_llm = path.endswith(("/health-qa/llm", "/health-qa/explain", "/health-qa/rag"))
            cap = min(s.rate_limit_per_minute, s.llm_rate_limit_per_minute) if is_llm else s.rate_limit_per_minute
            bucket = who + ("|llm" if is_llm else "")
            if app.state.rate.count(bucket) >= cap:
                return await _json(send, 429, "RATE_LIMITED", "too many requests; slow down and retry",
                                   [(b"retry-after", str(app.state.rate.retry_after(bucket)).encode())])
            app.state.rate.add(bucket)
        seen = 0

        async def counted():
            nonlocal seen
            m = await receive()
            if m["type"] == "http.request":
                seen += len(m.get("body", b""))
                if seen > limit:
                    raise _TooLarge()
            return m

        started = False

        async def with_headers(m):
            nonlocal started
            if m["type"] == "http.response.start":
                started = True
                h = list(m.get("headers", []))
                present = {k.lower() for k, _ in h}
                for k, v in SECURITY_HEADERS:
                    if k not in present:
                        h.append((k, v))
                if scope.get("scheme") == "https" and b"strict-transport-security" not in present:
                    h.append((b"strict-transport-security", b"max-age=31536000; includeSubDomains"))
                m = dict(m, headers=h)
            await send(m)

        try:
            await self.app(scope, counted, with_headers)
        except _TooLarge:
            if not started:
                await _json(send, 413, "PAYLOAD_TOO_LARGE", "request body is too large")
