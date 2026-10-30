"""Website accounts: argon2 passwords, short-lived JWT sessions, roles, lockout, CSRF guard, per-phone API keys, admin audit."""
import datetime as dt
import time

import jwt
import pytest
from sqlalchemy import select

from app.db.models import AdminAudit, PhoneKey, User
from app.tests.conftest import PASSWORDS, login, needs_pack

pytestmark = needs_pack


def test_passwords_are_argon2id_hashes_never_plain(bdb):
    for u in bdb.scalars(select(User)):
        assert u.password_hash.startswith("$argon2id$")
        assert PASSWORDS.get(u.username, "~~") not in u.password_hash


def test_login_returns_short_lived_token_and_httponly_strict_cookie(web):
    c = web()
    r = c.post("/api/v1/auth/login", json={"username": "admin", "password": PASSWORDS["admin"]})
    assert r.status_code == 200
    body = r.json()
    assert body["expires_in"] == 30 * 60 and body["user"]["role"] == "admin" and "password_hash" not in r.text
    cookie = r.headers["set-cookie"].lower()
    assert "asha_session=" in cookie and "httponly" in cookie and "samesite=strict" in cookie
    claims = jwt.decode(body["access_token"], options={"verify_signature": False})
    assert claims["exp"] - claims["iat"] == 1800 and claims["typ"] == "session" and "password" not in claims


def test_wrong_password_unknown_user_and_lockout(web, bdb):
    c = web(failed_auth_per_minute=0)
    assert c.post("/api/v1/auth/login", json={"username": "nobody", "password": "x" * 12}).status_code == 401
    for _ in range(5):
        assert c.post("/api/v1/auth/login", json={"username": "anm", "password": "wrong-wrong-1"}).status_code == 401
    r = c.post("/api/v1/auth/login", json={"username": "anm", "password": PASSWORDS["anm"]})      # right password, but now locked
    assert r.status_code == 429 and r.json()["error"]["code"] == "RATE_LIMITED"
    bdb.expire_all()
    assert bdb.scalar(select(AdminAudit).where(AdminAudit.action == "account_locked", AdminAudit.target == "anm"))


def test_failed_logins_are_rate_limited_per_address(web):
    c = web(failed_auth_per_minute=3)
    codes = [c.post("/api/v1/auth/login", json={"username": "admin", "password": "nope-nope-%d" % i}).status_code for i in range(5)]
    assert codes[:3] == [401, 401, 401] and codes[3:] == [429, 429]


def test_expired_or_tampered_token_is_refused(web):
    c = web()
    h = login(c, "admin")
    assert c.get("/api/v1/auth/me", headers=h).status_code == 200
    bad = {"Authorization": h["Authorization"][:-3] + "abc"}
    assert c.get("/api/v1/auth/me", headers=bad).status_code == 401
    old = jwt.encode({"sub": "1", "tv": 1, "typ": "session", "exp": int(time.time()) - 5, "iat": int(time.time()) - 100},
                     "test-secret-key-0123456789-0123456789", algorithm="HS256")
    assert c.get("/api/v1/auth/me", headers={"Authorization": "Bearer " + old}).status_code == 401


def test_logout_and_deactivation_end_sessions(web, bdb):
    c = web()
    h = login(c, "anm")
    assert c.post("/api/v1/auth/logout", headers=h).status_code == 200
    assert c.get("/api/v1/auth/me", headers=h).status_code == 401
    h2 = login(c, "asha.kalavati")
    admin = login(c, "admin")
    uid = bdb.scalar(select(User.id).where(User.username == "asha.kalavati"))
    assert c.patch("/api/v1/admin/users/%d" % uid, json={"is_active": False}, headers=admin).status_code == 200
    assert c.get("/api/v1/auth/me", headers=h2).status_code == 401


def test_cookie_writes_need_the_csrf_header(web):
    c = web()
    c.post("/api/v1/auth/login", json={"username": "admin", "password": PASSWORDS["admin"]})          # cookie now in the client jar
    assert c.get("/api/v1/auth/me").status_code == 200                                                    # reads: fine
    r = c.post("/api/v1/ask", json={"question": "MR-1 kab lagta hai?"})
    assert r.status_code == 403 and r.json()["error"]["code"] == "CSRF_CHECK_FAILED"
    assert c.post("/api/v1/ask", json={"question": "MR-1 kab lagta hai?"}, headers={"X-Requested-With": "fetch"}).status_code == 200


@pytest.mark.parametrize("user,path,code", [
    ("asha.kalavati", "/api/v1/admin/users", 403), ("anm", "/api/v1/admin/users", 403), ("admin", "/api/v1/admin/users", 200),
    ("asha.kalavati", "/api/v1/admin/phones", 403), ("anm", "/api/v1/dashboard/reports/export?kind=households", 200),
    ("asha.kalavati", "/api/v1/dashboard/reports/export?kind=households", 403), ("asha.kalavati", "/api/v1/dashboard/overview", 200),
])
def test_roles(web, user, path, code):
    c = web()
    assert c.get(path, headers=login(c, user)).status_code == code


def test_asha_sees_only_her_own_households_and_visit_list(web):
    c = web()
    h = login(c, "asha.kalavati")
    items = c.get("/api/v1/dashboard/households?limit=200", headers=h).json()["items"]
    assert items and {i["worker_id"] for i in items} == {"ASHA-RRR5"}
    assert c.get("/api/v1/dashboard/visit-list?worker_id=ASHA-096P", headers=h).status_code == 403
    vl = c.get("/api/v1/dashboard/visit-list", headers=h).json()
    assert vl["worker_id"] == "ASHA-RRR5" and all(i["worker_id"] == "ASHA-RRR5" for g in vl["groups"] for i in g["items"])
    other = c.get("/api/v1/dashboard/households?worker_id=ASHA-096P&limit=1", headers=login(c, "admin")).json()["items"][0]["household_id"]
    assert c.get("/api/v1/dashboard/households/" + other, headers=h).status_code == 404                  # existence not leaked


