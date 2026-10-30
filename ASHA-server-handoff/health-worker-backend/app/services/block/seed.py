"""Loads the SYNTHETIC block (Chandrapuri: 6 villages, 5 ASHAs, 500 households, 2,234 people) from the hackathon pack, and optionally the
phone app's demo sync dataset (HH-SYN-*, WRK-SYN-*) so a phone in demo mode can sync against this server.

Map positions come from h5.export_assets.village_layout, the generator that made the phone's own village maps: same input, same seed,
same made-up street layout (checked by a test). Phone numbers are SYNTHETIC: +91 5xxxx xxxxx, a range not allocated to Indian mobiles."""
import csv
import datetime as dt
import hashlib
import os
from collections import Counter, defaultdict
from typing import Dict, List, Optional

from sqlalchemy import delete, func, select
from sqlalchemy.orm import Session

from app.db.base import Base, utcnow
from app.db.models import Asha, Household, HouseholdProfile, Member, Village
from app.services.dashboard import vis
from h5.export_assets import slug, village_layout

BLOCK = "Chandrapuri"


def _csv(path: str) -> List[dict]:
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def _date(s: str) -> Optional[dt.date]:
    try:
        return dt.date.fromisoformat((s or "").strip()[:10]) if (s or "").strip() else None
    except ValueError:
        return None


def synthetic_phone(household_id: str) -> str:
    n = int(hashlib.sha256(household_id.encode()).hexdigest()[:10], 16) % 10**9
    return "+91 5%04d %05d" % (n // 100000, n % 100000)


def categories(members: List[dict], today: dt.date) -> List[str]:
    cats = []
    if any(m.get("pregnant", "").upper() == "Y" for m in members):
        cats.append("ANC")
    kids = [m for m in members if _date(m.get("dob", "")) and (today - _date(m["dob"])).days < 5 * 365 + 1]
    if kids:
        cats += ["IMMUNISATION", "NUTRITION"]
    ncd = " ".join(m.get("ncd_condition", "") for m in members)
    if "HTN" in ncd:
        cats.append("HYPERTENSION")
    if "DM" in ncd:
        cats.append("DIABETES")
    return cats + ["ROUTINE"]


def wipe(db: Session) -> None:
    """Deletes every row of every table (children first). Schema stays; run migrations separately."""
    for t in reversed(Base.metadata.sorted_tables):
        db.execute(delete(t))
    db.commit()
    vis.clear_cache()


def load_block(db: Session, h5_dir: str, today: dt.date) -> Dict[str, int]:
    households = _csv(os.path.join(h5_dir, "households.csv"))
    register = _csv(os.path.join(h5_dir, "household_register.csv"))
    ashas = _csv(os.path.join(h5_dir, "ashas.csv"))
    by_hh: Dict[str, List[dict]] = defaultdict(list)
    for r in register:
        by_hh[r["household_id"]].append(r)
    by_village: Dict[str, List[dict]] = defaultdict(list)
    for h in households:
        by_village[h["village"]].append(h)
    positions: Dict[str, list] = {}
    for i, (vname, houses) in enumerate(sorted(by_village.items())):        # same order as h5.export_assets -> same maps as the phone
        pack, pos = village_layout(vname, houses, i)
        positions.update(pos)
        db.merge(Village(village_id=slug(vname), name=vname, block=BLOCK, source="block", map_json=pack))
    for a in ashas:
        db.merge(Asha(worker_id=a["asha_id"], name=a["asha_name"], villages=[slug(v) for v in a["villages"].split(";") if v], source="block"))
    rows = vis.build_rows(register, today)
    hh_of = {r["member_id"]: r["household_id"] for r in register}
    worst: Dict[str, dict] = {}
    for member_id, _item, _prio, status, due in rows:
        hid = hh_of[member_id]
        cur = worst.setdefault(hid, {"due": None, "status": "NO_VISIT_DUE"})
        d = dt.date.fromisoformat(due)
        cur["due"] = d if cur["due"] is None or d < cur["due"] else cur["due"]
        rank = {"overdue": "OVERDUE", "due_today": "DUE_TODAY", "due_this_week": "UPCOMING"}[status]
        order = ["NO_VISIT_DUE", "UPCOMING", "DUE_TODAY", "OVERDUE"]
        if order.index(rank) > order.index(cur["status"]):
            cur["status"] = rank
    now = utcnow()
    for h in households:
        hid = h["household_id"]
        mem = by_hh.get(hid, [])
        w = worst.get(hid, {"due": None, "status": "NO_VISIT_DUE"})
        cats = categories(mem, today)
        db.merge(Household(household_id=hid, village_id=slug(h["village"]), assigned_worker_id=h["asha_id"], household_member_count=max(1, len(mem)),
                           eligible_followup_categories="|" + "|".join(cats) + "|", last_visit_date=None, next_visit_due_date=w["due"],
                           scheduled_followup_category=None, record_status=w["status"], last_updated=now, version=1, synthetic_record=True))
    db.flush()                                  # households before the rows that point at them
    for h in households:
        hid = h["household_id"]
        p = positions.get(hid)
        db.merge(HouseholdProfile(household_id=hid, house_no=h["house_no"], head_member_id=h["head_member_id"], head_name=h["head_name"],
                                  lat=p[0] if p else None, lng=p[1] if p else None, phone_number=synthetic_phone(hid)))
    db.flush()
    for r in register:
        db.merge(Member(member_id=r["member_id"], household_id=r["household_id"], name=r["name"], relation=r["relation"] or None,
                        sex=(r["sex"] or None), dob=_date(r["dob"]), register=dict(r)))
    db.commit()
    vis.clear_cache()
    return {"villages": len(by_village), "ashas": len(ashas), "households": len(households), "members": len(register)}


def load_phone_demo(db: Session, dataset_dir: str) -> Dict[str, int]:
    """The sync datasets the phone app's demo mode uses (same ids and versions). Reuses the existing, tested importer."""
    from app.services.dataset_import.importer import import_datasets
    report = import_datasets(db, dataset_dir)
    vids = sorted({v for (v,) in db.execute(select(Household.village_id).where(Household.household_id.like("HH-SYN-%")).distinct())})
    for v in vids:
        db.merge(Village(village_id=v, name="Demo village " + v[-2:], block="Phone demo set", source="phone-demo", map_json=None))
    wids = Counter(w for (w,) in db.execute(select(Household.assigned_worker_id).where(Household.household_id.like("HH-SYN-%"))))
    by_w: Dict[str, set] = defaultdict(set)
    for w, v in db.execute(select(Household.assigned_worker_id, Household.village_id).where(Household.household_id.like("HH-SYN-%"))):
        by_w[w].add(v)
    for w in wids:
        db.merge(Asha(worker_id=w, name="Demo worker " + w[-3:], villages=sorted(by_w[w]), source="phone-demo"))
    db.commit()
    n = db.scalar(select(func.count()).select_from(Household).where(Household.household_id.like("HH-SYN-%"))) or 0
    return {"households": n, "villages": len(vids), "workers": len(wids), "import_report": report}
