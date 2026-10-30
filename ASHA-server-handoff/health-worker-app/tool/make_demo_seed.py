#!/usr/bin/env python3
"""Build assets/demo/demo_seed.json (SYNTHETIC) for ONE worker from the existing backend datasets, in the API's JSON shape.
Reads ../health-worker-datasets (never modifies it). Also copies the backend's danger_rules.json so the on-device safety
engine uses the exact same ruleset file. Re-run whenever either source changes."""
import csv, datetime as dt, json, os, shutil, sys
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DS = os.path.abspath(os.path.join(ROOT, "..", "health-worker-datasets"))
BE = os.path.abspath(os.path.join(ROOT, "..", "health-worker-backend"))
WORKER = sys.argv[1] if len(sys.argv) > 1 else "WRK-SYN-001"

def rows(fn): return list(csv.DictReader(open(os.path.join(DS, fn), encoding="utf-8", newline="")))
def utc(s):
    d = dt.datetime.fromisoformat(s)
    return d.astimezone(dt.timezone.utc).replace(tzinfo=None).isoformat() + "Z"
def nn(s): return s if s else None
def b(s): return {"true": True, "false": False}.get(s)

H = [r for r in rows("household_register_500.csv") if r["assigned_worker_id"] == WORKER]
ids = {r["household_id"] for r in H}
V = [r for r in rows("visit_history.csv") if r["household_id"] in ids]
R = [r for r in rows("referral_records.csv") if r["household_id"] in ids]
out = dict(
    synthetic=True, worker_id=WORKER, reference_date="2026-10-13",
    note="SYNTHETIC demo data derived from the project's generated datasets. Not real people, not clinical.",
    households=[dict(household_id=r["household_id"], village_id=r["village_id"], assigned_worker_id=r["assigned_worker_id"],
                     household_member_count=int(r["household_member_count"]), eligible_followup_categories=[c for c in r["eligible_followup_categories"].split("|") if c],
                     last_visit_date=nn(r["last_visit_date"]), next_visit_due_date=nn(r["next_visit_due_date"]), scheduled_followup_category=nn(r["scheduled_followup_category"]),
                     record_status=r["record_status"], last_updated=utc(r["last_updated_timestamp"]), version=1, synthetic_record=True) for r in H],
    visits=[dict(visit_id=r["visit_id"], household_id=r["household_id"], worker_id=r["worker_id"], scheduled_date=r["scheduled_date"], actual_visit_date=nn(r["actual_visit_date"]),
                 visit_status=r["visit_status"], visit_reason=r["visit_reason"], followup_required=b(r["followup_required"]), next_followup_date=nn(r["next_followup_date"]),
                 referral_status=r["referral_status"], referral_id=nn(r["referral_id"]), recorded_at=utc(r["recorded_timestamp"]), updated_at=utc(r["recorded_timestamp"]),
                 version=1, synthetic_record=True) for r in V],
    referrals=[dict(referral_id=r["referral_id"], household_id=r["household_id"], visit_id=r["visit_id"], facility_id=r["facility_id"], service_category=r["service_category"],
                    referral_created_date=r["referral_created_date"], planned_visit_date=nn(r["planned_visit_date"]), referral_status=r["referral_status"],
                    attendance_confirmed=r["attendance_confirmed"] == "true", attendance_confirmation_date=nn(r["attendance_confirmation_date"]),
                    attendance_record_id=nn(r["attendance_record_id"]), record_state=r["record_state"], duplicate_of=nn(r["duplicate_of"]),
                    last_updated=utc(r["record_last_updated"]), version=1, synthetic_record=True) for r in R],
)
p = os.path.join(ROOT, "assets", "demo", "demo_seed.json")
json.dump(out, open(p, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))
shutil.copyfile(os.path.join(BE, "app", "services", "safety", "rules", "danger_rules.json"), os.path.join(ROOT, "assets", "safety", "danger_rules.json"))
print("seed: %d households, %d visits, %d referrals, %d bytes" % (len(H), len(V), len(R), os.path.getsize(p)))