def test_phone_key_shown_once_stored_hashed_and_revocable(web, bdb):
    c = web()
    admin = login(c, "admin")
    r = c.post("/api/v1/admin/phones", json={"worker_id": "WRK-SYN-001", "label": "Redmi test"}, headers=admin)
    assert r.status_code == 201
    key = r.json()["api_key"]
    assert key.startswith("asha_") and len(key) > 50
    bdb.expire_all()
    row = bdb.scalar(select(PhoneKey).where(PhoneKey.key_id == r.json()["key_id"]))
    assert key not in (row.key_hash or "") and len(row.key_hash) == 64
    listed = c.get("/api/v1/admin/phones", headers=admin).text
    assert key not in listed and r.json()["key_id"] in listed
    phone = {"X-API-Key": key}
    assert c.get("/api/v1/sync/pull?entity_types=household&limit=5", headers=phone).status_code == 200
    assert c.post("/api/v1/admin/phones/%s/revoke" % r.json()["key_id"], headers=admin).status_code == 200
    assert c.get("/api/v1/sync/pull?entity_types=household&limit=5", headers=phone).status_code == 401
    bdb.rollback()                                                # end the read snapshot taken earlier in this test
    actions = [a.action for a in bdb.scalars(select(AdminAudit).order_by(AdminAudit.id))]
    assert "phone_key_create" in actions and "phone_key_revoke" in actions


def test_phone_key_is_scoped_to_its_worker(web):
    c = web()
    key = c.post("/api/v1/admin/phones", json={"worker_id": "WRK-SYN-001", "label": "p"}, headers=login(c, "admin")).json()["api_key"]
    pulled = c.get("/api/v1/sync/pull?limit=500", headers={"X-API-Key": key}).json()
    assert pulled["households"] and all(h["assigned_worker_id"] == "WRK-SYN-001" for h in pulled["households"])
    assert c.get("/api/v1/admin/users", headers={"X-API-Key": key}).status_code == 403


def test_admin_actions_are_audited_without_secrets(web, bdb):
    c = web()
    admin = login(c, "admin")
    r = c.post("/api/v1/admin/users", json={"username": "new.sup", "display_name": "New", "role": "supervisor", "password": "a-strong-password-9"}, headers=admin)
    assert r.status_code == 201
    assert c.post("/api/v1/admin/users", json={"username": "x", "display_name": "x", "role": "asha", "password": "short"}, headers=admin).status_code == 422
    bdb.expire_all()
    rows = list(bdb.scalars(select(AdminAudit)))
    assert any(a.action == "user_create" and a.target == "new.sup" for a in rows)
    assert all("a-strong-password-9" not in str(a.details) for a in rows)
    assert c.get("/api/v1/admin/audit?action=user_create", headers=admin).json()["total"] >= 1


def test_last_admin_cannot_be_removed(web, bdb):
    c = web()
    admin = login(c, "admin")
    uid = bdb.scalar(select(User.id).where(User.username == "admin"))
    r = c.patch("/api/v1/admin/users/%d" % uid, json={"role": "supervisor"}, headers=admin)
    assert r.status_code == 409 and r.json()["error"]["code"] == "LAST_ADMIN"


def test_cors_is_closed_unless_a_site_origin_is_set(web, monkeypatch):
    from fastapi.testclient import TestClient

    from app.core import config
    from app.main import create_app
    pre = {"Origin": "https://evil.example", "Access-Control-Request-Method": "POST"}
    assert "access-control-allow-origin" not in web().options("/api/v1/ask", headers=pre).headers
    monkeypatch.setenv("SITE_ORIGIN", "https://asha.example.org")      # CORS is configured when the app is created
    config.get_settings.cache_clear()
    try:
        c = TestClient(create_app())
        assert "access-control-allow-origin" not in c.options("/api/v1/ask", headers=pre).headers
        ok = c.options("/api/v1/ask", headers=dict(pre, Origin="https://asha.example.org"))
        assert ok.headers.get("access-control-allow-origin") == "https://asha.example.org"
    finally:
        config.get_settings.cache_clear()


def test_pages_require_login_and_send_strict_security_headers(web):
    c = web(auth_mode="disabled")                       # even with the API in dev mode, pages need a real sign-in
    r = c.get("/", follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"].startswith("/login")
    page = c.get("/login")
    csp = page.headers["content-security-policy"]
    assert "script-src 'self'" in csp and "unsafe-inline" not in csp and "frame-ancestors 'none'" in csp
    assert page.headers["x-frame-options"] == "DENY" and page.headers["x-content-type-options"] == "nosniff"


def test_form_login_rejects_cross_site_origin_and_open_redirects(web):
    c = web()
    r = c.post("/login", data={"username": "admin", "password": PASSWORDS["admin"], "next": "//evil.example/x"}, follow_redirects=False)
    assert r.status_code == 303 and r.headers["location"] == "/"
    r = c.post("/login", data={"username": "admin", "password": PASSWORDS["admin"]}, headers={"Origin": "https://evil.example"}, follow_redirects=False)
    assert r.status_code == 403


def test_session_token_has_no_long_lifetime(web):
    c = web(session_minutes=1)
    tok = c.post("/api/v1/auth/login", json={"username": "admin", "password": PASSWORDS["admin"]}).json()["access_token"]
    claims = jwt.decode(tok, options={"verify_signature": False})
    assert dt.timedelta(seconds=claims["exp"] - claims["iat"]) == dt.timedelta(minutes=1)
