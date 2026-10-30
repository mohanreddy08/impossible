import datetime as dt

from sqlalchemy import func, select

from app.core.security import Principal
from app.db.models import Household, Visit
from app.services.visits import service as vs
from app.tests.conftest import REF

ADMIN = Principal("admin", None, "t")


# ---------------- household CRUD ----------------
def test_list_filter_search_paginate(client):
    r = client.get("/api/v1/households?limit=10&offset=0")
    j = r.json()
    assert r.status_code == 200 and len(j["items"]) == 10 and j["total"] >= 500 and j["limit"] == 10
    assert client.get("/api/v1/households?limit=1000").status_code == 422        # page size cap
    only = client.get("/api/v1/households?status=OVERDUE&limit=200").json()
    assert only["total"] > 0 and all(h["record_status"] == "OVERDUE" for h in only["items"])
    cat = client.get("/api/v1/households?category=ANC&limit=200").json()
    assert cat["total"] > 0 and all("ANC" in h["eligible_followup_categories"] for h in cat["items"])
    w = client.get("/api/v1/households?worker_id=WRK-SYN-001&limit=200").json()
    assert w["total"] > 0 and all(h["assigned_worker_id"] == "WRK-SYN-001" for h in w["items"])
    assert client.get("/api/v1/households?q=HH-SYN-00042").json()["total"] == 1


def test_get_household_and_404(client):
    h = client.get("/api/v1/households/HH-SYN-00001").json()
    assert h["household_id"] == "HH-SYN-00001" and isinstance(h["eligible_followup_categories"], list) and h["synthetic_record"] is True
    r = client.get("/api/v1/households/NOPE")
    assert r.status_code == 404 and r.json()["error"]["code"] == "NOT_FOUND"


def test_create_update_household(client):
    body = dict(village_id="VIL-SYN-01", assigned_worker_id="WRK-SYN-001", household_member_count=4, eligible_followup_categories=["ANC", "ROUTINE"])
    r = client.post("/api/v1/households", json=body)
    assert r.status_code == 201
    h = r.json()
    assert h["version"] == 1 and h["record_status"] == "NO_VISIT_DUE" and h["household_id"].startswith("HH-")
    p = client.patch("/api/v1/households/" + h["household_id"], json=dict(household_member_count=5, version=1))
    assert p.status_code == 200 and p.json()["household_member_count"] == 5 and p.json()["version"] == 2
    stale = client.patch("/api/v1/households/" + h["household_id"], json=dict(household_member_count=6, version=1))
    assert stale.status_code == 409 and stale.json()["error"]["code"] == "VERSION_CONFLICT"
    assert client.post("/api/v1/households", json=dict(body, household_id=h["household_id"])).status_code == 409


def test_household_validation(client):
    base = dict(village_id="VIL-SYN-01", assigned_worker_id="WRK-SYN-001", household_member_count=4)
    assert client.post("/api/v1/households", json=dict(base, household_member_count=0)).status_code == 422
    assert client.post("/api/v1/households", json=dict(base, eligible_followup_categories=["BOGUS"])).status_code == 422
    assert client.post("/api/v1/households", json=dict(base, name="Real Person")).status_code == 422     # no personal fields accepted
    r = client.post("/api/v1/households", json=dict(base, eligible_followup_categories=["ANC"], scheduled_followup_category="DIABETES"))
    assert r.status_code == 422 and r.json()["error"]["code"] == "CATEGORY_NOT_ELIGIBLE"
    err = client.post("/api/v1/households", json={}).json()["error"]
    assert err["code"] == "VALIDATION_ERROR" and err["details"]


# ---------------- daily visit lists ----------------
def test_due_today_and_overdue_match_register(client, db):
    due = client.get("/api/v1/follow-ups?bucket=DUE_TODAY&limit=200").json()
    over = client.get("/api/v1/follow-ups?bucket=OVERDUE&limit=200").json()
    reg_due = db.scalar(select(func.count()).select_from(Household).where(Household.record_status == "DUE_TODAY"))
    reg_over = db.scalar(select(func.count()).select_from(Household).where(Household.record_status == "OVERDUE"))
    assert due["total"] == reg_due and over["total"] == reg_over and reg_due > 0 and reg_over > 0
    assert all(i["scheduled_date"] == REF for i in due["items"])
    assert all(i["scheduled_date"] < REF and i["days_overdue"] > 0 for i in over["items"])


def test_followup_explains_itself(client):
    i = client.get("/api/v1/follow-ups?bucket=OVERDUE&limit=1").json()["items"][0]
    assert "overdue" in i["explanation"] and i["scheduled_date"] in i["explanation"] and i["category"] in i["explanation"]


