import pytest
from sqlalchemy import select

from app.db.models import Referral, Visit
from app.tests.conftest import REF


def _completed_visit_without_referral(db):
    return db.scalar(select(Visit).where(Visit.visit_status == "COMPLETED", Visit.referral_status == "NONE", Visit.actual_visit_date <= REF))


def _create(client, v, **kw):
    body = dict(household_id=v.household_id, visit_id=v.visit_id, facility_id="FAC-SYN-01", service_category="GENERAL", referral_status="RECOMMENDED")
    body.update(kw)
    return client.post("/api/v1/referrals", json=body)


def test_create_recommended_referral_updates_visit(client, db):
    v = _completed_visit_without_referral(db)
    r = _create(client, v)
    assert r.status_code == 201
    j = r.json()
    assert j["referral_status"] == "RECOMMENDED" and j["attendance_confirmed"] is False and j["planned_visit_date"] is None and j["record_state"] == "ACTIVE"
    lst = client.get("/api/v1/visits?household_id=%s&status=COMPLETED&limit=200" % v.household_id).json()["items"]
    mine = [x for x in lst if x["visit_id"] == v.visit_id][0]
    assert mine["referral_id"] == j["referral_id"] and mine["referral_status"] == "RECOMMENDED"


def test_full_lifecycle_recommended_planned_confirmed(client, db):
    v = _completed_visit_without_referral(db)
    rid = _create(client, v).json()["referral_id"]
    p = client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="PLANNED", planned_visit_date=REF))
    assert p.status_code == 200 and p.json()["planned_visit_date"] == REF and p.json()["attendance_confirmed"] is False     # planned != attended
    c = client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-TEST-1", attendance_confirmation_date=REF))
    assert c.status_code == 200 and c.json()["attendance_confirmed"] is True and c.json()["version"] == 3
    imm = client.patch("/api/v1/referrals/" + rid, json=dict(planned_visit_date="2026-10-14"))
    assert imm.status_code == 409 and imm.json()["error"]["code"] in ("CONFIRMED_IMMUTABLE", "INVALID_TRANSITION")


@pytest.mark.parametrize("start,target,ok", [("RECOMMENDED", "ATTENDANCE_CONFIRMED", False), ("PLANNED", "RECOMMENDED", False)])
def test_invalid_transitions(client, db, start, target, ok):
    v = _completed_visit_without_referral(db)
    rid = _create(client, v).json()["referral_id"]
    if start == "PLANNED":
        client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="PLANNED", planned_visit_date=REF))
    r = client.patch("/api/v1/referrals/" + rid, json=dict(referral_status=target, attendance_record_id="ATT-TEST-2", attendance_confirmation_date=REF))
    assert r.status_code == 409 and r.json()["error"]["code"] == "INVALID_TRANSITION"


def test_confirmation_requires_attendance_record(client, db):
    v = _completed_visit_without_referral(db)
    rid = _create(client, v, referral_status="PLANNED", planned_visit_date=REF).json()["referral_id"]
    r = client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="ATTENDANCE_CONFIRMED"))
    assert r.status_code == 422 and r.json()["error"]["code"] == "ATTENDANCE_RECORD_REQUIRED"
    r = client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-T3", attendance_confirmation_date="2026-10-14"))
    assert r.status_code == 422                                                         # after "today"


def test_validation_rules_on_create(client, db):
    v = _completed_visit_without_referral(db)
    assert _create(client, v, referral_status="PLANNED").json()["error"]["code"] == "PLANNED_DATE_REQUIRED"
    assert _create(client, v, planned_visit_date=REF).json()["error"]["code"] == "PLANNED_DATE_NOT_ALLOWED"
    assert _create(client, v, referral_status="ATTENDANCE_CONFIRMED").status_code == 422        # cannot be created confirmed
    assert _create(client, v, facility_id="FAC-NOPE").json()["error"]["code"] == "UNKNOWN_FACILITY"
    planned_visit = db.scalar(select(Visit).where(Visit.visit_status == "PLANNED"))
    assert _create(client, planned_visit).json()["error"]["code"] == "VISIT_NOT_COMPLETED"


def test_duplicate_referral_rejected_on_rest(client, db):
    v = _completed_visit_without_referral(db)
    assert _create(client, v).status_code == 201
    d = _create(client, v)
    assert d.status_code == 409 and d.json()["error"]["code"] == "DUPLICATE_REFERRAL"


def test_cancel_clears_visit_link(client, db):
    v = _completed_visit_without_referral(db)
    rid = _create(client, v).json()["referral_id"]
    c = client.patch("/api/v1/referrals/" + rid, json=dict(record_state="CANCELLED"))
    assert c.status_code == 200 and c.json()["record_state"] == "CANCELLED"
    mine = [x for x in client.get("/api/v1/visits?household_id=%s&limit=200" % v.household_id).json()["items"] if x["visit_id"] == v.visit_id][0]
    assert mine["referral_status"] == "NONE" and mine["referral_id"] is None
    assert client.patch("/api/v1/referrals/" + rid, json=dict(referral_status="PLANNED", planned_visit_date=REF)).status_code == 409


def test_confirmed_referral_cannot_be_cancelled(client, db):
    r = db.scalar(select(Referral).where(Referral.referral_status == "ATTENDANCE_CONFIRMED", Referral.record_state == "ACTIVE"))
    x = client.patch("/api/v1/referrals/" + r.referral_id, json=dict(record_state="CANCELLED"))
    assert x.status_code == 409


def test_list_filters(client):
    j = client.get("/api/v1/referrals?facility_id=FAC-SYN-02&status=PLANNED&limit=200").json()
    assert j["total"] > 0 and all(r["facility_id"] == "FAC-SYN-02" and r["referral_status"] == "PLANNED" for r in j["items"])
    j = client.get("/api/v1/referrals?record_state=DUPLICATE").json()
    assert j["total"] > 0 and all(r["duplicate_of"] for r in j["items"])
    assert client.get("/api/v1/referrals?status=BOGUS").status_code == 422
    c = client.get("/api/v1/referrals?created_from=2026-09-01&created_to=2026-09-30&limit=200").json()
    assert all("2026-09-01" <= r["referral_created_date"] <= "2026-09-30" for r in c["items"])
