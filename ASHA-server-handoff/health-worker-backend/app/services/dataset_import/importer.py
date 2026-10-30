"""Reproducible dataset import. Run: python scripts/import_datasets.py

Documented transformations (nothing else is changed; all supplied IDs are preserved):
  * ISO timestamps with offsets (+05:30) are converted to naive UTC datetimes.
  * CSV "true"/"false" -> bool; empty string -> NULL.
  * household.eligible_followup_categories "A|B" -> stored as "|A|B|" (LIKE-filterable); API exposes a list.
  * visits.followup_required empty -> NULL (unknown for PLANNED visits).
  * Facilities are derived from the distinct facility_id values in referral_records.csv.
  * Protocol documents are derived by grouping protocol_passages rows by document_id; values equal to
    "", "unknown", "UNKNOWN" become NULL (never invented).
  * Benchmark/evaluation files go to benchmark_cases (kept apart from production tables).
Rows that fail validation or reference a missing parent are REJECTED and reported, never silently fixed.
"""
import datetime as dt
from typing import Dict, List

from sqlalchemy.orm import Session

from app.db.models import (BenchmarkCase, Facility, Household, ProtocolDocument, ProtocolPassage, Referral, Visit)
from app.domain import (HOUSEHOLD_RECORD_STATUSES, REFERRAL_RECORD_STATES, REFERRAL_STATUSES, SERVICE_CATEGORIES,
                        VISIT_REFERRAL_STATUSES, VISIT_STATUSES)
from app.services.dataset_import.manifest import load
from app.services.protocol_import.importer import content_hash

UNKNOWN = {"", "unknown", "UNKNOWN", None}
BENCH = {"health_questions": "health_questions", "danger_sign_tests": "danger_sign_tests",
         "hospital_report_tests": "hospital_report_tests", "offline_sync_tests": "offline_sync_tests",
         "retrieval_evaluation": "retrieval_evaluation"}
BENCH_ID = {"health_questions": "question_id", "danger_sign_tests": "test_id", "hospital_report_tests": "scenario_id",
            "offline_sync_tests": "sync_test_id", "retrieval_evaluation": "retrieval_test_id"}


def _ts(s):
    if not s:
        return None
    d = dt.datetime.fromisoformat(s)
    if d.tzinfo:
        d = d.astimezone(dt.timezone.utc).replace(tzinfo=None)
    return d


def _date(s):
    return dt.date.fromisoformat(s) if s else None


def _bool(s):
    return {"true": True, "false": False}.get(str(s).lower()) if s not in ("", None) else None


def _none(s):
    return None if s in UNKNOWN else s


