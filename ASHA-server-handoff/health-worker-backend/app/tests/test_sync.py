import datetime as dt
import re
import uuid

import pytest
from sqlalchemy import func, select

from app.db.models import Household, Referral, SyncOperation, Visit
from app.services.dataset_import.manifest import load
from app.tests.conftest import DATASETS, REF

SCEN = load(DATASETS, "offline_sync_tests")
HH = "HH-SYN-00001"


def op(entity_type, entity_id, op_type, payload, base_version=None, op_id=None, **kw):
    d = dict(op_id=op_id or "op-" + uuid.uuid4().hex[:12], entity_type=entity_type, entity_id=entity_id, op_type=op_type, payload=payload)
    if base_version: d["base_version"] = base_version
    d.update(kw)
    return d


def visit_op(i, tag="T"):
    return op("visit", "VIS-%s-%04d" % (tag, i), "create", dict(household_id=HH, scheduled_date="2026-11-%02d" % (1 + i % 27), visit_reason="ROUTINE"), op_id="op-%s-%04d" % (tag, i))


def push(client, ops, inst="install-AAAA1111"):
    r = client.post("/api/v1/sync/push", json=dict(installation_id=inst, operations=ops))
    assert r.status_code == 200, r.text
    return r.json()


def nvisits(db, prefix):
    db.rollback()
    return db.scalar(select(func.count()).select_from(Visit).where(Visit.visit_id.like(prefix + "%")))


# ---------------------------------------------------------------- core behaviours
def test_push_acknowledges_only_after_commit(client, db):
    out = push(client, [visit_op(1, "A")])
    r = out["results"][0]
    assert r["status"] == "ACKNOWLEDGED" and r["acknowledged"] is True and r["server_version"] == 1 and out["acknowledged_count"] == 1
    assert nvisits(db, "VIS-A-") == 1


def test_repeated_push_is_idempotent(client, db):
    ops = [visit_op(i, "B") for i in range(5)]
    first, second = push(client, ops), push(client, ops)
    assert all(not r["duplicate"] for r in first["results"]) and all(r["duplicate"] and r["acknowledged"] for r in second["results"])
    assert nvisits(db, "VIS-B-") == 5
    db.rollback()
    assert db.scalar(select(func.count()).select_from(SyncOperation).where(SyncOperation.op_id.like("op-B-%"))) == 5


def test_same_idempotency_key_new_op_id_is_duplicate(client, db):
    a = visit_op(1, "C"); a["idempotency_key"] = "idem-key-0001"
    b = visit_op(2, "C"); b["idempotency_key"] = "idem-key-0001"
    out = push(client, [a, b])
    assert out["results"][1]["duplicate"] is True and nvisits(db, "VIS-C-") == 1


def test_malformed_operations_rejected_without_blocking_others(client, db):
    ops = [visit_op(1, "D"), {"op_id": "bad-op-0001", "entity_type": "nonsense"}, "not-an-object", visit_op(2, "D")]
    ops[2] = {"junk": True}
    out = push(client, ops)
    st = [r["status"] for r in out["results"]]
    assert st == ["ACKNOWLEDGED", "REJECTED", "REJECTED", "ACKNOWLEDGED"] and out["results"][1]["error_code"] == "MALFORMED_OPERATION"
    assert all(r["acknowledged"] is False for r in out["results"] if r["status"] == "REJECTED") and nvisits(db, "VIS-D-") == 2


def test_partial_failure_keeps_earlier_ops_and_failed_op_is_not_acknowledged(client, db):
    ops = [visit_op(1, "E"), op("visit", "VIS-E-0002", "create", dict(household_id="HH-NOPE", scheduled_date="2026-11-02"), op_id="op-E-0002"), visit_op(3, "E")]
    out = push(client, ops)
    assert [r["acknowledged"] for r in out["results"]] == [True, False, True] and out["results"][1]["status"] == "REJECTED"
    assert nvisits(db, "VIS-E-") == 2
    retry = push(client, [visit_op(1, "E"), visit_op(2, "E"), visit_op(3, "E")])        # client retries the whole batch (op 2 is now valid)
    assert [r["duplicate"] for r in retry["results"]] == [True, False, True] and all(r["acknowledged"] for r in retry["results"])
    assert nvisits(db, "VIS-E-") == 3


