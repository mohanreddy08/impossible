"""Which public address phones should use, whether it answers, and a QR code of it.

Precedence: the Settings page value, then PUBLIC_URL, then the file scripts/start_public.sh writes (run/public_url.txt, refreshed every time
the tunnel starts, because a quick tunnel gets a NEW address on each start), then the address this request arrived on."""
import io
import os
from typing import Optional, Tuple

import httpx
import segno
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.services.accounts import service as accounts


def resolve_public_url(db: Session, s: Settings, request_base: Optional[str] = None) -> Tuple[Optional[str], str]:
    v = accounts.get_setting(db, "public_url")
    if v:
        return v.rstrip("/"), "settings page"
    if s.public_url:
        return s.public_url.rstrip("/"), "PUBLIC_URL environment variable"
    try:
        with open(s.resolved_public_url_file, encoding="utf-8") as f:
            line = f.read().strip()
        if line.startswith("https://"):
            return line.rstrip("/"), "tunnel script (%s)" % os.path.basename(s.resolved_public_url_file)
    except OSError:
        pass
    if request_base and request_base.startswith("https://"):
        return request_base.rstrip("/"), "address of this page"
    return None, "not set"


def check(url: Optional[str], timeout: float = 6.0) -> Tuple[Optional[bool], Optional[str]]:
    """GET <url>/health from the server itself (so through the tunnel and back). None = not checked."""
    if not url:
        return None, "no public address yet: run scripts/start_public.sh (or set PUBLIC_URL)"
    try:
        r = httpx.get(url + "/health", timeout=timeout, follow_redirects=False)
        ok = r.status_code == 200 and r.json().get("status") == "ok"
        return ok, "HTTP %d" % r.status_code
    except Exception as e:                                        # noqa: BLE001  any network problem = not reachable
        return False, type(e).__name__


def qr_svg(text: str) -> str:
    buf = io.BytesIO()
    segno.make(text, error="m").save(buf, kind="svg", scale=6, border=2, dark="#000", light="#fff", xmldecl=False, svgns=True,
                                     title="QR code: " + text)
    return buf.getvalue().decode("utf-8")
