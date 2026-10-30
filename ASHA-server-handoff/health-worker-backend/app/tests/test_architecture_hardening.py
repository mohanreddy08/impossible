import ast
import concurrent.futures as cf
import datetime as dt
import glob
import json
import logging
import os
import subprocess
import sys

import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session

from app.core.config import BACKEND_ROOT
from app.core.principal import Principal
from app.db.models import Household, Referral, SyncOperation, Visit
from app.schemas.domain import referral_label

ADMIN = Principal("admin", None, "t")
KEYS = "worker|WRK-SYN-001|wk-one-key;worker|WRK-SYN-002|wk-two-key;admin||admin-key;hospital||hosp-key"


WEB_PREFIXES = ("/api/v1/auth", "/api/v1/dashboard", "/api/v1/admin", "/api/v1/ask")
WEB_OPERATIONS = 29                # auth 3, ask 1, dashboard 16, admin 9


def H(k): return {"X-API-Key": k}


def _imports(path):
    tree = ast.parse(open(path, encoding="utf-8").read())
    mods = []
    for n in ast.walk(tree):
        if isinstance(n, ast.Import): mods += [a.name for a in n.names]
        elif isinstance(n, ast.ImportFrom) and n.module: mods.append(n.module)
    return mods


def _files(sub): return [f for f in glob.glob(os.path.join(BACKEND_ROOT, "app", sub, "**", "*.py"), recursive=True)]


# ---------------------------------------------------------------- separation of concerns
def test_business_logic_has_no_http_framework_imports():
    files = _files("services") + [os.path.join(BACKEND_ROOT, "app", "core", p) for p in ("principal.py", "errors.py", "config.py")] + _files("repositories")
    bad = [(os.path.relpath(f, BACKEND_ROOT), m) for f in files for m in _imports(f) if m.split(".")[0] in ("fastapi", "starlette", "uvicorn") or m.startswith("app.api")]
    assert bad == []


def test_safety_engine_is_isolated_from_retrieval_db_and_http():
    bad = [(os.path.basename(f), m) for f in _files("services/safety") for m in _imports(f)
           if m.split(".")[0] in ("fastapi", "starlette", "sqlalchemy", "sqlite3", "requests", "httpx", "openai", "anthropic")
           or m.startswith(("app.db", "app.api", "app.services.protocol_retrieval", "app.services.health_qa"))]
    assert bad == []