def test_followup_filters(client):
    j = client.get("/api/v1/follow-ups?worker_id=WRK-SYN-002&category=ROUTINE&limit=200").json()
    assert all(i["worker_id"] == "WRK-SYN-002" and i["category"] == "ROUTINE" for i in j["items"])
    assert client.get("/api/v1/follow-ups?bucket=NOPE").status_code == 422
    one = j["items"][0]
    by_hh = client.get("/api/v1/follow-ups?household_id=" + one["household_id"]).json()
    assert by_hh["total"] >= 1
    on = client.get("/api/v1/follow-ups?on_date=" + one["scheduled_date"] + "&limit=200").json()
    assert all(i["scheduled_date"] == one["scheduled_date"] for i in on["items"])


def test_as_of_changes_buckets(client):
    base = client.get("/api/v1/follow-ups?bucket=OVERDUE&limit=1").json()["total"]
    later = client.get("/api/v1/follow-ups?bucket=OVERDUE&as_of=2027-01-01&limit=1").json()["total"]
    assert later >= base


def test_recompute_reproduces_register_for_every_household(db, settings):
    """Recalculating from visit history must give back the supplied register (dates + status)."""
    bad = []
    snap = {h.household_id: (h.last_visit_date, h.next_visit_due_date, h.scheduled_followup_category, h.record_status) for h in db.scalars(select(Household))}
    for hid, exp in snap.items():
        h = vs.recompute_household(db, hid, settings)
        if (h.last_visit_date, h.next_visit_due_date, h.scheduled_followup_category, h.record_status) != exp:
            bad.append((hid, exp, (h.last_visit_date, h.next_visit_due_date, h.scheduled_followup_category, h.record_status)))
    assert bad == [], bad[:3]


def test_record_visit_outcome_recalculates_tasks(client, db):
    h = db.scalar(select(Household).where(Household.record_status == "DUE_TODAY"))
    planned = db.scalar(select(Visit).where(Visit.household_id == h.household_id, Visit.visit_status == "PLANNED"))
    next_day = (dt.date.fromisoformat(REF) + dt.timedelta(days=30)).isoformat()
    r = client.patch("/api/v1/visits/" + planned.visit_id, json=dict(visit_status="COMPLETED", actual_visit_date=REF, followup_required=True, next_followup_date=next_day))
    assert r.status_code == 200 and r.json()["visit_status"] == "COMPLETED"
    hh = client.get("/api/v1/households/" + h.household_id).json()
    assert hh["last_visit_date"] == REF and hh["next_visit_due_date"] == next_day and hh["record_status"] == "UPCOMING"
    tasks = client.get("/api/v1/follow-ups?household_id=" + h.household_id).json()
    assert [t["scheduled_date"] for t in tasks["items"]] == [next_day]                    # old task gone, new one created
    assert client.patch("/api/v1/visits/" + planned.visit_id, json=dict(visit_status="PLANNED")).status_code == 409     # final


def test_visit_validation(client, db):
    h = db.scalar(select(Household).where(Household.record_status == "DUE_TODAY"))
    planned = db.scalar(select(Visit).where(Visit.household_id == h.household_id, Visit.visit_status == "PLANNED"))
    p = "/api/v1/visits/" + planned.visit_id
    assert client.patch(p, json=dict(visit_status="COMPLETED")).json()["error"]["code"] == "ACTUAL_DATE_REQUIRED"
    assert client.patch(p, json=dict(visit_status="COMPLETED", actual_visit_date="2030-01-01")).json()["error"]["code"] == "FUTURE_ACTUAL_DATE"
    assert client.patch(p, json=dict(visit_status="BOGUS")).status_code == 422
    assert client.patch(p, json=dict(actual_visit_date=REF)).json()["error"]["code"] == "ACTUAL_DATE_NOT_ALLOWED"
    assert client.patch(p, json=dict(visit_status="COMPLETED", actual_visit_date=REF, followup_required=True)).json()["error"]["code"] == "FOLLOWUP_INCONSISTENT"
    assert client.patch(p, json=dict(visit_status="COMPLETED", actual_visit_date=REF, followup_required=False, next_followup_date="2026-11-01")).status_code == 422


def test_create_visit_and_filters(client):
    r = client.post("/api/v1/visits", json=dict(household_id="HH-SYN-00001", scheduled_date="2026-12-01", visit_reason="ROUTINE"))
    assert r.status_code == 201 and r.json()["visit_status"] == "PLANNED" and r.json()["referral_status"] == "NONE"
    assert client.post("/api/v1/visits", json=dict(household_id="NOPE", scheduled_date="2026-12-01")).status_code == 404
    lst = client.get("/api/v1/visits?household_id=HH-SYN-00001&status=PLANNED&date_from=2026-12-01").json()
    assert lst["total"] >= 1 and all(v["visit_status"] == "PLANNED" for v in lst["items"])
    assert client.get("/api/v1/visits?status=BOGUS").status_code == 422