def import_datasets(db: Session, dataset_dir: str, include_benchmarks: bool = True) -> Dict:
    report = dict(imported={}, rejected=[], skipped=[])

    def reject(ds, rid, why):
        report["rejected"].append(dict(dataset=ds, id=rid, reason=why))

    rows = {n: load(dataset_dir, n) for n in ("households", "visits", "referrals", "protocol_passages")}
    for n, r in rows.items():
        if r is None:
            report["skipped"].append(n + ": file not found")

    # households
    ok = 0
    for r in rows["households"] or []:
        try:
            if r["record_status"] not in HOUSEHOLD_RECORD_STATUSES:
                raise ValueError("bad record_status")
            cats = [c for c in r["eligible_followup_categories"].split("|") if c]
            db.merge(Household(
                household_id=r["household_id"], village_id=r["village_id"], assigned_worker_id=r["assigned_worker_id"],
                household_member_count=int(r["household_member_count"]),
                eligible_followup_categories="|" + "|".join(cats) + "|",
                last_visit_date=_date(r["last_visit_date"]), next_visit_due_date=_date(r["next_visit_due_date"]),
                scheduled_followup_category=_none(r["scheduled_followup_category"]), record_status=r["record_status"],
                last_updated=_ts(r["last_updated_timestamp"]), synthetic_record=_bool(r["synthetic_record"]) is not False))
            ok += 1
        except Exception as e:  # noqa: BLE001
            reject("households", r.get("household_id"), str(e))
    db.flush()
    report["imported"]["households"] = ok
    hids = {h for (h,) in db.query(Household.household_id)}

    # visits
    ok = 0
    for r in rows["visits"] or []:
        try:
            if r["household_id"] not in hids: raise ValueError("unknown household_id")
            if r["visit_status"] not in VISIT_STATUSES: raise ValueError("bad visit_status")
            if r["referral_status"] not in VISIT_REFERRAL_STATUSES: raise ValueError("bad referral_status")
            db.merge(Visit(
                visit_id=r["visit_id"], household_id=r["household_id"], worker_id=r["worker_id"],
                scheduled_date=_date(r["scheduled_date"]), actual_visit_date=_date(r["actual_visit_date"]),
                visit_status=r["visit_status"], visit_reason=r["visit_reason"], followup_required=_bool(r["followup_required"]),
                next_followup_date=_date(r["next_followup_date"]), referral_status=r["referral_status"],
                referral_id=_none(r["referral_id"]), recorded_at=_ts(r["recorded_timestamp"]),
                updated_at=_ts(r["recorded_timestamp"]), synthetic_record=_bool(r["synthetic_record"]) is not False))
            ok += 1
        except Exception as e:  # noqa: BLE001
            reject("visits", r.get("visit_id"), str(e))
    db.flush()
    report["imported"]["visits"] = ok
    vids = {v for (v,) in db.query(Visit.visit_id)}

    # facilities + referrals
    for fid in sorted({r["facility_id"] for r in rows["referrals"] or []}):
        db.merge(Facility(facility_id=fid, synthetic_record=True))
    db.flush()
    ok = 0
    for r in rows["referrals"] or []:
        try:
            if r["household_id"] not in hids: raise ValueError("unknown household_id")
            if r["visit_id"] not in vids: raise ValueError("unknown visit_id")
            if r["referral_status"] not in REFERRAL_STATUSES: raise ValueError("bad referral_status")
            if r["record_state"] not in REFERRAL_RECORD_STATES: raise ValueError("bad record_state")
            if r["service_category"] not in SERVICE_CATEGORIES: raise ValueError("bad service_category")
            conf = _bool(r["attendance_confirmed"])
            if conf != (r["referral_status"] == "ATTENDANCE_CONFIRMED"): raise ValueError("attendance flag/status mismatch")
            if conf and not r.get("attendance_record_id"): raise ValueError("confirmed without attendance record")
            db.merge(Referral(
                referral_id=r["referral_id"], household_id=r["household_id"], visit_id=r["visit_id"], facility_id=r["facility_id"],
                service_category=r["service_category"], referral_created_date=_date(r["referral_created_date"]),
                planned_visit_date=_date(r["planned_visit_date"]), referral_status=r["referral_status"], attendance_confirmed=conf,
                attendance_confirmation_date=_date(r["attendance_confirmation_date"]),
                attendance_record_id=_none(r.get("attendance_record_id")), record_state=r["record_state"],
                duplicate_of=_none(r.get("duplicate_of")), last_updated=_ts(r["record_last_updated"]),
                synthetic_record=_bool(r["synthetic_record"]) is not False))
            ok += 1
        except Exception as e:  # noqa: BLE001
            reject("referrals", r.get("referral_id"), str(e))
    report["imported"]["referrals"] = ok
    report["imported"]["facilities"] = len({r["facility_id"] for r in rows["referrals"] or []})

    # protocol documents / passages
    docs: Dict[str, dict] = {}
    passages: List[dict] = rows["protocol_passages"] or []
    for p in passages:
        d = docs.setdefault(p["document_id"], dict(title=None, authority=None, version=None, date=None, lang=None, ver="UNKNOWN", appr=False))
        d["title"] = d["title"] or _none(p.get("document_title"))
        d["authority"] = d["authority"] or _none(p.get("issuing_authority"))
        d["version"] = d["version"] or _none(p.get("document_version"))
        d["date"] = d["date"] or _none(p.get("publication_date"))
        d["lang"] = d["lang"] or _none(p.get("language"))
        if p.get("source_verification_status") == "VERIFIED":
            d["ver"] = "VERIFIED"
    for did, d in docs.items():
        db.merge(ProtocolDocument(document_id=did, title=d["title"], issuing_authority=d["authority"], version=d["version"],
                                  publication_date=d["date"], language=d["lang"], source_verification_status=d["ver"],
                                  approved_for_retrieval=d["ver"] == "VERIFIED"))
    db.flush()
    ok = 0
    seen_hash = {(d, h) for d, h in db.query(ProtocolPassage.document_id, ProtocolPassage.content_hash) if h}
    existing_ids = {i for (i,) in db.query(ProtocolPassage.passage_id)}
    for p in passages:
        try:
            if not p.get("passage_text"): raise ValueError("empty passage_text")
            h = content_hash(p["passage_text"])
            if (p["document_id"], h) in seen_hash and p["passage_id"] not in existing_ids:
                report["skipped"].append("protocol_passages %s: duplicate text within %s" % (p["passage_id"], p["document_id"])); continue
            seen_hash.add((p["document_id"], h))
            page = p.get("page_number")
            db.merge(ProtocolPassage(
                passage_id=p["passage_id"], document_id=p["document_id"], section_id=_none(p.get("section_id")),
                section_title=_none(p.get("section_title")), page_number=int(page) if page not in UNKNOWN else None,
                passage_text=p["passage_text"], language=_none(p.get("language")),
                approved_for_retrieval=bool(p.get("approved_for_retrieval")),
                source_verification_status=p.get("source_verification_status") or "UNKNOWN", content_hash=h))
            ok += 1
        except Exception as e:  # noqa: BLE001
            reject("protocol_passages", p.get("passage_id"), str(e))
    report["imported"]["protocol_passages"] = ok

    if include_benchmarks:
        for ds, idk in BENCH_ID.items():
            data = load(dataset_dir, ds)
            if data is None:
                report["skipped"].append(ds + ": file not found"); continue
            for r in data:
                existing = db.query(BenchmarkCase).filter_by(dataset=ds, case_id=r[idk]).one_or_none()
                if existing: existing.payload = r
                else: db.add(BenchmarkCase(dataset=ds, case_id=r[idk], payload=r))
            report["imported"]["benchmark:" + ds] = len(data)
    db.commit()
    return report