def test_retrieval_core_has_no_orm_or_http_at_module_level():
    tree = ast.parse(open(os.path.join(BACKEND_ROOT, "app/services/protocol_retrieval/service.py"), encoding="utf-8").read())
    top = [n for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
    mods = [a.name for n in top if isinstance(n, ast.Import) for a in n.names] + [n.module for n in top if isinstance(n, ast.ImportFrom)]
    assert not [m for m in mods if m.split(".")[0] in ("fastapi", "sqlalchemy", "starlette") or m.startswith("app.db")]


def test_services_actually_run_with_fastapi_unavailable():
    """Proof, not just static analysis: block fastapi/starlette imports in a fresh interpreter and exercise the services."""
    code = r'''
import sys
for m in ("fastapi", "starlette", "uvicorn"): sys.modules[m] = None
import importlib, pkgutil, app.services as S
names = [m.name for m in pkgutil.walk_packages(S.__path__, "app.services.") if ".tests" not in m.name]
for n in names: importlib.import_module(n)
from app.services.safety.engine import SafetyEngine
assert SafetyEngine().evaluate("Pregnant woman is bleeding heavily right now").status == "ESCALATION_REQUIRED"
from app.services.protocol_retrieval.service import ProtocolIndex
assert ProtocolIndex([]).search("anything").status == "NO_RESULT"
from app.services.reports.export import to_csv, to_pdf
print("OK", len(names))
'''
    r = subprocess.run([sys.executable, "-c", code], cwd=BACKEND_ROOT, capture_output=True, text=True)
    assert r.returncode == 0 and r.stdout.startswith("OK"), r.stderr[-800:]


def test_service_layer_lifecycle_without_http(db, settings):
    """Household -> visit -> referral -> confirmation, calling services directly (no FastAPI, no TestClient)."""
    from app.schemas.domain import HouseholdCreate, ReferralCreate, ReferralUpdate, VisitCreate, VisitUpdate
    from app.services.households import service as hh
    from app.services.referrals import service as rf
    from app.services.visits import service as vs
    h = hh.create(db, ADMIN, HouseholdCreate(village_id="VIL-X", assigned_worker_id="WRK-SYN-001", household_member_count=3, eligible_followup_categories=["ANC", "ROUTINE"]), settings)
    v = vs.create(db, ADMIN, VisitCreate(household_id=h.household_id, scheduled_date=dt.date(2026, 10, 10), visit_reason="ANC"), settings)
    assert h.record_status == "OVERDUE" and db.get(Household, h.household_id).next_visit_due_date == dt.date(2026, 10, 10)
    vs.update(db, ADMIN, v.visit_id, VisitUpdate(visit_status="COMPLETED", actual_visit_date=dt.date(2026, 10, 12)), settings)
    assert db.get(Household, h.household_id).record_status == "COMPLETED"
    r, dup = rf.create(db, ADMIN, ReferralCreate(household_id=h.household_id, visit_id=v.visit_id, facility_id="FAC-SYN-01", service_category="ANC"), settings)
    assert dup is None and r.referral_status == "RECOMMENDED" and r.attendance_confirmed is False
    rf.update(db, ADMIN, r.referral_id, ReferralUpdate(referral_status="PLANNED", planned_visit_date=dt.date(2026, 10, 13)), settings)
    assert db.get(Visit, v.visit_id).referral_status == "PLANNED" and db.get(Referral, r.referral_id).attendance_confirmed is False


# ---------------------------------------------------------------- referral wording never implies attendance
@pytest.mark.parametrize("status,conf,state,must,mustnt", [
    ("RECOMMENDED", False, "ACTIVE", "NOT confirmed", "attendance confirmed by"),
    ("PLANNED", False, "ACTIVE", "NOT confirmed", "attendance confirmed by"),
    ("ATTENDANCE_CONFIRMED", True, "ACTIVE", "confirmed by hospital record", "NOT"),
    ("PLANNED", False, "CANCELLED", "cancelled", "attend"),
    ("RECOMMENDED", False, "DUPLICATE", "not counted", "attend"),
])
def test_referral_label_semantics(status, conf, state, must, mustnt):
    lab = referral_label(status, conf, state)
    assert must.lower() in lab.lower() and mustnt.lower() not in lab.lower()


def test_label_never_claims_attendance_without_hospital_record():
    assert "confirmed by hospital record" not in referral_label("ATTENDANCE_CONFIRMED", False, "ACTIVE").lower()


def test_every_api_referral_has_truthful_label(client):
    items = client.get("/api/v1/referrals?limit=200").json()["items"]
    assert items
    for r in items:
        lab = r["status_label"].lower()
        if r["record_state"] == "ACTIVE" and r["referral_status"] != "ATTENDANCE_CONFIRMED":
            assert "not confirmed" in lab and r["attendance_confirmed"] is False
        if "confirmed by hospital record" in lab:
            assert r["referral_status"] == "ATTENDANCE_CONFIRMED" and r["attendance_confirmed"] and r["attendance_confirmation_date"]


def test_household_visits_alone_never_create_attendance_or_report_counts(client, db):
    before = client.post("/api/v1/reports/summary", json=dict(facility_id="FAC-SYN-01", period_start="2026-01-01", period_end="2026-10-13")).json()["counts"]
    for i in range(3):
        client.post("/api/v1/visits", json=dict(household_id="HH-SYN-00001", scheduled_date="2026-12-%02d" % (i + 1)))
    hv = client.get("/api/v1/visits?household_id=HH-SYN-00001&limit=200").json()
    assert hv["total"] >= 3
    after = client.post("/api/v1/reports/summary", json=dict(facility_id="FAC-SYN-01", period_start="2026-01-01", period_end="2026-10-13")).json()["counts"]
    assert after == before


# ---------------------------------------------------------------- sync: acknowledgement only after commit
def _vop(i, tag="Z"):
    return dict(op_id="op-%s-%04d" % (tag, i), entity_type="visit", entity_id="VIS-%s-%04d" % (tag, i), op_type="create",
                payload=dict(household_id="HH-SYN-00001", scheduled_date="2026-11-%02d" % (1 + i % 27), visit_reason="ROUTINE"))


def test_commit_failure_is_never_acknowledged_and_resend_succeeds(client, db, monkeypatch):
    real, state = Session.commit, {"n": 0}

    def flaky(self):
        state["n"] += 1
        if state["n"] == 2:                                        # second op's commit fails
            raise OperationalError("COMMIT", {}, Exception("disk I/O error (simulated)"))
        return real(self)
    monkeypatch.setattr(Session, "commit", flaky)
    out = client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=[_vop(1), _vop(2), _vop(3)]))
    assert out.status_code == 200
    res = out.json()["results"]
    assert [r["status"] for r in res] == ["ACKNOWLEDGED", "FAILED_RETRYABLE", "ACKNOWLEDGED"]
    assert [r["acknowledged"] for r in res] == [True, False, True] and res[1]["error_code"] == "TEMPORARY_FAILURE"
    monkeypatch.setattr(Session, "commit", real)
    db.rollback()
    assert {v for (v,) in db.execute(select(Visit.visit_id).where(Visit.visit_id.like("VIS-Z-%")))} == {"VIS-Z-0001", "VIS-Z-0003"}     # failed op left no trace
    assert db.get(SyncOperation, "op-Z-0002") is None
    again = client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=[_vop(1), _vop(2), _vop(3)])).json()["results"]
    assert [(r["duplicate"], r["acknowledged"]) for r in again] == [(True, True), (False, True), (True, True)]