def test_batch_size_limit_enforced(client):
    r = client.post("/api/v1/sync/push", json=dict(installation_id="install-AAAA1111", operations=[visit_op(i, "F") for i in range(201)]))
    assert r.status_code == 422


def test_installation_id_is_hashed_not_stored(client, db):
    push(client, [visit_op(1, "G")], inst="my-secret-device-id")
    db.rollback()
    row = db.scalar(select(SyncOperation).where(SyncOperation.op_id == "op-G-0001"))
    assert "my-secret-device-id" not in row.installation_hash and len(row.installation_hash) == 64


def test_status_and_pull(client):
    push(client, [visit_op(1, "H"), op("visit", "VIS-H-0002", "create", dict(household_id="NOPE", scheduled_date="2026-11-02"), op_id="op-H-0002")], inst="install-HHHH1111")
    s = client.get("/api/v1/sync/status", headers={"X-Installation-Id": "install-HHHH1111"}).json()
    assert s["by_status"] == {"ACKNOWLEDGED": 1, "REJECTED": 1} and s["last_acknowledged_at"] and s["rejected"] == 1
    p = client.get("/api/v1/sync/pull?entity_types=visit&since=%s&limit=50" % (dt.datetime.utcnow() - dt.timedelta(hours=1)).isoformat()).json()
    assert p["visits"] is not None and p["households"] is None and p["referrals"] is None and p["server_time"]     # unrequested types are null
    assert any(v["visit_id"] == "VIS-H-0001" for v in client.get("/api/v1/sync/pull?entity_types=visit&limit=500&since=%s" % (dt.datetime.utcnow() - dt.timedelta(hours=1)).isoformat()).json()["visits"])
    assert client.get("/api/v1/sync/pull?entity_types=bogus").status_code == 422


def test_duplicate_referral_from_two_devices_flagged_not_deleted(client, db):
    v = db.scalar(select(Visit).where(Visit.visit_status == "COMPLETED", Visit.referral_status == "NONE"))
    pay = dict(household_id=v.household_id, visit_id=v.visit_id, facility_id="FAC-SYN-01", service_category="GENERAL")
    a = push(client, [op("referral", "REF-DEV-A001", "create", pay, op_id="op-devA-0001")], inst="device-AAAA1111")
    b = push(client, [op("referral", "REF-DEV-B001", "create", pay, op_id="op-devB-0001")], inst="device-BBBB2222")
    assert a["results"][0]["acknowledged"] and b["results"][0]["acknowledged"] and any("DUPLICATE_FLAGGED" in w for w in b["results"][0]["warnings"])
    db.rollback()
    rows = db.scalars(select(Referral).where(Referral.visit_id == v.visit_id)).all()
    assert sorted(r.record_state for r in rows) == ["ACTIVE", "DUPLICATE"] and {r.referral_id for r in rows} == {"REF-DEV-A001", "REF-DEV-B001"}


