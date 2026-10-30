"""Dashboard API: block register, VIS visit list parity, map, households, referrals/escalations, Q&A audit privacy, exports, reveals,
per-phone sync status, and sync safety (idempotent, no duplicate households) with per-phone keys."""
import concurrent.futures as cf
import csv
import io
import json
import logging
import os
from datetime import date

from sqlalchemy import func, select

from app.db.models import AdminAudit, Household, Member, QaAudit, Visit
from app.tests.conftest import H5_DIR, login, needs_pack

pytestmark = needs_pack
GOLDEN = os.path.join(os.path.dirname(H5_DIR), "golden")


def test_block_seed_counts(bdb):
    assert bdb.scalar(select(func.count()).select_from(Member)) == 2234
    assert bdb.scalar(select(func.count()).select_from(Household).where(~Household.household_id.like("HH-SYN-%"))) == 500


def test_visit_list_equals_python_engine_golden(web):
    """All 346 rows of golden/golden_visit.json (the h5 engine's own output for 2026-10-26) come back from the API, with priority/status/date."""
    c = web()
    h = login(c, "admin")
    golden = {tuple(r) for r in json.load(open(os.path.join(GOLDEN, "golden_visit.json"), encoding="utf-8"))}
    got = set()
    for a in c.get("/api/v1/dashboard/ashas", headers=h).json():
        vl = c.get("/api/v1/dashboard/visit-list?worker_id=%s&date=2026-10-26" % a["worker_id"], headers=h).json()
        for g in vl["groups"]:
            assert all(i["priority"] == g["priority"] for i in g["items"])
            got |= {(i["member_id"], i["due_item"], i["priority"], i["status"], i["due_date"]) for i in g["items"]}
    assert got == golden and len(golden) == 346


def test_maps_are_the_phone_apps_maps(web):
    c = web()
    h = login(c, "admin")
    maps = os.path.join(os.path.dirname(H5_DIR), "health-worker-app", "assets", "h5", "maps")
    if not os.path.isdir(maps):
        import pytest
        pytest.skip("phone app assets not present")
    for v in c.get("/api/v1/dashboard/villages", headers=h).json():
        if not v["has_map"]:
            continue
        m = c.get("/api/v1/dashboard/map/" + v["village_id"], headers=h).json()
        phone = json.load(open(os.path.join(maps, v["village_id"] + ".json"), encoding="utf-8"))
        assert m["made_up"] is True and m["roads"] == phone["roads"] and m["bounds"] == phone["bounds"]
        assert {x["household_id"]: [x["lat"], x["lng"]] for x in m["houses"]} == {x[0]: x[1:] for x in phone["houses"]}
        assert {x["urgency"] for x in m["houses"]} <= {"URGENT", "DUE", "THIS_WEEK", "NONE"}


def test_household_filters_and_pagination(web):
    c = web()
    h = login(c, "anm")
    all_ = c.get("/api/v1/dashboard/households?village_id=amrapur&limit=200", headers=h).json()
    assert all_["total"] == 106 and len(all_["items"]) == 106
    p2 = c.get("/api/v1/dashboard/households?village_id=amrapur&limit=50&offset=50", headers=h).json()
    assert p2["items"] == all_["items"][50:100]
    urgent = c.get("/api/v1/dashboard/households?urgency=URGENT&limit=200", headers=h).json()
    assert urgent["total"] > 0 and all(i["urgency"] == "URGENT" and i["top_priority"] == 1 for i in urgent["items"])
    p3 = c.get("/api/v1/dashboard/households?priority=3&limit=200", headers=h).json()
    assert all(i["top_priority"] == 3 for i in p3["items"])
    by_asha = c.get("/api/v1/dashboard/households?worker_id=ASHA-KQXR&limit=200", headers=h).json()
    assert {i["village_id"] for i in by_asha["items"]} == {"navagaon-khurd", "sitapahari"}
    assert c.get("/api/v1/dashboard/households?q=AM-108", headers=h).json()["items"][0]["house_no"] == "AM-108"


def test_household_detail_masks_phone_and_reveal_is_audited(web, bdb):
    c = web()
    h = login(c, "anm")
    d = c.get("/api/v1/dashboard/households/HH-014Q8O", headers=h).json()
    assert d["members"] and d["house_no"] == "BE-189" and d["phone_masked"].startswith("+91 ••") and d["phone_masked"][-3:].isdigit()
    assert "phone_number" not in json.dumps(d)
    r = c.post("/api/v1/dashboard/households/HH-014Q8O/reveal-phone", json={"reason": "CALL_FAMILY"}, headers=h).json()
    assert r["phone_number"].startswith("+91 5") and r["phone_number"][-3:] == d["phone_masked"][-3:] and r["synthetic"]
    bdb.expire_all()
    a = bdb.scalar(select(AdminAudit).where(AdminAudit.action == "phone_reveal"))
    assert a.actor == "user:anm" and a.target == "HH-014Q8O" and r["phone_number"] not in json.dumps(a.details)