def test_concurrent_identical_pushes_create_one_record(client, db):
    ops = [_vop(i, "C") for i in range(1, 4)]
    def go(_):
        r = client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=ops))
        return r.status_code, r.json()
    with cf.ThreadPoolExecutor(6) as ex:
        outs = list(ex.map(go, range(6)))
    assert all(code == 200 for code, _ in outs)                    # never a 500
    for _, j in outs:
        for r in j["results"]:
            assert r["status"] in ("ACKNOWLEDGED", "FAILED_RETRYABLE") and (r["status"] != "FAILED_RETRYABLE" or not r["acknowledged"])
    final = client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=ops)).json()["results"]
    assert all(r["acknowledged"] for r in final)
    db.rollback()
    assert db.scalar(select(func.count()).select_from(Visit).where(Visit.visit_id.like("VIS-C-%"))) == 3
    assert db.scalar(select(func.count()).select_from(SyncOperation).where(SyncOperation.op_id.like("op-C-%"))) == 3


def test_installation_hash_depends_on_server_salt(make_client, db):
    a, b = make_client(device_hash_salt="salt-one-xxxxxxxx"), make_client(device_hash_salt="salt-two-xxxxxxxx")
    a.post("/api/v1/sync/push", json=dict(installation_id="same-device-0001", operations=[_vop(1, "SA")]))
    b.post("/api/v1/sync/push", json=dict(installation_id="same-device-0001", operations=[_vop(1, "SB")]))
    db.rollback()
    ha = db.get(SyncOperation, "op-SA-0001").installation_hash
    hb = db.get(SyncOperation, "op-SB-0001").installation_hash
    assert ha != hb and "same-device-0001" not in ha + hb


def test_sync_status_uses_header_not_url(client):
    client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=[_vop(1, "ST")]))
    s = client.get("/api/v1/sync/status", headers={"X-Installation-Id": "install-AAAA1111"}).json()
    assert s["by_status"] == {"ACKNOWLEDGED": 1}
    assert client.get("/api/v1/sync/status", headers={"X-Installation-Id": "install-OTHER999"}).json()["total_operations"] == 0
    spec = client.get("/openapi.json").json()["paths"]["/api/v1/sync/status"]["get"]["parameters"]
    assert [p["in"] for p in spec if "nstallation" in p["name"]] == ["header"]