def _planned_referral(db):
    return db.scalar(select(Referral).where(Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE", Referral.planned_visit_date <= REF))


def test_stale_update_to_protected_field_is_conflict_and_not_applied(client, db):
    r = _planned_referral(db)
    assert client.patch("/api/v1/referrals/" + r.referral_id, json=dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-SYNC-1", attendance_confirmation_date=REF)).status_code == 200
    out = push(client, [op("referral", r.referral_id, "update", dict(referral_status="PLANNED", planned_visit_date=REF), base_version=1, op_id="op-conf-0001")])
    res = out["results"][0]
    assert res["status"] == "CONFLICT" and res["acknowledged"] is False and res["conflict"]["resolution"] == "NOT_APPLIED_FLAGGED_FOR_REVIEW"
    assert res["conflict"]["server_values"]["referral_status"] == "ATTENDANCE_CONFIRMED" and res["conflict"]["client_values"]["referral_status"] == "PLANNED"
    db.rollback()
    assert db.get(Referral, r.referral_id).referral_status == "ATTENDANCE_CONFIRMED"
    assert db.get(SyncOperation, "op-conf-0001").conflict          # client's intended change is retained for review


def test_stale_update_to_unprotected_field_merges_and_logs_superseded(client, db):
    assert client.patch("/api/v1/households/" + HH, json=dict(village_id="VIL-SYN-09")).status_code == 200
    out = push(client, [op("household", HH, "update", dict(household_member_count=7), base_version=1, op_id="op-merge-001")])
    r = out["results"][0]
    assert r["acknowledged"] and r["conflict"]["resolution"] == "MERGED_UNPROTECTED_FIELDS" and "household_member_count" in r["conflict"]["superseded"]
    h = client.get("/api/v1/households/" + HH).json()
    assert h["household_member_count"] == 7 and h["village_id"] == "VIL-SYN-09"        # both edits survive


def test_update_requires_valid_base_version(client):
    a = push(client, [op("household", HH, "update", dict(household_member_count=3), op_id="op-nobase-01")])["results"][0]
    b = push(client, [op("household", HH, "update", dict(household_member_count=3), base_version=99, op_id="op-ahead-001")])["results"][0]
    assert a["error_code"] == "BASE_VERSION_REQUIRED" and b["error_code"] == "INVALID_BASE_VERSION" and not a["acknowledged"] and not b["acknowledged"]


def test_worker_cannot_confirm_attendance_via_sync(make_client, db):
    c = make_client(auth_mode="api_key", api_keys="worker|WRK-SYN-001|wk1;admin||ad1")
    r = db.scalar(select(Referral).join(Household, Household.household_id == Referral.household_id)
                  .where(Household.assigned_worker_id == "WRK-SYN-001", Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE"))
    out = c.post("/api/v1/sync/push", headers={"X-API-Key": "wk1"}, json=dict(installation_id="install-AAAA1111", operations=[
        op("referral", r.referral_id, "update", dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-X-001", attendance_confirmation_date=REF), base_version=1, op_id="op-wkr-0001")])).json()
    assert out["results"][0]["status"] == "REJECTED" and out["results"][0]["acknowledged"] is False


# ---------------------------------------------------------------- every supplied offline scenario
def _count(s):
    return (s["local_record_changes"][0].get("count") or 0) if s["local_record_changes"] else 0


def run(client, db, s, n):
    d = s["scenario_description"]
    tag = "S%02d" % n
    m = re.search
    if m(r"^App used \d+ hours offline", d) or m(r"^Device restarts while offline", d):
        cnt = _count(s)
        out = push(client, [visit_op(i, tag) for i in range(cnt)])
        assert out["acknowledged_count"] == cnt and nvisits(db, "VIS-%s-" % tag) == s["expected_server_state_after_sync"]["visits_present"]
    elif m(r"^One referral edited \d+ times", d):
        k = s["local_record_changes"][0]["edits"]
        r = _planned_referral(db)
        base = r.version
        ops = [op("referral", r.referral_id, "update", dict(planned_visit_date=(r.planned_visit_date + dt.timedelta(days=0)).isoformat()), base_version=base + i, op_id="op-%s-%03d" % (tag, i)) for i in range(k)]
        out = push(client, ops)
        assert [x["acknowledged"] for x in out["results"]] == [True] * k
        db.rollback()
        assert db.get(Referral, r.referral_id).version == base + k and db.scalar(select(func.count()).select_from(Referral).where(Referral.referral_id == r.referral_id)) == 1
    elif m(r"^Same upload batch sent \d+ times", d):
        t = s["local_record_changes"][0]["upload_attempts"]
        ops = [visit_op(i, tag) for i in range(5)]
        outs = [push(client, ops) for _ in range(t)]
        assert all(x["duplicate"] for o in outs[1:] for x in o["results"]) and nvisits(db, "VIS-%s-" % tag) == s["expected_server_state_after_sync"]["visits_present"]
    elif m(r"^Connection drops after \d+ of \d+", d):
        ch = s["local_record_changes"][0]
        total, j = ch["count"], ch["fail_after"]
        ops = [visit_op(i, tag) for i in range(total)]
        first = push(client, ops[:j])
        assert first["acknowledged_count"] == j and nvisits(db, "VIS-%s-" % tag) == j == s["expected_server_state_after_sync"]["visits_present"]
        retry = push(client, ops)                                                     # client keeps all as pending, retries everything
        assert sum(x["duplicate"] for x in retry["results"]) == j and all(x["acknowledged"] for x in retry["results"]) and nvisits(db, "VIS-%s-" % tag) == total
    elif m(r"^Two devices each create a referral", d):
        v = db.scalar(select(Visit).where(Visit.visit_status == "COMPLETED", Visit.referral_status == "NONE").offset(n))
        pay = dict(household_id=v.household_id, visit_id=v.visit_id, facility_id="FAC-SYN-02", service_category="GENERAL")
        push(client, [op("referral", "REF-%s-A" % tag, "create", pay, op_id="op-%s-A001" % tag)], inst="device-AAAA1111")
        push(client, [op("referral", "REF-%s-B" % tag, "create", pay, op_id="op-%s-B001" % tag)], inst="device-BBBB2222")
        db.rollback()
        st = sorted(r.record_state for r in db.scalars(select(Referral).where(Referral.visit_id == v.visit_id)))
        assert st == ["ACTIVE", "DUPLICATE"]
    elif m(r"^Conflicting update:", d):
        variant = d.split(":", 1)[1].strip()
        if variant.startswith("local PLANNED vs server ATTENDANCE_CONFIRMED"):
            r = db.scalars(select(Referral).where(Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE", Referral.planned_visit_date <= REF).offset(n)).first()
            client.patch("/api/v1/referrals/" + r.referral_id, json=dict(referral_status="ATTENDANCE_CONFIRMED", attendance_record_id="ATT-%s" % tag, attendance_confirmation_date=REF))
            res = push(client, [op("referral", r.referral_id, "update", dict(referral_status="PLANNED", planned_visit_date=REF), base_version=1, op_id="op-%s-0001" % tag)])["results"][0]
            assert res["status"] == "CONFLICT" and res["conflict"]["client_values"]
            db.rollback(); assert db.get(Referral, r.referral_id).referral_status == "ATTENDANCE_CONFIRMED"
        elif variant.startswith("local newer note"):
            hid = "HH-SYN-%05d" % (10 + n)
            client.patch("/api/v1/households/" + hid, json=dict(household_member_count=2))
            res = push(client, [op("household", hid, "update", dict(household_member_count=6), base_version=1, op_id="op-%s-0001" % tag)])["results"][0]
            assert res["acknowledged"] and res["conflict"]["superseded"]["household_member_count"] == 2
        elif variant.startswith("different fields"):
            hid = "HH-SYN-%05d" % (10 + n)
            client.patch("/api/v1/households/" + hid, json=dict(village_id="VIL-SYN-07"))
            res = push(client, [op("household", hid, "update", dict(household_member_count=8), base_version=1, op_id="op-%s-0001" % tag)])["results"][0]
            h = client.get("/api/v1/households/" + hid).json()
            assert res["acknowledged"] and h["household_member_count"] == 8 and h["village_id"] == "VIL-SYN-07"
        else:     # same protected field edited on both sides
            r = db.scalars(select(Referral).where(Referral.referral_status == "PLANNED", Referral.record_state == "ACTIVE").offset(n)).first()
            later = (max(r.planned_visit_date, dt.date.fromisoformat(REF)) + dt.timedelta(days=3)).isoformat()
            assert client.patch("/api/v1/referrals/" + r.referral_id, json=dict(planned_visit_date=later)).status_code == 200
            res = push(client, [op("referral", r.referral_id, "update", dict(planned_visit_date=REF), base_version=1, op_id="op-%s-0001" % tag)])["results"][0]
            assert res["status"] == "CONFLICT" and res["conflict"]["server_values"]["planned_visit_date"] == later and res["conflict"]["client_values"]["planned_visit_date"] == REF
    elif m(r"^Report generated, record changed", d):
        fac = "FAC-SYN-0%d" % (1 + n % 4)
        body = dict(facility_id=fac, period_start="2026-05-01", period_end="2026-10-13", last_sync_at="2026-10-13T08:00:00Z")
        a = client.post("/api/v1/reports/summary", json=body).json()
        r = db.scalars(select(Referral).where(Referral.facility_id == fac, Referral.referral_status == "RECOMMENDED", Referral.record_state == "ACTIVE", Referral.referral_created_date >= dt.date(2026, 5, 1))).first()
        client.patch("/api/v1/referrals/" + r.referral_id, json=dict(referral_status="PLANNED", planned_visit_date=REF))
        b = client.post("/api/v1/reports/summary", json=body).json()
        assert a["report_id"] != b["report_id"] and client.get("/api/v1/reports/" + a["report_id"]).json()["counts"] == a["counts"] and b["counts"]["planned"] == a["counts"]["planned"] + 1
    elif m(r"^Network lost mid-transfer while sharing", d):
        a = client.post("/api/v1/reports/summary", json=dict(facility_id="FAC-SYN-01", period_start="2026-06-01", period_end="2026-10-13")).json()
        assert client.get("/api/v1/reports/%s?format=pdf" % a["report_id"]).status_code == 200       # report survives; re-download possible
        assert client.get("/api/v1/reports/%s?format=csv" % a["report_id"]).status_code == 200
    elif m(r"^Share retried after \d+ failed transfers", d):
        body = dict(facility_id="FAC-SYN-02", period_start="2026-06-01", period_end="2026-10-13")
        ids = {client.post("/api/v1/reports/summary", json=body).json()["report_id"] for _ in range(s["local_record_changes"][0]["failed_attempts"] + 1)}
        assert len(ids) == 1
    elif m(r"^Device offline for \d+ days", d):
        days = s["local_record_changes"][1]["days"]
        created = (dt.datetime(2026, 10, 13, 8) - dt.timedelta(days=days)).isoformat() + "Z"
        out = push(client, [visit_op(i, tag) for i in range(12)] and [dict(visit_op(i, tag), client_created_at=created) for i in range(12)])
        assert out["acknowledged_count"] == 12 and nvisits(db, "VIS-%s-" % tag) == 12
        rep = client.post("/api/v1/reports/summary", json=dict(facility_id="FAC-SYN-01", period_start="2026-06-01", period_end="2026-10-13", last_sync_at=created)).json()
        assert rep["data_freshness_label"] == s["expected_local_state"]["freshness_label"]
    elif m(r"^Device clock is wrong by", d):
        skew = s["local_record_changes"][0]["clock_skew_days"]
        wrong = (dt.datetime(2026, 10, 13, 8) + dt.timedelta(days=skew)).isoformat() + "Z"
        out = push(client, [dict(visit_op(i, tag), client_created_at=wrong, client_updated_at=wrong) for i in range(4)])
        assert out["acknowledged_count"] == 4
        db.rollback()
        row = db.get(SyncOperation, "op-%s-0000" % tag)
        assert row.received_at is not None and row.client_created_at is not None and row.acknowledged_at is not None      # server keeps its own time
    elif m(r"^Connectivity flaps", d):
        w = s["local_record_changes"][0]["flaps"]
        ops = [visit_op(i, tag) for i in range(10)]
        step = max(1, 10 // (w + 1))
        for end in list(range(step, 10, step)) + [10]:
            push(client, ops[:end])                                                      # every reconnect resends everything so far
        assert nvisits(db, "VIS-%s-" % tag) == 10
    else:
        pytest.fail("no executable handler for scenario: " + d)
    assert s["data_loss_expected"] is False


def test_scenario_file_size():
    assert len(SCEN) >= 50


@pytest.mark.parametrize("n", range(len(SCEN)), ids=[s["sync_test_id"] for s in SCEN])
def test_every_offline_sync_scenario(client, db, n):
    run(client, db, SCEN[n], n)
