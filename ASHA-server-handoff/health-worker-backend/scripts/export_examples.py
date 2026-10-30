#!/usr/bin/env python3
"""Capture REAL request/response pairs (from the test database copy) into docs/api_examples.json."""
import json, os, sqlite3, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from fastapi.testclient import TestClient
from app.core.config import BACKEND_ROOT, Settings, get_settings
from app.db.base import Base
import app.db.models  # noqa: F401
from app.db.session import get_db, make_engine, session_factory
from app.main import create_app
from app.services.dataset_import.importer import import_datasets

ds = os.path.abspath(os.path.join(BACKEND_ROOT, "..", "health-worker-datasets"))
tmp = tempfile.mkdtemp()
eng = make_engine("sqlite:///" + os.path.join(tmp, "x.db")); Base.metadata.create_all(eng)
with session_factory(eng)() as db: import_datasets(db, ds)
st = Settings(auth_mode="disabled", reference_date="2026-10-13", dataset_dir=ds)
app = create_app(); app.dependency_overrides[get_settings] = lambda: st
sf = session_factory(eng)
def _db():
    s = sf()
    try: yield s
    finally: s.close()
app.dependency_overrides[get_db] = _db
c = TestClient(app)
ex = []
def call(name, method, url, body=None, headers=None):
    r = c.request(method, url, json=body, headers=headers)
    try: resp = r.json()
    except Exception: resp = "<%s bytes %s>" % (len(r.content), r.headers.get("content-type"))
    if isinstance(resp, dict):
        for k in ("items", "households", "visits", "referrals"):
            if isinstance(resp.get(k), list) and len(resp[k]) > 1: resp[k] = resp[k][:1] + ["... (truncated)"]
    ex.append(dict(name=name, request=dict(method=method, url=url, headers=headers, body=body), status=r.status_code, response=resp))
    return r
call("QA: danger sign -> escalation (Telugu)", "POST", "/api/v1/health-qa/query", {"question": "గర్భిణీకి ఇప్పుడు విపరీతంగా రక్తస్రావం అవుతోంది"})
call("QA: no verified evidence -> insufficient evidence", "POST", "/api/v1/health-qa/query", {"question": "How often should a diabetic person be followed up?"})
call("QA: dosage request -> refusal", "POST", "/api/v1/health-qa/query", {"question": "What dose of amoxicillin should I give a child?"})
call("Households: list", "GET", "/api/v1/households?status=OVERDUE&limit=1")
call("Households: create", "POST", "/api/v1/households", {"village_id": "VIL-SYN-01", "assigned_worker_id": "WRK-SYN-001", "household_member_count": 4, "eligible_followup_categories": ["ANC", "ROUTINE"]})
call("Follow-ups: overdue with explanation", "GET", "/api/v1/follow-ups?bucket=OVERDUE&limit=1")
call("Report summary", "POST", "/api/v1/reports/summary", {"facility_id": "FAC-SYN-01", "period_start": "2026-06-01", "period_end": "2026-10-13", "last_sync_at": "2026-10-13T08:00:00+05:30"})
call("Sync push (create visit, repeated => duplicate)", "POST", "/api/v1/sync/push", {"installation_id": "install-AAAA1111", "operations": [{"op_id": "op-demo-0001", "entity_type": "visit", "entity_id": "VIS-DEMO-0001", "op_type": "create", "payload": {"household_id": "HH-SYN-00001", "scheduled_date": "2026-11-05", "visit_reason": "ROUTINE"}}]})
call("Sync push repeated", "POST", "/api/v1/sync/push", {"installation_id": "install-AAAA1111", "operations": [{"op_id": "op-demo-0001", "entity_type": "visit", "entity_id": "VIS-DEMO-0001", "op_type": "create", "payload": {"household_id": "HH-SYN-00001", "scheduled_date": "2026-11-05", "visit_reason": "ROUTINE"}}]})
call("Referrals: list (note status_label)", "GET", "/api/v1/referrals?status=PLANNED&limit=1")
# --- sync: conflict, rejection, malformed, status
from sqlalchemy import select
from app.db.models import Referral
with sf() as _s:
    _r = _s.scalar(select(Referral).where(Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE", Referral.planned_visit_date <= "2026-10-13"))
    rid = _r.referral_id
call("Referral: hospital/admin confirms attendance (needs attendance record)", "PATCH", "/api/v1/referrals/" + rid, {"referral_status": "ATTENDANCE_CONFIRMED", "attendance_record_id": "ATT-EXAMPLE-1", "attendance_confirmation_date": "2026-10-13"})
call("Sync push: stale update of a protected field => CONFLICT (not applied)", "POST", "/api/v1/sync/push", {"installation_id": "install-AAAA1111", "operations": [{"op_id": "op-demo-conf1", "entity_type": "referral", "entity_id": rid, "op_type": "update", "base_version": 1, "client_updated_at": "2026-10-13T09:00:00+05:30", "payload": {"referral_status": "PLANNED", "planned_visit_date": "2026-10-13"}}]})
call("Sync push: rejected + malformed operations", "POST", "/api/v1/sync/push", {"installation_id": "install-AAAA1111", "operations": [{"op_id": "op-demo-rej01", "entity_type": "visit", "entity_id": "VIS-DEMO-0002", "op_type": "create", "payload": {"household_id": "HH-DOES-NOT-EXIST", "scheduled_date": "2026-11-05"}}, {"op_id": "x", "entity_type": "nonsense"}]})
call("Sync status (installation id in header, never in URL)", "GET", "/api/v1/sync/status", None, {"X-Installation-Id": "install-AAAA1111"})
call("Error: not found", "GET", "/api/v1/households/NOPE")
call("Error: validation", "POST", "/api/v1/households", {"village_id": "x"})
out = os.path.join(BACKEND_ROOT, "docs", "api_examples.json")
json.dump(ex, open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print("wrote", out, len(ex), "examples")