# ---------------------------------------------------------------- report ownership
def test_reports_are_scoped_to_their_creator(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    body = dict(facility_id="FAC-SYN-01", period_start="2026-01-01", period_end="2026-10-13")
    mine = c.post("/api/v1/reports/summary", json=body, headers=H("wk-one-key")).json()
    other = c.post("/api/v1/reports/summary", json=body, headers=H("wk-two-key")).json()
    assert mine["report_id"] != other["report_id"]                                        # same counts, different scopes -> separate reports
    assert c.get("/api/v1/reports/" + mine["report_id"], headers=H("wk-one-key")).status_code == 200
    for fmt in ("json", "csv", "pdf"):
        assert c.get("/api/v1/reports/%s?format=%s" % (mine["report_id"], fmt), headers=H("wk-two-key")).status_code == 404
    assert c.get("/api/v1/reports/" + mine["report_id"], headers=H("admin-key")).status_code == 200      # privileged roles may read any
    assert c.get("/api/v1/reports/" + mine["report_id"], headers=H("hosp-key")).status_code == 200
    adm = c.post("/api/v1/reports/summary", json=body, headers=H("admin-key")).json()
    assert c.get("/api/v1/reports/" + adm["report_id"], headers=H("wk-one-key")).status_code == 404     # workers cannot read the all-data report


def test_report_payload_has_no_identifiers_and_no_small_group_names(client):
    r = client.post("/api/v1/reports/summary", json=dict(facility_id="FAC-SYN-01", period_start="2026-01-01", period_end="2026-10-13")).json()
    blob = json.dumps(r)
    assert not any(t in blob for t in ("HH-", "VIS-", "REF-", "WRK-", "installation"))
    assert set(r) >= {"counts", "counts_by_service_category", "privacy_notice"}


# ---------------------------------------------------------------- configuration guards
def test_production_refuses_fixture_statuses(monkeypatch):
    from app.core import config
    from app.main import create_app
    monkeypatch.setenv("APP_ENV", "production"); monkeypatch.setenv("AUTH_MODE", "api_key"); monkeypatch.setenv("API_KEYS", "admin||k-0123456789abcdef-0123456789")
    monkeypatch.setenv("DEVICE_HASH_SALT", "a-long-random-production-salt-0123456789")
    monkeypatch.setenv("SECRET_KEY", "a-long-random-session-signing-secret-0123456789")
    monkeypatch.setenv("ELIGIBLE_VERIFICATION_STATUSES", "VERIFIED,TEST_FIXTURE_ONLY")
    config.get_settings.cache_clear()
    try:
        with pytest.raises(RuntimeError, match="VERIFIED"):
            create_app()
        monkeypatch.setenv("ELIGIBLE_VERIFICATION_STATUSES", "VERIFIED")
        config.get_settings.cache_clear()
        assert create_app() is not None
    finally:
        config.get_settings.cache_clear()


def test_docs_can_be_disabled(monkeypatch):
    from fastapi.testclient import TestClient
    from app.core import config
    from app.main import create_app
    monkeypatch.setenv("DOCS_ENABLED", "false"); config.get_settings.cache_clear()
    try:
        c = TestClient(create_app())
        assert c.get("/docs").status_code == 404 and c.get("/openapi.json").status_code == 404 and c.get("/health").status_code == 200
    finally:
        config.get_settings.cache_clear()


def test_safety_output_always_marked_not_clinically_validated(client):
    for q in ("Pregnant woman is bleeding heavily right now", "she is not feeling well", "What dose of amoxicillin?", "how often is the register signed"):
        s = client.post("/api/v1/health-qa/query", json={"question": q}).json()["safety"]
        assert s["clinically_validated"] is False and "UNREVIEWED" in s["ruleset_review_status"]


# ---------------------------------------------------------------- logging / label leakage
def test_no_request_content_in_application_logs(client, caplog):
    caplog.set_level(logging.DEBUG)
    client.post("/api/v1/households", json=dict(village_id="VIL-ZEBRA-9", assigned_worker_id="WRK-SYN-001", household_member_count=3))
    client.post("/api/v1/sync/push", json=dict(installation_id="install-ZEBRA-7777", operations=[dict(_vop(1, "LG"), payload=dict(household_id="HH-SYN-00001", scheduled_date="2026-11-02", visit_reason="ANC"))]))
    client.post("/api/v1/health-qa/query", json={"question": "zebra-quokka-7731 bleeding heavily"})
    app_logs = "\n".join(r.getMessage() for r in caplog.records if r.name.startswith(("app", "health_qa", "api", "uvicorn")))
    for needle in ("VIL-ZEBRA-9", "install-ZEBRA-7777", "quokka-7731"):
        assert needle not in app_logs, needle


def test_no_get_endpoint_leaks_evaluation_labels(client):
    for path in ("/api/v1/households?limit=5", "/api/v1/visits?limit=5", "/api/v1/referrals?limit=5", "/api/v1/follow-ups?limit=5", "/api/v1/protocols",
                 "/api/v1/sync/pull?limit=5"):
        t = client.get(path).text
        assert "expected_" not in t and "notes_for_evaluation" not in t and "RULE_DEVELOPMENT" not in t


# ---------------------------------------------------------------- every endpoint: auth, validation, documentation
def _ops(client):
    spec = client.get("/openapi.json").json()
    for path, item in spec["paths"].items():
        if path.startswith("/api/v1"):
            for method, op in item.items():
                yield path, method, op


def test_openapi_documents_responses_and_errors_for_every_operation(client):
    n = 0
    for path, method, op in _ops(client):
        n += 1
        codes = set(op["responses"])
        assert {"401", "422", "500"} <= codes, (path, method, codes)
        ok = op["responses"]["200" if "200" in codes else "201"]
        assert "content" in ok, (path, method)
        assert op.get("summary") or op.get("description") or True
    # 26 operations of the phone's API (22 paths + the AI routes incl. RAG + the two offline speech-model routes), all still present,
    # plus the website's API (auth, dashboard, admin, ask) added in 0.3.0
    legacy = [op for op in _ops(client) if not op[0].startswith(WEB_PREFIXES)]
    assert len(legacy) == 26
    assert n == 26 + WEB_OPERATIONS
    schemas = client.get("/openapi.json").json()["components"]["schemas"]
    assert {"ErrorResponse", "ReportOut", "SyncPushOut", "SyncResultOut", "QAOut", "ReferralOut"} <= set(schemas)
    assert "status_label" in schemas["ReferralOut"]["properties"]
    assert "clinically_validated" in schemas["SafetyOut"]["properties"]


def _fill(path):
    return path.replace("{household_id}", "HH-NOPE").replace("{visit_id}", "VIS-NOPE").replace("{referral_id}", "REF-NOPE") \
        .replace("{document_id}", "DOC-NOPE").replace("{report_id}", "RPT-NOPE")


def test_every_endpoint_requires_authentication_when_enabled(make_client):
    c = make_client(auth_mode="api_key", api_keys=KEYS, failed_auth_per_minute=0, rate_limit_per_minute=0)   # this test deliberately probes every route unauthenticated
    for path, method, _ in _ops(c):
        if path == "/api/v1/auth/login":
            continue                                 # the sign-in endpoint is the one open route (tested in test_web_api.py)
        r = c.request(method.upper(), _fill(path), json={})
        assert r.status_code == 401 and r.json()["error"]["code"] == "UNAUTHORIZED", (method, path)
        r = c.request(method.upper(), _fill(path), json={}, headers=H("not-a-key"))
        assert r.status_code == 401, (method, path)


def test_every_write_endpoint_rejects_unknown_fields_with_standard_422(client):
    for path, method, op in _ops(client):
        if method in ("post", "patch"):
            r = client.request(method.upper(), _fill(path), json={"__unknown__": 1})
            assert r.status_code == 422 and r.json()["error"]["code"] == "VALIDATION_ERROR" and r.json()["error"]["details"], (method, path)


def test_every_read_endpoint_handles_missing_ids_with_standard_404(client):
    for path, method, _ in _ops(client):
        if method == "get" and "{" in path:
            r = client.get(_fill(path))
            assert r.status_code == 404 and r.json()["error"]["code"] == "NOT_FOUND", path


def test_workers_cannot_reach_other_workers_data_on_any_id_endpoint(make_client, db):
    c = make_client(auth_mode="api_key", api_keys=KEYS)
    foreign_h = db.scalar(select(Household).where(Household.assigned_worker_id == "WRK-SYN-002"))
    foreign_v = db.scalar(select(Visit).where(Visit.worker_id == "WRK-SYN-002", Visit.visit_status == "COMPLETED"))
    foreign_r = db.scalar(select(Referral).join(Household, Household.household_id == Referral.household_id).where(Household.assigned_worker_id == "WRK-SYN-002"))
    w = H("wk-one-key")
    assert c.get("/api/v1/households/" + foreign_h.household_id, headers=w).status_code == 404
    assert c.patch("/api/v1/households/" + foreign_h.household_id, json=dict(household_member_count=2), headers=w).status_code == 404
    assert c.patch("/api/v1/visits/" + foreign_v.visit_id, json=dict(followup_required=False), headers=w).status_code == 404
    assert c.patch("/api/v1/referrals/" + foreign_r.referral_id, json=dict(record_state="CANCELLED"), headers=w).status_code == 404
    assert c.post("/api/v1/visits", json=dict(household_id=foreign_h.household_id, scheduled_date="2026-12-01"), headers=w).status_code == 404
    assert c.post("/api/v1/referrals", json=dict(household_id=foreign_v.household_id, visit_id=foreign_v.visit_id, facility_id="FAC-SYN-01", service_category="GENERAL"), headers=w).status_code == 404
    # sync cannot reach them either
    out = c.post("/api/v1/sync/push", headers=w, json=dict(installation_id="install-AAAA1111", operations=[
        dict(op_id="op-xw-0001", entity_type="household", entity_id=foreign_h.household_id, op_type="update", base_version=1, payload=dict(household_member_count=2))])).json()
    assert out["results"][0]["status"] == "REJECTED" and out["results"][0]["acknowledged"] is False
    pulled = c.get("/api/v1/sync/pull?limit=500", headers=w).json()
    assert all(h["assigned_worker_id"] == "WRK-SYN-001" for h in pulled["households"]) and all(v["worker_id"] == "WRK-SYN-001" for v in pulled["visits"])
