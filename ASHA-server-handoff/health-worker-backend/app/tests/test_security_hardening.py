"""Security hardening regression tests (synthetic data only). Each test pins one verified weakness found in the audit."""
import uuid

import pytest
from sqlalchemy import select

from app.db.models import Household, SyncOperation, Visit

KEYS = "worker|WRK-SYN-001|wk-one-key-0123456789abcdef;worker|WRK-SYN-002|wk-two-key-0123456789abcdef;admin||admin-key-0123456789abcdef"


def H(k):
    return {"X-API-Key": k}


def _hh_of(db, worker):
    return db.scalar(select(Household.household_id).where(Household.assigned_worker_id == worker).limit(1))


def _visit_op(op_id, vid, hh, date="2026-11-05"):
    return dict(op_id=op_id, entity_type="visit", entity_id=vid, op_type="create",
                payload=dict(household_id=hh, scheduled_date=date, visit_reason="ROUTINE"))


def _push(c, key, ops, inst):
    r = c.post("/api/v1/sync/push", headers=H(key), json=dict(installation_id=inst, operations=ops))
    assert r.status_code == 200, r.text
    return r.json()["results"][0]


# ------------------------------------------------------------------ sync: operation ids are owned by the worker who sent them
def test_another_worker_cannot_reuse_or_read_my_operation_id(make_client, db):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    shared = "op-shared-" + uuid.uuid4().hex[:8]
    mine = _push(c, "wk-one-key-0123456789abcdef", [_visit_op(shared, "VIS-SEC-A001", _hh_of(db, "WRK-SYN-001"))], "install-WORKER-ONE")
    assert mine["acknowledged"] is True
    # worker two sends the same op_id for a visit of ITS OWN household: it must NOT be answered with worker one's stored result
    theirs = _push(c, "wk-two-key-0123456789abcdef", [_visit_op(shared, "VIS-SEC-B001", _hh_of(db, "WRK-SYN-002"))], "install-WORKER-TWO")
    assert theirs["acknowledged"] is False, "worker two was told its data is stored when it was silently discarded"
    assert theirs["status"] == "REJECTED" and theirs["error_code"] == "OPERATION_ID_IN_USE"
    assert theirs["server_version"] is None and theirs["conflict"] is None, "another worker's result leaked"
    db.rollback()
    assert db.get(Visit, "VIS-SEC-B001") is None
    assert db.get(Visit, "VIS-SEC-A001") is not None
    # worker one can still safely resend its own op: duplicate, same answer
    again = _push(c, "wk-one-key-0123456789abcdef", [_visit_op(shared, "VIS-SEC-A001", _hh_of(db, "WRK-SYN-001"))], "install-WORKER-ONE")
    assert again["duplicate"] is True and again["acknowledged"] is True


def test_worker_cannot_clear_another_workers_rejected_operation_record(make_client, db):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    shared = "op-rej-" + uuid.uuid4().hex[:8]
    bad = _visit_op(shared, "VIS-SEC-A002", "HH-DOES-NOT-EXIST")
    assert _push(c, "wk-one-key-0123456789abcdef", [bad], "install-WORKER-ONE")["status"] == "REJECTED"
    _push(c, "wk-two-key-0123456789abcdef", [bad], "install-WORKER-TWO")
    db.rollback()
    row = db.get(SyncOperation, shared)
    assert row is not None and (row.result or {}).get("owner") == "worker:WRK-SYN-001"


def test_worker_cannot_create_or_update_visits_of_another_worker_through_sync(make_client, db):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    foreign_hh = _hh_of(db, "WRK-SYN-002")
    r = _push(c, "wk-one-key-0123456789abcdef", [_visit_op("op-xw-" + uuid.uuid4().hex[:8], "VIS-SEC-X001", foreign_hh)], "install-WORKER-ONE")
    assert r["acknowledged"] is False and r["status"] == "REJECTED"
    db.rollback()
    assert db.get(Visit, "VIS-SEC-X001") is None


