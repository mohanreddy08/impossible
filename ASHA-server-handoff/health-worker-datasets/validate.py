#!/usr/bin/env python3
"""Independent validation of the synthetic datasets -> dataset_validation_report.json.
Reads only the files on disk; recomputes aggregates itself. Errors are reported, never auto-fixed."""
import csv, json, os, re, datetime as dt
from collections import Counter

D = os.path.dirname(os.path.abspath(__file__))
REF = "2026-10-13"


def jl(n):
    with open(os.path.join(D, n), encoding="utf-8") as f:
        return [json.loads(l) for l in f if l.strip()]


def cs(n):
    with open(os.path.join(D, n), encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


Q, S = jl("health_questions_200.jsonl"), jl("danger_sign_tests.jsonl")
P, RT = jl("protocol_passages.jsonl"), jl("retrieval_evaluation.jsonl")
H, V, R = cs("household_register_500.csv"), cs("visit_history.csv"), cs("referral_records.csv")
G, Y = jl("hospital_report_tests.jsonl"), jl("offline_sync_tests.jsonl")

checks, errors = [], []


def check(name, bad, detail=""):
    ok = not bad
    checks.append(dict(check=name, status="PASS" if ok else "FAIL", violations=len(bad), detail=detail))
    for b in bad[:10]:
        errors.append("%s: %s" % (name, b))


def dup_ids(rows, key):
    c = Counter(r[key] for r in rows)
    return [k for k, v in c.items() if v > 1]


for nm, rows, key in [("Q", Q, "question_id"), ("S", S, "test_id"), ("H", H, "household_id"), ("V", V, "visit_id"),
                      ("R", R, "referral_id"), ("G", G, "scenario_id"), ("Y", Y, "sync_test_id")]:
    check("unique_ids_" + nm, dup_ids(rows, key))

hids, vids, rids = {h["household_id"] for h in H}, {v["visit_id"] for v in V}, {r["referral_id"] for r in R}
vmap, rmap = {v["visit_id"]: v for v in V}, {r["referral_id"]: r for r in R}
check("fk_visit_household", [v["visit_id"] for v in V if v["household_id"] not in hids])
check("fk_referral_household", [r["referral_id"] for r in R if r["household_id"] not in hids])
check("fk_referral_visit", [r["referral_id"] for r in R if r["visit_id"] not in vids])
check("fk_visit_referral", [v["visit_id"] for v in V if v["referral_id"] and v["referral_id"] not in rids])
check("fk_hospital_test_referrals", [g["scenario_id"] for g in G for i in g["input_referral_ids"] if i not in rids])
check("referral_household_matches_visit", [r["referral_id"] for r in R if vmap[r["visit_id"]]["household_id"] != r["household_id"]])

# visit date logic
bad = []
for v in V:
    s, a, nf = v["scheduled_date"], v["actual_visit_date"], v["next_followup_date"]
    if v["visit_status"] == "COMPLETED" and not a: bad.append((v["visit_id"], "completed w/o actual date"))
    if v["visit_status"] != "COMPLETED" and a: bad.append((v["visit_id"], "actual date on non-completed"))
    if a and a < s: bad.append((v["visit_id"], "actual before scheduled"))
    if a and a > REF: bad.append((v["visit_id"], "actual in future"))
    if nf and nf <= (a or s): bad.append((v["visit_id"], "next_followup not after visit"))
    if v["followup_required"] == "true" and not nf: bad.append((v["visit_id"], "followup true without date"))
    if v["followup_required"] == "false" and nf: bad.append((v["visit_id"], "followup false with date"))
    if v["recorded_timestamp"][:10] > REF: bad.append((v["visit_id"], "recorded in future"))
    if v["visit_status"] not in ("PLANNED", "COMPLETED", "MISSED", "RESCHEDULED", "CANCELLED"): bad.append((v["visit_id"], "bad status"))
check("visit_date_consistency", bad)

# household register vs visit history
vh = {}
for v in V: vh.setdefault(v["household_id"], []).append(v)
bad = []
for h in H:
    vs = vh.get(h["household_id"], [])
    comp = [v["actual_visit_date"] for v in vs if v["visit_status"] == "COMPLETED"]
    plan = [v["scheduled_date"] for v in vs if v["visit_status"] == "PLANNED"]
    if (max(comp) if comp else "") != h["last_visit_date"]: bad.append((h["household_id"], "last_visit mismatch"))
    if (min(plan) if plan else "") != h["next_visit_due_date"]: bad.append((h["household_id"], "next_due mismatch"))
    st, nd = h["record_status"], h["next_visit_due_date"]
    if st == "DUE_TODAY" and nd != REF: bad.append((h["household_id"], "due today wrong"))
    if st == "OVERDUE" and not (nd and nd < REF): bad.append((h["household_id"], "overdue wrong"))
    if st == "UPCOMING" and not (nd and nd > REF): bad.append((h["household_id"], "upcoming wrong"))
    if st in ("COMPLETED", "NO_VISIT_DUE") and nd: bad.append((h["household_id"], "next due on non-scheduled"))
    sc = h["scheduled_followup_category"]
    if sc and sc not in h["eligible_followup_categories"].split("|"): bad.append((h["household_id"], "scheduled cat not eligible"))
check("household_register_matches_visits", bad)

# referral status vs attendance
bad = []
for r in R:
    st, conf = r["referral_status"], r["attendance_confirmed"] == "true"
    if conf != (st == "ATTENDANCE_CONFIRMED"): bad.append((r["referral_id"], "flag/status mismatch"))
    if st == "ATTENDANCE_CONFIRMED" and not (r["attendance_confirmation_date"] and r["attendance_record_id"]): bad.append((r["referral_id"], "confirmed w/o attendance record"))
    if st != "ATTENDANCE_CONFIRMED" and (r["attendance_confirmation_date"] or r["attendance_record_id"]): bad.append((r["referral_id"], "attendance data without confirmation"))
    if st == "RECOMMENDED" and r["planned_visit_date"]: bad.append((r["referral_id"], "recommended with planned date"))
    if st in ("PLANNED", "ATTENDANCE_CONFIRMED") and r["planned_visit_date"] <= r["referral_created_date"]: bad.append((r["referral_id"], "planned not after created"))
    if r["attendance_confirmation_date"] and not (r["planned_visit_date"] <= r["attendance_confirmation_date"] <= REF): bad.append((r["referral_id"], "confirmation date order"))
    if r["record_state"] == "ACTIVE":
        v = vmap[r["visit_id"]]
        if v["referral_id"] != r["referral_id"] or v["referral_status"] != st: bad.append((r["referral_id"], "visit mirror mismatch"))
        if v["visit_status"] != "COMPLETED": bad.append((r["referral_id"], "referral on non-completed visit"))
    if r["record_state"] == "DUPLICATE" and r["duplicate_of"] not in rids: bad.append((r["referral_id"], "dangling duplicate_of"))
    if r["record_last_updated"][:10] > REF: bad.append((r["referral_id"], "updated in future"))
check("referral_status_vs_attendance_and_visit", bad)
check("confirmed_only_with_attendance_record", [v["visit_id"] for v in V if v["referral_status"] == "ATTENDANCE_CONFIRMED" and rmap[v["referral_id"]]["attendance_record_id"] == ""])

# hospital report recompute (independent implementation)
bad = []
for g in G:
    s, e = g["reporting_period"].split("/")
    seen, c, cat = set(), Counter(), Counter()
    for i in g["input_referral_ids"]:
        if i in seen: continue
        seen.add(i)
        r = rmap[i]
        if r["facility_id"] != g["selected_facility_id"] or not (s <= r["referral_created_date"] <= e) or r["record_state"] != "ACTIVE": continue
        c[r["referral_status"]] += 1; cat[r["service_category"]] += 1
    exp = (g["expected_recommended_count"], g["expected_planned_count"], g["expected_attendance_confirmed_count"])
    if exp != (c["RECOMMENDED"], c["PLANNED"], c["ATTENDANCE_CONFIRMED"]): bad.append((g["scenario_id"], "status counts"))
    if g["expected_counts_by_service_category"] != dict(sorted(cat.items())): bad.append((g["scenario_id"], "category counts"))
    if sum(g["expected_counts_by_service_category"].values()) != sum(exp): bad.append((g["scenario_id"], "category sum != status sum"))
    if "no_arrival_probability_or_prediction" not in g["expected_privacy_checks"]: bad.append((g["scenario_id"], "privacy check missing"))
check("hospital_report_counts_match_referrals", bad, "recomputed independently from referral_records.csv")
check("hospital_report_scenario_coverage", [t for t in ["NO_REFERRALS", "ONLY_RECOMMENDED", "ONLY_PLANNED", "CONFIRMED_ATTENDANCE", "MIXED_STATUSES", "DUPLICATE_RECORDS",
                                                    "CANCELLED_OR_INVALID", "OUTSIDE_PERIOD", "STALE_OFFLINE", "CHANGED_AFTER_REPORT", "REPEATED_SHARING"]
                                                    if t not in {g["scenario_type"] for g in G}])

# sync tests
check("sync_no_data_loss_expected", [y["sync_test_id"] for y in Y if y["data_loss_expected"]])
check("sync_required_fields", [y["sync_test_id"] for y in Y if any(k not in y for k in ["pending_upload_count", "expected_sync_status", "expected_local_state", "expected_server_state_after_sync"])])

# language labels
TE = re.compile("[ఀ-౿]"); LAT = re.compile("[A-Za-z]")
def lang_ok(t, lt):
    te, la = len(TE.findall(t)), len(LAT.findall(t))
    if lt == "telugu": return te > 0 and te >= la
    if lt == "english": return te == 0 and la > 0
    if lt == "code_mixed": return te > 0 and re.search("[A-Za-z]{2,}", t) is not None
    if lt == "telugu_transliterated": return te == 0 and la > 0
    return False
check("language_labels_match_script_Q", [q["question_id"] for q in Q if not lang_ok(q["question_text"], q["language_type"])],
      "script check only; Telugu transliteration plausibility needs a human reader")
check("language_labels_match_script_S", [s["test_id"] for s in S if not lang_ok(s["input_text"], s["language_type"])])
lc = Counter(q["language_type"] for q in Q)
check("question_language_distribution", [] if lc == {"telugu": 70, "english": 60, "code_mixed": 50, "telugu_transliterated": 20} else [dict(lc)])
check("question_text_unique", dup_ids([{"t": q["question_text"]} for q in Q], "t"))
check("safety_dev_final_text_disjoint", [t for t in {s["input_text"] for s in S if s["split"] == "RULE_DEVELOPMENT"} & {s["input_text"] for s in S if s["split"] == "FINAL_EVALUATION"}])

# citation integrity: no fabricated sources anywhere
check("no_fabricated_citations_Q", [q["question_id"] for q in Q if q["expected_document_id"] or q["expected_page"] or q["expected_evidence_text"] or q["expected_answer"]])
check("no_invented_rule_ids_S", [s["test_id"] for s in S if s["expected_rule_id"]])

# synthetic label + PII
check("synthetic_label_all_records", [r.get("synthetic_record") for rows in (Q, S, G, Y) for r in rows if r.get("synthetic_record") is not True]
      + [x["household_id"] for x in H if x["synthetic_record"] != "true"] + [x["visit_id"] for x in V if x["synthetic_record"] != "true"]
      + [x["referral_id"] for x in R if x["synthetic_record"] != "true"])
pii = [re.compile(p) for p in (r"\b\d{10}\b", r"\b\d{12}\b", r"[\w.]+@[\w.]+\.\w+", r"https?://")]
hits = []
for n in ["household_register_500.csv", "visit_history.csv", "referral_records.csv", "hospital_report_tests.jsonl", "offline_sync_tests.jsonl"]:
    txt = open(os.path.join(D, n), encoding="utf-8").read()
    hits += [(n, p.pattern) for p in pii if p.search(txt)]
check("no_pii_patterns_in_structured_files", hits, "phone/Aadhaar-like numbers, e-mails, URLs")

counts = dict(health_questions=len(Q), danger_sign_tests=len(S), protocol_passages=len(P), households=len(H), visits=len(V),
              referrals=len(R), hospital_report_tests=len(G), offline_sync_tests=len(Y), retrieval_evaluation=len(RT))
check("record_counts_meet_requirements", [k for k, ok in {
    "questions==200": len(Q) == 200, "safety>=100": len(S) >= 100, "households==500": len(H) == 500, "visits>=1500": len(V) >= 1500,
    "referrals>=200": len(R) >= 200, "hospital>=50": len(G) >= 50, "sync>=50": len(Y) >= 50}.items() if not ok])

blocked = [
    "protocol_passages.jsonl: 0 records. No official protocol corpus was supplied; passages, versions, authorities and page numbers were not invented.",
    "retrieval_evaluation.jsonl: 0 records. Labels require real passage IDs (depends on protocol_passages.jsonl).",
    "health_questions_200.jsonl: expected_answer/document/section/page/evidence are null; every row is REQUIRES_SOURCE_VERIFICATION.",
    "danger_sign_tests.jsonl: expected_rule_id is null; expected_safety_status is a preliminary label that needs clinical review before use.",
    "Supported-answer citation check is vacuous (0 supported answers exist) - it does NOT show answers are verified.",
]
report = dict(dataset="frontline_health_worker_companion_synthetic", synthetic_data_declaration="ALL RECORDS ARE SYNTHETIC. Not clinical advice, not real protocols, not real patients/facilities.",
              reference_date=REF, record_counts=counts, summary=dict(passed=sum(c["status"] == "PASS" for c in checks), failed=sum(c["status"] == "FAIL" for c in checks)),
              checks=checks, errors=errors, blocked_or_incomplete=blocked)
json.dump(report, open(os.path.join(D, "dataset_validation_report.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
print(report["summary"], counts)
for c in checks:
    if c["status"] == "FAIL": print("FAIL", c["check"], c["violations"])
for e in errors[:30]: print(" ", e)
