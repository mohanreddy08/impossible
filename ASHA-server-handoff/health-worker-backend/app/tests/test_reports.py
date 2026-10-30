import datetime as dt
import json

import pytest
from sqlalchemy import select

from app.core.security import Principal
from app.db.models import Referral
from app.services.dataset_import.manifest import load
from app.services.reports import export, service
from app.tests.conftest import DATASETS

SCEN = load(DATASETS, "hospital_report_tests")
ADMIN = Principal("admin", None, "t")


def _utc(s):
    return dt.datetime.fromisoformat(s).astimezone(dt.timezone.utc).replace(tzinfo=None)


def _build(db, settings, s, override=None):
    a, b = s["reporting_period"].split("/")
    return service.build_summary(db, ADMIN, settings, facility_id=s["selected_facility_id"], period_start=dt.date.fromisoformat(a), period_end=dt.date.fromisoformat(b),
                                 referral_ids=s["input_referral_ids"], last_sync_at=_utc(s["device_last_sync_at"]), generated_at=_utc(s["report_generated_at"]), status_override=override)


def test_scenario_file_covers_required_cases():
    assert len(SCEN) >= 50
    assert {s["scenario_type"] for s in SCEN} >= {"NO_REFERRALS", "ONLY_RECOMMENDED", "ONLY_PLANNED", "CONFIRMED_ATTENDANCE", "MIXED_STATUSES", "DUPLICATE_RECORDS",
                                                  "CANCELLED_OR_INVALID", "OUTSIDE_PERIOD", "STALE_OFFLINE", "CHANGED_AFTER_REPORT", "REPEATED_SHARING"}


@pytest.mark.parametrize("s", SCEN, ids=[s["scenario_id"] for s in SCEN])
def test_every_hospital_report_scenario(db, settings, s):
    r = _build(db, settings, s)
    c = r["counts"]
    assert (c["recommended"], c["planned"], c["attendance_confirmed"]) == (s["expected_recommended_count"], s["expected_planned_count"], s["expected_attendance_confirmed_count"])
    assert r["counts_by_service_category"] == s["expected_counts_by_service_category"]
    assert c["total_included"] == s["expected_total_included"] == sum(r["counts_by_service_category"].values())
    assert r["excluded_counts"] == s["expected_excluded_counts"]
    assert r["data_freshness_label"] == s["expected_data_freshness_label"]
    blob = json.dumps(r)
    assert "HH-SYN" not in blob and "REF-SYN" not in blob and "aggregate" in r["privacy_notice"].lower()      # privacy: aggregates only
    if "post_report_change" in s:
        ch = s["post_report_change"]
        r2 = _build(db, settings, s, override={ch["referral_id"]: ch["new_status"]})
        e = s["expected_counts_after_change"]
        assert (r2["counts"]["recommended"], r2["counts"]["planned"], r2["counts"]["attendance_confirmed"]) == (e["recommended"], e["planned"], e["attendance_confirmed"])
        assert r2["content_hash"] != r["content_hash"] or r2["counts"] == r["counts"]


def test_recorded_counts_not_predictions(db, settings):
    r = _build(db, settings, SCEN[10])
    assert "predicted" in r["privacy_notice"].lower()
    assert not any("probab" in k or "predict" in k for k in r)


def test_duplicates_cancelled_invalid_are_excluded(db, settings):
    dup = next(s for s in SCEN if s["scenario_type"] == "DUPLICATE_RECORDS")
    r = _build(db, settings, dup)
    assert r["excluded_counts"].get("duplicate", 0) >= 1
    bad = next(s for s in SCEN if s["scenario_type"] == "CANCELLED_OR_INVALID")
    assert set(_build(db, settings, bad)["excluded_counts"]) & {"cancelled", "invalid"}


def test_unknown_referral_ids_rejected(db, settings):
    with pytest.raises(Exception) as e:
        service.build_summary(db, ADMIN, settings, facility_id="FAC-SYN-01", period_start=dt.date(2026, 1, 1), period_end=dt.date(2026, 12, 31), referral_ids=["REF-NOPE"])
    assert "UNKNOWN_REFERRAL" in getattr(e.value, "code", "")