# ------------------------------------------------------------------ request limits, headers, rate limiting
def test_oversized_request_body_is_rejected_413(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    big = {"question": "x" * 3_000_000}
    r = c.post("/api/v1/health-qa/query", headers=H("wk-one-key-0123456789abcdef"), json=big)
    assert r.status_code == 413 and r.json()["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_responses_carry_security_headers_and_are_not_cacheable(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    r = c.get("/api/v1/households?limit=1", headers=H("wk-one-key-0123456789abcdef"))
    assert r.headers["X-Content-Type-Options"] == "nosniff"
    assert r.headers["Cache-Control"] == "no-store"
    assert r.headers["X-Frame-Options"] == "DENY"


def test_rate_limit_returns_429_with_retry_after(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS, rate_limit_per_minute=5)
    codes = [c.get("/api/v1/households?limit=1", headers=H("wk-one-key-0123456789abcdef")).status_code for _ in range(8)]
    assert codes[:5] == [200] * 5 and 429 in codes[5:]
    r = c.get("/api/v1/households?limit=1", headers=H("wk-one-key-0123456789abcdef"))
    assert r.status_code == 429 and "Retry-After" in r.headers and r.json()["error"]["code"] == "RATE_LIMITED"
    # another worker is not affected by the first worker's limit
    assert c.get("/api/v1/households?limit=1", headers=H("wk-two-key-0123456789abcdef")).status_code == 200


def test_failed_logins_are_rate_limited_per_client(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS, failed_auth_per_minute=4)
    codes = [c.get("/api/v1/households", headers=H("guess-%d" % i)).status_code for i in range(8)]
    assert codes[:4] == [401] * 4 and set(codes[4:]) == {429}
    # the correct key is blocked from the same address while the lockout lasts (brute-force protection)
    assert c.get("/api/v1/households", headers=H("wk-one-key-0123456789abcdef")).status_code == 429


def test_failed_auth_is_logged_without_the_supplied_key(make_client, caplog):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    with caplog.at_level("WARNING", logger="security"):
        c.get("/api/v1/households", headers=H("super-secret-guess-123"))
    text = " ".join(r.getMessage() for r in caplog.records)
    assert "auth failure" in text and "super-secret-guess-123" not in text


# ------------------------------------------------------------------ production configuration guards
def _prod(monkeypatch, **env):
    from app.core import config
    base = dict(APP_ENV="production", AUTH_MODE="api_key", API_KEYS=KEYS, DEVICE_HASH_SALT="a-long-random-production-salt-0123456789", DOCS_ENABLED="false",
                SECRET_KEY="a-long-random-session-signing-secret-0123456789")
    base.update(env)
    for k, v in base.items():
        monkeypatch.setenv(k, v)
    config.get_settings.cache_clear()
    return config


def test_production_refuses_default_device_salt(monkeypatch):
    from app.main import create_app
    config = _prod(monkeypatch, DEVICE_HASH_SALT="dev-only-salt-change-me")
    try:
        with pytest.raises(RuntimeError, match="DEVICE_HASH_SALT"):
            create_app()
    finally:
        config.get_settings.cache_clear()


def test_production_refuses_default_session_secret(monkeypatch):
    from app.main import create_app
    config = _prod(monkeypatch, SECRET_KEY="dev-only-secret-change-me")
    try:
        with pytest.raises(RuntimeError, match="SECRET_KEY"):
            create_app()
    finally:
        config.get_settings.cache_clear()


def test_production_refuses_short_api_keys(monkeypatch):
    from app.main import create_app
    config = _prod(monkeypatch, API_KEYS="worker|WRK-SYN-001|short;admin||short2")
    try:
        with pytest.raises(RuntimeError, match="API key"):
            create_app()
    finally:
        config.get_settings.cache_clear()


def test_production_hides_docs_and_auth_mode(monkeypatch):
    from fastapi.testclient import TestClient
    from app.main import create_app
    config = _prod(monkeypatch, DOCS_ENABLED="true")      # even if someone forgets to turn docs off
    try:
        c = TestClient(create_app())
        assert c.get("/docs").status_code == 404 and c.get("/openapi.json").status_code == 404
        assert c.get("/health").json() == {"status": "ok"}
    finally:
        config.get_settings.cache_clear()


# ------------------------------------------------------------------ AI answer: deterministic output guard
@pytest.mark.parametrize("text", ["Give 500 mg paracetamol now.", "Give her two tablets every 6 hours", "Use 5 ml of syrup", "ORS 200ml after each stool",
                                  "paracetamol bhi de sakte hain", "Amoxicillin 250 mg"])
def test_ai_answer_that_names_a_dose_or_medicine_is_withheld(text):
    from app.services.llm.client import unsafe_output
    assert unsafe_output(text) is True


@pytest.mark.parametrize("text", ["Contact the supervising medical officer now.", "Take her to the nearest health centre straight away.",
                                  "Visit again in 3 days and record it in the register."])
def test_ai_answer_without_doses_is_allowed(text):
    from app.services.llm.client import unsafe_output
    assert unsafe_output(text) is False


def test_llm_route_withholds_unsafe_answer(make_client, monkeypatch):
    import app.services.llm.client as llm
    c = make_client(auth_mode="api_key", api_keys=KEYS, anthropic_api_key="test")

    class R:
        status_code = 200
        def json(self): return {"content": [{"type": "text", "text": "Give 500 mg paracetamol every 4 hours."}]}
    monkeypatch.setattr(llm, "_post", lambda *a, **k: R())
    r = c.post("/api/v1/health-qa/llm", headers=H("wk-one-key-0123456789abcdef"), json={"question": "baby has fever"})
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_UNSAFE_OUTPUT"
    assert "paracetamol" not in r.text