def test_overview_numbers_are_consistent(web):
    c = web()
    h = login(c, "admin")
    o = c.get("/api/v1/dashboard/overview", headers=h).json()
    golden = json.load(open(os.path.join(GOLDEN, "golden_visit.json"), encoding="utf-8"))
    assert o["due_today"] == sum(1 for r in golden if r[3] == "due_today")
    assert o["overdue"] == sum(1 for r in golden if r[3] == "overdue")
    assert o["upcoming"] == sum(1 for r in golden if r[3] == "due_this_week")
    assert len(o["priority1"]) == sum(1 for r in golden if r[2] == 1) and o["people"] == 2234


def test_ask_audit_never_stores_question_text(web, bdb, caplog):
    caplog.set_level(logging.DEBUG)
    c = web()
    h = login(c, "anm")
    q = "zebra-marker-7781 delivery ko 2 din hue, din me 8 pad badal chuki hai"
    r = c.post("/api/v1/ask", json={"question": q}, headers=h).json()
    assert r["escalate"] is True and r["outcome"] == "ESCALATED" and r["answer_text"].startswith("REFER IMMEDIATELY")
    assert r["disclaimer"] == "Clinician-assisting only, not a diagnosis."
    bdb.expire_all()
    row = bdb.get(QaAudit, r["audit_id"])
    assert row.outcome == "ESCALATED" and row.status == "OPEN" and row.cited_section_ids == r["cited_section_ids"]
    dump = json.dumps({k: str(getattr(row, k)) for k in row.__table__.columns.keys()})
    assert "zebra" not in dump and "pad badal" not in dump and "zebra" not in caplog.text
    feed = c.get("/api/v1/dashboard/escalations?days=7", headers=h).json()
    assert feed["items"][0]["id"] == r["audit_id"]


def test_escalation_workflow_records_who_handled_it(web):
    c = web()
    h = login(c, "anm")
    eid = c.post("/api/v1/ask", json={"question": "pregnant bahu ko abhi jhatke aaye"}, headers=h).json()["audit_id"]
    r = c.patch("/api/v1/dashboard/escalations/%d" % eid, json={"status": "ACKNOWLEDGED", "note_code": "REFERRED_108"}, headers=h).json()
    assert r["status"] == "ACKNOWLEDGED" and r["handled_by"] == "user:anm" and r["note_code"] == "REFERRED_108"
    assert c.patch("/api/v1/dashboard/escalations/%d" % eid, json={"status": "CLOSED"}, headers=h).json()["status"] == "CLOSED"
    back = c.patch("/api/v1/dashboard/escalations/%d" % eid, json={"status": "ACKNOWLEDGED"}, headers=h)
    assert back.status_code == 409
    asha = login(c, "asha.kalavati")
    assert c.patch("/api/v1/dashboard/escalations/%d" % eid, json={"status": "CLOSED"}, headers=asha).status_code == 403


def test_supervisor_can_plan_and_confirm_referrals_and_feed_shows_handler(web):
    c = web()
    h = login(c, "anm")
    ref = c.get("/api/v1/dashboard/referrals?status=RECOMMENDED&state=ACTIVE&limit=1", headers=h).json()["items"][0]
    r = c.patch("/api/v1/referrals/" + ref["referral_id"], json={"referral_status": "PLANNED", "planned_visit_date": "2026-10-13", "version": ref["version"]}, headers=h)
    assert r.status_code == 200, r.text
    r = c.patch("/api/v1/referrals/" + ref["referral_id"], json={"referral_status": "ATTENDANCE_CONFIRMED", "attendance_record_id": "ATT-TEST-1",
                                                                 "attendance_confirmation_date": "2026-10-13", "version": r.json()["version"]}, headers=h)
    assert r.status_code == 200, r.text
    feed = c.get("/api/v1/dashboard/referrals?status=ATTENDANCE_CONFIRMED&limit=200", headers=h).json()["items"]
    mine = [x for x in feed if x["referral_id"] == ref["referral_id"]][0]
    assert mine["handled_by"] == "user:anm"