def test_planned_and_recommended_are_not_attendance(db, settings):
    refs = db.scalars(select(Referral).where(Referral.referral_status.in_(["RECOMMENDED", "PLANNED"]), Referral.record_state == "ACTIVE")).all()
    agg = service.aggregate(refs, refs[0].facility_id, dt.date(2000, 1, 1), dt.date(2100, 1, 1))
    assert agg["status"]["ATTENDANCE_CONFIRMED"] == 0


# ------------- API: summary / idempotency / exports -------------
def _body(**kw):
    b = dict(facility_id="FAC-SYN-01", period_start="2026-06-01", period_end="2026-10-13", last_sync_at="2026-10-13T08:00:00Z")
    b.update(kw)
    return b


def test_summary_endpoint_idempotent_and_versioned(client, db):
    a = client.post("/api/v1/reports/summary", json=_body()).json()
    again = client.post("/api/v1/reports/summary", json=_body()).json()
    assert a["duplicate_of_existing"] is False and again["duplicate_of_existing"] is True and a["report_id"] == again["report_id"]
    ref = db.scalar(select(Referral).where(Referral.facility_id == "FAC-SYN-01", Referral.referral_status == "RECOMMENDED", Referral.record_state == "ACTIVE",
                                           Referral.referral_created_date >= dt.date(2026, 6, 1)))
    assert client.patch("/api/v1/referrals/" + ref.referral_id, json=dict(referral_status="PLANNED", planned_visit_date="2026-10-13")).status_code == 200
    b = client.post("/api/v1/reports/summary", json=_body()).json()
    assert b["report_id"] != a["report_id"] and b["counts"]["planned"] == a["counts"]["planned"] + 1 and b["counts"]["recommended"] == a["counts"]["recommended"] - 1
    old = client.get("/api/v1/reports/" + a["report_id"]).json()
    assert old["counts"] == a["counts"] and old["superseded_by"] == b["report_id"]       # earlier report unchanged, marked superseded


def test_report_contains_required_fields(client):
    r = client.post("/api/v1/reports/summary", json=_body(last_sync_at="2026-10-01T08:00:00Z")).json()
    for k in ("facility_id", "period_start", "period_end", "generated_at", "data_freshness_label", "last_sync_at", "counts", "counts_by_service_category", "privacy_notice", "follow_ups"):
        assert k in r
    assert r["data_freshness_label"] == "STALE_OFFLINE" and r["facility_id"] == "FAC-SYN-01"


def test_csv_and_pdf_exports(client):
    rid = client.post("/api/v1/reports/summary", json=_body()).json()["report_id"]
    csv = client.get("/api/v1/reports/%s?format=csv" % rid)
    assert csv.status_code == 200 and csv.headers["content-type"].startswith("text/csv")
    text = csv.text
    for k in ("facility_id", "period_start", "generated_at", "data_freshness_label", "count_recommended", "count_planned", "count_attendance_confirmed", "privacy_notice"):
        assert k in text
    pdf = client.get("/api/v1/reports/%s?format=pdf" % rid)
    assert pdf.status_code == 200 and pdf.content[:5] == b"%PDF-" and len(pdf.content) > 1000
    assert client.get("/api/v1/reports/%s?format=xml" % rid).status_code == 422
    assert client.get("/api/v1/reports/RPT-NOPE").status_code == 404


def test_exports_are_pure_functions_usable_offline(db, settings):
    r = service.build_summary(db, ADMIN, settings, facility_id="FAC-SYN-03", period_start=dt.date(2026, 1, 1), period_end=dt.date(2026, 10, 13))
    r["report_id"] = "LOCAL"
    assert export.to_pdf(r)[:4] == b"%PDF" and b"FAC-SYN-03" in export.to_csv(r)


def test_bad_period_rejected(client):
    assert client.post("/api/v1/reports/summary", json=_body(period_start="2026-10-13", period_end="2026-01-01")).status_code == 422
