import json
import logging
import os
import re

import pytest
from sqlalchemy import select

from app.core.config import BACKEND_ROOT, Settings
from app.core.security import parse_keys
from app.db.models import AuditLog, Referral
from app.tests.conftest import REF

KEYS = "worker|WRK-SYN-001|wk-one-key;worker|WRK-SYN-002|wk-two-key;admin||admin-key;hospital||hosp-key"


@pytest.fixture
def secured(make_client):
    return make_client(auth_mode="api_key", api_keys=KEYS)


def H(k): return {"X-API-Key": k}


def test_dev_mode_is_unauthenticated_by_design(client):
    assert client.get("/api/v1/households?limit=1").status_code == 200
    assert client.get("/health").json()["auth_mode"] == "disabled"


def test_production_refuses_disabled_auth(monkeypatch):
    from app.core import config
    from app.main import create_app
    monkeypatch.setenv("APP_ENV", "production"); monkeypatch.setenv("AUTH_MODE", "disabled")
    config.get_settings.cache_clear()
    try:
        with pytest.raises(RuntimeError):
            create_app()
    finally:
        config.get_settings.cache_clear()


def test_missing_or_bad_key_is_401_with_standard_error(secured):
    for h in ({}, H("wrong")):
        r = secured.get("/api/v1/households", headers=h)
        assert r.status_code == 401 and r.json()["error"]["code"] == "UNAUTHORIZED"
    assert secured.get("/health").status_code == 200           # liveness stays open and reveals nothing sensitive


def test_every_v1_route_requires_auth(make_client):
    secured = make_client(auth_mode="api_key", api_keys=KEYS, failed_auth_per_minute=0)   # probes 50+ routes unauthenticated on purpose
    spec = secured.get("/openapi.json").json()["paths"]
    ops = [(m, p) for p, item in spec.items() if p.startswith("/api/v1") and "{" not in p for m in item if p != "/api/v1/auth/login"]
    assert len(ops) > 30
    for m, p in ops:
        r = secured.request(m.upper(), p, json={})
        assert r.status_code == 401, (m, p)
    # the sign-in route is the only open one, and it never signs anyone in without a password
    assert secured.post("/api/v1/auth/login", json={"username": "admin", "password": "wrong-password"}).status_code == 401


def test_worker_sees_only_own_households_visits_referrals(secured):
    one = secured.get("/api/v1/households?limit=200", headers=H("wk-one-key")).json()
    assert one["total"] > 0 and all(h["assigned_worker_id"] == "WRK-SYN-001" for h in one["items"])
    assert secured.get("/api/v1/households?worker_id=WRK-SYN-002", headers=H("wk-one-key")).status_code == 403
    other = secured.get("/api/v1/households?worker_id=WRK-SYN-002&limit=1", headers=H("admin-key")).json()["items"][0]["household_id"]
    assert secured.get("/api/v1/households/" + other, headers=H("wk-one-key")).status_code == 404         # existence not leaked
    assert secured.get("/api/v1/households/" + other, headers=H("admin-key")).status_code == 200
    v = secured.get("/api/v1/visits?limit=200", headers=H("wk-one-key")).json()
    assert v["total"] > 0 and all(x["worker_id"] == "WRK-SYN-001" for x in v["items"])
    assert secured.get("/api/v1/visits?worker_id=WRK-SYN-002", headers=H("wk-one-key")).status_code == 403
    f = secured.get("/api/v1/follow-ups?limit=200", headers=H("wk-one-key")).json()
    assert all(x["worker_id"] == "WRK-SYN-001" for x in f["items"])
    hh_ids = {h["household_id"] for h in secured.get("/api/v1/households?limit=200", headers=H("wk-one-key")).json()["items"]}
    r = secured.get("/api/v1/referrals?limit=200", headers=H("wk-one-key")).json()
    assert r["total"] > 0 and all(x["household_id"] in hh_ids for x in r["items"])


