import datetime as dt
import uuid

from sqlalchemy import select

from app.db.models import Visit
from app.tests.conftest import REF

DAY = (dt.date.fromisoformat(REF) - dt.timedelta(days=1)).isoformat()  # the day before the synthetic 'today'

HH = "HH-SYN-00001"


def _op(entity_id, op_type, payload, base_version=None):
    d = dict(op_id="op-" + uuid.uuid4().hex[:12], entity_type="visit", entity_id=entity_id, op_type=op_type, payload=payload)
    if base_version:
        d["base_version"] = base_version
    return d


def _push(client, ops):
    r = client.post("/api/v1/sync/push", json=dict(installation_id="install-TIME1111", operations=ops))
    assert r.status_code == 200, r.text
    return r.json()["results"]


def _planned(client, vid):
    r = client.post("/api/v1/visits", json=dict(visit_id=vid, household_id=HH, scheduled_date="2026-10-10", visit_reason="ROUTINE"))
    assert r.status_code == 201, r.text
    return r.json()


def _complete(client, vid, extra=None, version=1):
    body = dict(visit_status="COMPLETED", actual_visit_date=DAY, followup_required=False, version=version)
    body.update(extra or {})
    return client.patch("/api/v1/visits/" + vid, json=body)


def test_completed_visit_stores_and_returns_the_time(client):
    _planned(client, "VIS-TIME-0001")
    r = _complete(client, "VIS-TIME-0001", dict(actual_visit_time="08:45"))
    assert r.status_code == 200, r.text
    assert r.json()["actual_visit_time"].startswith("08:45")
    got = client.get("/api/v1/visits?household_id=%s&limit=200" % HH).json()
    got = got["items"] if isinstance(got, dict) else got
    assert any(v["visit_id"] == "VIS-TIME-0001" and v["actual_visit_time"].startswith("08:45") for v in got)


def test_time_is_optional_so_older_apps_keep_working(client):
    _planned(client, "VIS-TIME-0002")
    r = _complete(client, "VIS-TIME-0002")
    assert r.status_code == 200 and r.json()["actual_visit_time"] is None


def test_time_is_refused_unless_the_visit_is_completed(client):
    r = client.post("/api/v1/visits", json=dict(visit_id="VIS-TIME-0003", household_id=HH, scheduled_date="2026-10-10", visit_reason="ROUTINE", actual_visit_time="08:45"))
    assert r.status_code == 422 and r.json()["error"]["code"] == "ACTUAL_TIME_NOT_ALLOWED"
    _planned(client, "VIS-TIME-0004")
    r = client.patch("/api/v1/visits/VIS-TIME-0004", json=dict(visit_status="MISSED", actual_visit_time="08:45", followup_required=True, next_followup_date="2026-11-01", version=1))
    assert r.status_code == 422 and r.json()["error"]["code"] == "ACTUAL_TIME_NOT_ALLOWED"


def test_malformed_time_is_rejected(client):
    _planned(client, "VIS-TIME-0005")
    assert _complete(client, "VIS-TIME-0005", dict(actual_visit_time="25:99")).status_code == 422


def test_sync_round_trip_create_update_and_pull(client, db):
    res = _push(client, [_op("VIS-TIME-0006", "create", dict(household_id=HH, scheduled_date="2026-10-10", visit_reason="ROUTINE"))])
    assert res[0]["status"] == "ACKNOWLEDGED", res
    res = _push(client, [_op("VIS-TIME-0006", "update", dict(
        visit_status="COMPLETED", actual_visit_date=DAY, actual_visit_time="11:27",
        followup_required=False, create_followup_task=False), base_version=1)])
    assert res[0]["status"] == "ACKNOWLEDGED", res
    db.rollback()
    v = db.scalar(select(Visit).where(Visit.visit_id == "VIS-TIME-0006"))
    assert v.actual_visit_time == dt.time(11, 27)
    pulled = client.get("/api/v1/sync/pull?entity_types=visit&limit=500&since=2000-01-01T00:00:00").json()["visits"]
    pulled += client.get("/api/v1/visits?household_id=%s&limit=200" % HH).json()["items"]
    mine = [x for x in pulled if x["visit_id"] == "VIS-TIME-0006"]
    assert mine and mine[0]["actual_visit_time"].startswith("11:27")


def test_stale_client_touching_the_time_is_flagged_not_silently_applied(client, db):
    _planned(client, "VIS-TIME-0007")
    assert _complete(client, "VIS-TIME-0007", dict(actual_visit_time="08:00")).status_code == 200      # server moves to version 2
    res = _push(client, [_op("VIS-TIME-0007", "update", dict(actual_visit_time="09:30"), base_version=1)])
    assert res[0]["status"] == "CONFLICT", res        # a protected field changed on the server since the phone last synced: flagged for review
    assert res[0]["conflict"]["fields"] == ["actual_visit_time"]
    db.rollback()
    assert db.scalar(select(Visit.actual_visit_time).where(Visit.visit_id == "VIS-TIME-0007")) == dt.time(8, 0)   # server value kept