def test_exports_csv_pdf_are_audited_and_contain_no_phone_numbers(web, bdb):
    c = web()
    h = login(c, "anm")
    r = c.get("/api/v1/dashboard/reports/export?kind=households&format=csv", headers=h)
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/csv") and "attachment" in r.headers["content-disposition"]
    text = r.content.decode("utf-8-sig")
    assert "SYNTHETIC" in text and "+91" not in text
    rows = list(csv.reader(io.StringIO(text)))
    assert rows[1][0] == "household_id" and len(rows) == 2 + 1000
    pdf = c.get("/api/v1/dashboard/reports/export?kind=visit-list&format=pdf&worker_id=ASHA-RRR5", headers=h)
    assert pdf.status_code == 200 and pdf.content.startswith(b"%PDF")
    assert c.get("/api/v1/dashboard/reports/export?kind=summary&format=pdf", headers=h).content.startswith(b"%PDF")
    assert c.get("/api/v1/dashboard/reports/export?kind=summary&format=csv", headers=h).status_code == 422
    bdb.expire_all()
    ex = list(bdb.scalars(select(AdminAudit).where(AdminAudit.action == "export")))
    assert len(ex) == 3 and {e.target for e in ex} == {"households", "visit-list", "summary"} and all(e.actor == "user:anm" for e in ex)


def test_sync_from_phone_key_is_idempotent_and_shows_in_dashboard(web, bdb):
    """Phone on mobile data drops out mid-push and resends: same op ids -> one household, one visit; dashboard shows the family."""
    c = web()
    admin = login(c, "admin")
    key = c.post("/api/v1/admin/phones", json={"worker_id": "WRK-SYN-001", "label": "field phone"}, headers=admin).json()["api_key"]
    phone = {"X-API-Key": key, "User-Agent": "Dart/3.5 (dart:io)"}
    ops = [dict(op_id="op-new-family-0001", entity_type="household", entity_id="HH-PHONE-0001", op_type="create",
                payload=dict(village_id="VIL-SYN-01", assigned_worker_id="WRK-SYN-001", household_member_count=4, eligible_followup_categories=["ANC", "ROUTINE"])),
           dict(op_id="op-new-visit-0001", entity_type="visit", entity_id="VIS-PHONE-0001", op_type="create",
                payload=dict(household_id="HH-PHONE-0001", worker_id="WRK-SYN-001", scheduled_date="2026-10-20", visit_reason="ANC"))]
    body = dict(installation_id="install-field-0001", operations=ops)
    first = c.post("/api/v1/sync/push", json=body, headers=phone).json()
    assert [r["acknowledged"] for r in first["results"]] == [True, True]
    for _ in range(3):                                            # the phone never saw the answer and resends the same batch
        again = c.post("/api/v1/sync/push", json=body, headers=phone).json()
        assert all(r["duplicate"] and r["acknowledged"] for r in again["results"])
    bdb.expire_all()
    assert bdb.scalar(select(func.count()).select_from(Household).where(Household.household_id == "HH-PHONE-0001")) == 1
    assert bdb.scalar(select(func.count()).select_from(Visit).where(Visit.visit_id == "VIS-PHONE-0001")) == 1
    found = c.get("/api/v1/dashboard/households?q=HH-PHONE&limit=5", headers=admin).json()
    assert found["total"] == 1 and found["items"][0]["from_phone"] is True
    st = [p for p in c.get("/api/v1/dashboard/sync-status", headers=admin).json() if p["label"] == "field phone"][0]
    assert st["pushes"] == 4 and st["ops_received"] == 8 and st["ops_acknowledged"] == 2 and st["stale"] is False and st["client_agent"].startswith("Dart")


def test_concurrent_duplicate_pushes_from_two_connections_store_one_household(web, bdb):
    c = web(rate_limit_per_minute=0)
    key = c.post("/api/v1/admin/phones", json={"worker_id": "WRK-SYN-001", "label": "racer"}, headers=login(c, "admin")).json()["api_key"]
    body = dict(installation_id="install-race-0001", operations=[dict(op_id="op-race-hh-0001", entity_type="household", entity_id="HH-RACE-0001", op_type="create",
                payload=dict(village_id="VIL-SYN-02", assigned_worker_id="WRK-SYN-001", household_member_count=3))])
    with cf.ThreadPoolExecutor(6) as ex:
        res = list(ex.map(lambda _: c.post("/api/v1/sync/push", json=body, headers={"X-API-Key": key}).json(), range(6)))
    acked = [r["results"][0] for r in res]                       # never a 500; a loser of the race is told to resend, never falsely acked
    assert all(r["status"] in ("ACKNOWLEDGED", "FAILED_RETRYABLE") and (r["status"] == "ACKNOWLEDGED") == r["acknowledged"] for r in acked)
    assert sum(1 for r in acked if r["acknowledged"] and not r["duplicate"]) <= 1
    final = c.post("/api/v1/sync/push", json=body, headers={"X-API-Key": key}).json()["results"][0]
    assert final["acknowledged"] and final["duplicate"]
    bdb.rollback()
    assert bdb.scalar(select(func.count()).select_from(Household).where(Household.household_id == "HH-RACE-0001")) == 1