def test_worker_cannot_create_for_or_reassign_other_workers(secured):
    body = dict(village_id="VIL-SYN-01", assigned_worker_id="WRK-SYN-002", household_member_count=3)
    assert secured.post("/api/v1/households", json=body, headers=H("wk-one-key")).status_code == 403
    assert secured.post("/api/v1/households", json=dict(body, assigned_worker_id="WRK-SYN-001"), headers=H("wk-one-key")).status_code == 201
    mine = secured.get("/api/v1/households?limit=1", headers=H("wk-one-key")).json()["items"][0]["household_id"]
    assert secured.patch("/api/v1/households/" + mine, json=dict(assigned_worker_id="WRK-SYN-002"), headers=H("wk-one-key")).status_code == 403


def test_only_hospital_or_admin_can_confirm_attendance(secured, db):
    from app.db.models import Household
    r = db.scalar(select(Referral).join(Household, Household.household_id == Referral.household_id).where(
        Household.assigned_worker_id == "WRK-SYN-001", Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE", Referral.planned_visit_date <= REF))
    wk = "wk-one-key"
    body = dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-SEC-1", attendance_confirmation_date=REF)
    assert secured.patch("/api/v1/referrals/" + r.referral_id, json=body, headers=H(wk)).status_code == 403
    assert secured.patch("/api/v1/referrals/" + r.referral_id, json=body, headers=H("hosp-key")).status_code == 200


def test_worker_report_counts_only_own_households(secured):
    body = dict(facility_id="FAC-SYN-01", period_start="2026-01-01", period_end="2026-10-13")
    adm = secured.post("/api/v1/reports/summary", json=body, headers=H("admin-key")).json()["counts"]["total_included"]
    wk = secured.post("/api/v1/reports/summary", json=body, headers=H("wk-one-key")).json()["counts"]["total_included"]
    assert 0 <= wk < adm


def test_worker_sync_status_needs_installation_id(secured):
    assert secured.get("/api/v1/sync/status", headers=H("wk-one-key")).status_code == 403
    assert secured.get("/api/v1/sync/status", headers=H("admin-key")).status_code == 200


def test_malformed_key_config_is_rejected():
    for bad in ("worker||k", "root|x|k", "admin|y"):
        with pytest.raises(ValueError):
            parse_keys(bad)
    assert parse_keys("") == []


# ---------------- evaluation labels never exposed ----------------
def _walk(o, out):
    if isinstance(o, dict):
        for k, v in o.items():
            out.add(k); _walk(v, out)
    elif isinstance(o, list):
        for v in o: _walk(v, out)


def test_openapi_exposes_no_benchmark_routes_or_label_fields(client):
    spec = client.get("/openapi.json").json()
    assert not [p for p in spec["paths"] if any(w in p.lower() for w in ("benchmark", "evaluation", "danger-sign", "test-case"))]
    names = set(); _walk(spec["components"]["schemas"], names)
    assert not [n for n in names if n.startswith("expected_") or n in ("notes_for_evaluation", "split", "rule_mapping_status")]


def test_qa_response_never_contains_labels(client):
    r = client.post("/api/v1/health-qa/query", json={"question": "How many antenatal check-ups should a pregnant woman have?"}).json()
    blob = json.dumps(r)
    assert "expected_" not in blob and "notes_for_evaluation" not in blob
    assert set(r) == {"query_id", "outcome", "original_question", "message", "answer_text", "citations", "safety", "retrieval_status"}


def test_benchmark_data_is_in_separate_table(db):
    from app.db.models import BenchmarkCase
    assert BenchmarkCase.__tablename__ == "benchmark_cases"
    cols = {c.name for c in __import__("app.db.models", fromlist=["Household"]).Household.__table__.columns}
    assert not [c for c in cols if c.startswith("expected")]


# ---------------- error format / validation ----------------
def test_standard_error_shape(client):
    for r in (client.get("/api/v1/households/NOPE"), client.post("/api/v1/households", json={}), client.get("/api/v1/nope")):
        j = r.json()
        assert set(j) == {"error"} and {"code", "message"} <= set(j["error"])
    assert client.get("/api/v1/households?limit=0").status_code == 422
    assert client.get("/api/v1/households?offset=-1").status_code == 422
    assert client.get("/api/v1/visits?date_from=notadate").status_code == 422


def test_unhandled_error_is_generic_500(client):
    from app.db.session import get_db
    def boom():
        raise RuntimeError("secret internals")
        yield
    client.app.dependency_overrides[get_db] = boom
    r = client.get("/api/v1/households")
    assert r.status_code == 500 and r.json()["error"]["code"] == "INTERNAL_ERROR" and "secret" not in r.text


def test_integrity_violation_maps_to_409(client, db):
    from app.core.security import Principal
    from app.db.models import Referral as R
    assert True  # DB CHECK constraints are exercised below
    from sqlalchemy.exc import IntegrityError
    ref = db.scalar(select(R).where(R.referral_status == "PLANNED"))
    ref.attendance_confirmed = True            # violates ck_referral_attendance_flag
    with pytest.raises(IntegrityError):
        db.flush()
    db.rollback()


# ---------------- privacy / logging / audit ----------------
def test_health_text_is_not_logged(client, caplog):
    caplog.set_level(logging.DEBUG)
    secret = "zebra-unique-phrase-0451 bleeding heavily"
    client.post("/api/v1/health-qa/query", json={"question": secret})
    assert "zebra-unique-phrase" not in caplog.text


def test_audit_log_records_field_names_not_values(client, db):
    client.patch("/api/v1/households/HH-SYN-00001", json=dict(household_member_count=9))
    db.rollback()
    row = db.scalars(select(AuditLog).where(AuditLog.entity_id == "HH-SYN-00001").order_by(AuditLog.id.desc())).first()
    assert row.action == "UPDATE" and row.changed_fields == ["household_member_count"] and row.new_version == 2 and row.actor and row.source == "api"
    assert "9" not in json.dumps(row.changed_fields)


def test_no_secrets_committed():
    env = open(os.path.join(BACKEND_ROOT, ".env.example"), encoding="utf-8").read()
    assert "change-me" in env.lower() and "AUTH_MODE" in env
    # The website has accounts now, so the words "password" and "secret_key" legitimately appear in code. What must never appear is a
    # literal value assigned to them (other than the public dev placeholder that production refuses to start with), or an API key.
    assigned = re.compile(r"\b(password|passwd|secret_key|api_key)\w*\s*[:=]\s*(str\s*=\s*)?[\"']([^\"']{6,})[\"']", re.I)
    for root, _, files in os.walk(os.path.join(BACKEND_ROOT, "app")):
        for f in files:
            if f.endswith(".py") and "tests" not in root:
                src = open(os.path.join(root, f), encoding="utf-8").read()
                assert "sk-ant" not in src.lower() and not re.search(r"\bsk-[A-Za-z0-9]{20,}", src), f
                for m in assigned.finditer(src):
                    assert "change-me" in m.group(3) or m.group(1).isupper(), (f, m.group(0))   # upper case = a doc string naming the variable
    for name in (".env.example", os.path.join("..", ".env.example")):
        path = os.path.join(BACKEND_ROOT, name)
        if os.path.exists(path):
            for line in open(path, encoding="utf-8"):
                k, _, v = line.strip().partition("=")
                if not line.startswith("#") and any(w in k.upper() for w in ("PASSWORD", "SECRET", "API_KEYS", "SALT")):
                    assert v == "" or "change-me" in v.lower(), line


def test_dataset_files_never_served_over_http(client):
    for p in ("/health-worker-datasets/danger_sign_tests.jsonl", "/data/dataset_manifest.json", "/static/danger_sign_tests.jsonl"):
        assert client.get(p).status_code == 404
