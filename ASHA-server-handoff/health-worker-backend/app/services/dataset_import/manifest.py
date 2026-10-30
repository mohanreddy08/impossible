"""Phase 1: inspect the supplied dataset files and report what is actually there."""
import csv
import datetime as dt
import json
import os
import re
from collections import Counter

EXPECTED = {
    "health_questions": ("health_questions_200.jsonl", "question_id"),
    "danger_sign_tests": ("danger_sign_tests.jsonl", "test_id"),
    "protocol_passages": ("protocol_passages.jsonl", "passage_id"),
    "households": ("household_register_500.csv", "household_id"),
    "visits": ("visit_history.csv", "visit_id"),
    "referrals": ("referral_records.csv", "referral_id"),
    "hospital_report_tests": ("hospital_report_tests.jsonl", "scenario_id"),
    "offline_sync_tests": ("offline_sync_tests.jsonl", "sync_test_id"),
    "retrieval_evaluation": ("retrieval_evaluation.jsonl", "retrieval_test_id"),
}
SOURCE_VALIDATION_REPORT = "dataset_validation_report.json"


def read_jsonl(path):
    with open(path, encoding="utf-8") as f:
        return [json.loads(line) for line in f if line.strip()]


def read_csv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def load(dataset_dir, name):
    fn = EXPECTED[name][0]
    path = os.path.join(dataset_dir, fn)
    if not os.path.exists(path):
        return None
    return read_jsonl(path) if fn.endswith(".jsonl") else read_csv(path)


def _type(v):
    if v is None or v == "":
        return "null"
    if isinstance(v, bool):
        return "bool"
    if isinstance(v, int):
        return "int"
    if isinstance(v, float):
        return "float"
    if isinstance(v, list):
        return "list"
    if isinstance(v, dict):
        return "object"
    if isinstance(v, str):
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
            return "date_str"
        if re.fullmatch(r"\d{4}-\d{2}-\d{2}T[\d:]+([+-]\d\d:\d\d|Z)?", v):
            return "datetime_str"
        if v in ("true", "false"):
            return "bool_str"
        return "str"
    return type(v).__name__


def profile(rows, id_key):
    fields = {}
    for r in rows:
        for k, v in r.items():
            fields.setdefault(k, Counter())[_type(v)] += 1
    out = {}
    for k, c in fields.items():
        nulls = c.get("null", 0)
        out[k] = dict(types={t: n for t, n in c.items() if t != "null"}, missing=nulls,
                      required=nulls == 0)
    ids = [r.get(id_key) for r in rows]
    dups = sorted(k for k, n in Counter(ids).items() if n > 1)
    return dict(record_count=len(rows), fields=out, id_field=id_key,
                duplicate_ids=dups[:20], duplicate_id_count=len(dups),
                missing_id_count=sum(1 for i in ids if i in (None, "")))


def _valid_date(s):
    try:
        dt.date.fromisoformat(s)
        return True
    except (TypeError, ValueError):
        return False


