"""The VIS daily visit list (h5.visit_list, the same rules the phone runs) over the register stored in the database, with urgency levels
for the website. Results are cached per day: the register only changes when the block is (re)seeded, which clears the cache."""
import datetime as dt
import threading
from typing import Dict, List, Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.db.models import Member
from h5.visit_list import build_visit_list

Row = Tuple[str, str, int, str, str]          # member_id, due_item, priority, status, due_date

URGENCY = ("URGENT", "DUE", "THIS_WEEK", "NONE")   # red, orange, blue, green; always shown with an icon and a word too
PRIORITY_URGENCY = {1: "URGENT", 2: "DUE", 3: "THIS_WEEK"}
STATUS_ORDER = {"overdue": 0, "due_today": 1, "due_this_week": 2}

_lock = threading.Lock()
_cache: Dict[Tuple[dt.date, int], dict] = {}


def clear_cache() -> None:
    with _lock:
        _cache.clear()


def build_rows(register: List[dict], day: dt.date) -> List[Row]:
    return build_visit_list(register, day)


def _load(db: Session, day: dt.date) -> dict:
    n = db.scalar(select(func.count()).select_from(Member)) or 0
    key = (day, n)
    with _lock:
        hit = _cache.get(key)
    if hit is not None:
        return hit
    members = db.execute(select(Member.member_id, Member.household_id, Member.register)).all()
    register = [m.register for m in members]
    rows = build_rows(register, day)
    hh_of = {m.member_id: m.household_id for m in members}
    asha_of = {m.member_id: (m.register or {}).get("asha_id") for m in members}
    by_hh: Dict[str, List[Row]] = {}
    for r in rows:
        by_hh.setdefault(hh_of[r[0]], []).append(r)
    data = {"rows": rows, "hh_of": hh_of, "asha_of": asha_of, "by_household": by_hh}
    with _lock:
        if len(_cache) > 32:
            _cache.clear()
        _cache[key] = data
    return data


def rows_for(db: Session, day: dt.date, worker_id: Optional[str] = None) -> List[Row]:
    d = _load(db, day)
    rows = d["rows"] if not worker_id else [r for r in d["rows"] if d["asha_of"].get(r[0]) == worker_id]
    return sorted(rows, key=lambda r: (r[2], STATUS_ORDER.get(r[3], 9), r[4], r[0], r[1]))


def household_of(db: Session, day: dt.date) -> Dict[str, str]:
    return _load(db, day)["hh_of"]


def household_rows(db: Session, day: dt.date, household_id: str) -> List[Row]:
    return sorted(_load(db, day)["by_household"].get(household_id, []), key=lambda r: (r[2], STATUS_ORDER.get(r[3], 9), r[4]))


def household_urgency(db: Session, day: dt.date) -> Dict[str, str]:
    """household_id -> URGENT | DUE | THIS_WEEK for houses with at least one VIS item (others: see urgency_from_status)."""
    out: Dict[str, str] = {}
    for hid, rows in _load(db, day)["by_household"].items():
        out[hid] = PRIORITY_URGENCY[min(r[2] for r in rows)]
    return out


def urgency_from_status(record_status: str, next_due: Optional[dt.date], day: dt.date) -> str:
    """Households without register members (synced from phones): the sync record's own status."""
    if record_status in ("OVERDUE", "DUE_TODAY"):
        return "DUE"
    if record_status == "UPCOMING" and next_due and (next_due - day).days <= 6:
        return "THIS_WEEK"
    return "NONE"