def test_phone_app_contract_unchanged(web):
    """The phone's endpoints answer exactly as before (same keys) when called with a per-phone key."""
    c = web()
    key = c.post("/api/v1/admin/phones", json={"worker_id": "WRK-SYN-001", "label": "contract"}, headers=login(c, "admin")).json()["api_key"]
    h = {"X-API-Key": key}
    pull = c.get("/api/v1/sync/pull?entity_types=household,visit,referral&limit=3", headers=h).json()
    assert set(pull) == {"server_time", "households", "visits", "referrals"}
    assert set(pull["households"][0]) >= {"household_id", "village_id", "assigned_worker_id", "version", "record_status"}
    assert "house_no" not in pull["households"][0] and "phone_number" not in json.dumps(pull)
    st = c.get("/api/v1/sync/status", headers=dict(h, **{"X-Installation-Id": "install-x-0001"})).json()
    assert set(st) == {"total_operations", "by_status", "last_acknowledged_at", "conflicts", "rejected"}
    assert c.get("/health").json()["status"] == "ok"


def test_server_info_qr_and_public_url_precedence(web, tmp_path):
    f = tmp_path / "public_url.txt"
    f.write_text("https://quick-words-here.trycloudflare.com\n")
    c = web(public_url_file=str(f))
    h = login(c, "admin")
    r = c.get("/api/v1/admin/server-info?check=false", headers=h).json()
    assert r["public_url"] == "https://quick-words-here.trycloudflare.com" and r["source"].startswith("tunnel script")
    assert r["qr_svg"].startswith("<svg") and "trycloudflare" in r["qr_svg"]
    assert c.patch("/api/v1/admin/settings", json={"public_url": "https://asha.example.org"}, headers=h).status_code == 200
    assert c.get("/api/v1/admin/server-info?check=false", headers=h).json()["public_url"] == "https://asha.example.org"
    assert c.patch("/api/v1/admin/settings", json={"public_url": "http://insecure.example"}, headers=h).status_code == 422


def test_retention_purges_old_audit_rows_but_keeps_open_escalations(web, bdb):
    import datetime as dt
    from app.db.models import QaAudit as Q
    old = dt.datetime.utcnow() - dt.timedelta(days=400)
    bdb.add_all([Q(at=old, actor="t", channel="web", outcome="ANSWERED", cited_section_ids=[], rule_ids=[]),
                 Q(at=old, actor="t", channel="web", outcome="ESCALATED", escalate=True, status="OPEN", cited_section_ids=[], rule_ids=[])])
    bdb.commit()
    c = web()
    r = c.patch("/api/v1/admin/settings", json={"retention_days": 30}, headers=login(c, "admin")).json()
    assert r["purged"]["qa_audit"] == 1
    bdb.expire_all()
    assert bdb.scalar(select(func.count()).select_from(Q).where(Q.at == old)) == 1


def test_html_pages_render_with_synthetic_banner(web):
    c = web()
    c.post("/login", data={"username": "admin", "password": "admin-password-1"})
    for p in ("/", "/visits", "/map", "/households", "/households/HH-014Q8O", "/referrals", "/ask", "/reports", "/admin", "/settings"):
        r = c.get(p)
        assert r.status_code == 200, p
        assert "Synthetic data" in r.text and "Clinician-assisting only, not a diagnosis" in r.text, p
    assert "Made-up map, house positions are not real" in c.get("/map").text
    te = c.get("/lang/te?next=/visits")
    assert "సందర్శనల జాబితా" in te.text
    assert c.get("/households/NOPE", headers={"Accept": "text/html"}).status_code == 404


def test_demo_date_default(web):
    c = web()
    assert c.get("/api/v1/dashboard/visit-list?worker_id=ASHA-RRR5", headers=login(c, "admin")).json()["date"] == date(2026, 10, 26).isoformat()