def build_manifest(dataset_dir):
    data, files = {}, {}
    for name, (fn, idk) in EXPECTED.items():
        rows = load(dataset_dir, name)
        files[name] = dict(file=fn, exists=rows is not None)
        if rows is not None:
            data[name] = rows
            files[name].update(profile(rows, idk))
    issues = []

    def add(severity, dataset, msg, count=1):
        issues.append(dict(severity=severity, dataset=dataset, message=msg, count=count))

    for name, info in files.items():
        if not info["exists"]:
            add("ERROR", name, "file missing")
        elif info["record_count"] == 0:
            add("BLOCKER", name, "file exists but contains 0 records")
        if info.get("duplicate_id_count"):
            add("ERROR", name, "duplicate IDs", info["duplicate_id_count"])
        if info.get("missing_id_count"):
            add("ERROR", name, "records without ID", info["missing_id_count"])

    H, V, R = data.get("households", []), data.get("visits", []), data.get("referrals", [])
    hid = {h["household_id"] for h in H}
    vid = {v["visit_id"] for v in V}
    rid = {r["referral_id"] for r in R}
    fk = Counter()
    fk["visits.household_id->households"] = sum(v["household_id"] not in hid for v in V)
    fk["referrals.household_id->households"] = sum(r["household_id"] not in hid for r in R)
    fk["referrals.visit_id->visits"] = sum(r["visit_id"] not in vid for r in R)
    fk["visits.referral_id->referrals"] = sum(bool(v["referral_id"]) and v["referral_id"] not in rid for v in V)
    for g in data.get("hospital_report_tests", []):
        fk["hospital_report_tests.input_referral_ids->referrals"] += sum(i not in rid for i in g["input_referral_ids"])
    qid = {q["question_id"] for q in data.get("health_questions", [])}
    pid = {p["passage_id"] for p in data.get("protocol_passages", [])}
    for t in data.get("retrieval_evaluation", []):
        fk["retrieval_evaluation.question_id->health_questions"] += t.get("question_id") not in qid
        fk["retrieval_evaluation.expected_passage_ids->protocol_passages"] += sum(p not in pid for p in t.get("expected_passage_ids", []))
    for k, n in fk.items():
        if n:
            add("ERROR", "cross-dataset", "foreign key failures: " + k, n)

    bad_dates = Counter()
    for ds, cols in (("households", ["last_visit_date", "next_visit_due_date"]),
                     ("visits", ["scheduled_date", "actual_visit_date", "next_followup_date"]),
                     ("referrals", ["referral_created_date", "planned_visit_date", "attendance_confirmation_date"])):
        for r in data.get(ds, []):
            for c in cols:
                if r.get(c) and not _valid_date(r[c]):
                    bad_dates[ds + "." + c] += 1
    for k, n in bad_dates.items():
        add("ERROR", k.split(".")[0], "invalid date values in " + k, n)

    stat = Counter()
    for v in V:
        if v["visit_status"] == "COMPLETED" and not v["actual_visit_date"]: stat["visit COMPLETED without actual date"] += 1
        if v["visit_status"] != "COMPLETED" and v["actual_visit_date"]: stat["visit actual date on non-COMPLETED"] += 1
        if v["visit_status"] not in ("PLANNED", "COMPLETED", "MISSED", "RESCHEDULED", "CANCELLED"): stat["invalid visit status"] += 1
        if v["referral_status"] not in ("NONE", "RECOMMENDED", "PLANNED", "ATTENDANCE_CONFIRMED"): stat["invalid visit referral_status"] += 1
    for r in R:
        conf = r["attendance_confirmed"] == "true"
        if conf != (r["referral_status"] == "ATTENDANCE_CONFIRMED"): stat["attendance flag/status mismatch"] += 1
        if conf and not r.get("attendance_record_id"): stat["ATTENDANCE_CONFIRMED without attendance record"] += 1
        if r["referral_status"] not in ("RECOMMENDED", "PLANNED", "ATTENDANCE_CONFIRMED"): stat["invalid referral status"] += 1
    for k, n in stat.items():
        add("ERROR", "status", k, n)

    Q = data.get("health_questions", [])
    unverified = sum(1 for q in Q if q.get("source_verification_status") != "VERIFIED")
    no_answer = sum(1 for q in Q if not q.get("expected_answer"))
    no_cite = sum(1 for q in Q if not q.get("expected_document_id"))
    if Q:
        add("BLOCKER", "health_questions", "expected answers/citations are unverified or absent (questions are usable as inputs only)", unverified)
    S = data.get("danger_sign_tests", [])
    unmapped = sum(1 for s in S if not s.get("expected_rule_id"))
    if S and unmapped:
        add("WARNING", "danger_sign_tests", "expected_rule_id is null: no approved clinical ruleset supplied; status labels are preliminary", unmapped)
    if not data.get("protocol_passages"):
        add("BLOCKER", "protocol_passages", "no protocol source passages supplied: retrieval cannot return real evidence and Recall/citation metrics cannot be computed")

    src_report = os.path.join(dataset_dir, SOURCE_VALIDATION_REPORT)
    return dict(
        generated_at=dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
        dataset_dir=os.path.abspath(dataset_dir),
        synthetic_data_declaration="Household, visit, referral and test records are synthetic. Clinical answer content is unapproved.",
        files=files,
        source_validation_report_present=os.path.exists(src_report),
        questions=dict(total=len(Q), unverified=unverified, missing_expected_answer=no_answer, missing_expected_citation=no_cite),
        cross_dataset_fk_failures=dict(fk),
        issues=issues,
        counts={n: i.get("record_count") for n, i in files.items()},
    )
