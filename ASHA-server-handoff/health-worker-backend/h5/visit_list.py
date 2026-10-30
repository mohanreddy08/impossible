"""Daily visit list from the household register, exactly as written in the VIS protocol (VIS-1 to VIS-6).

    rows = build_visit_list(register_rows, today)      # [(member_id, due_item, priority, status, due_date), ...]

Pure functions over plain dicts: no pandas, no network, so the identical rules can run on the phone (see
health-worker-app/lib/h5/h5_visit_list.dart, which test/h5_visit_list_test.dart checks row for row).
"""
from __future__ import annotations

import csv
import re
from datetime import date, timedelta
from typing import Dict, Iterable, List, Optional, Tuple

# VIS-1.3 counting conventions [block rule]
UPCOMING_HORIZON_DAYS = 6
GRACE_DAYS = 28
FOLLOWUP_INTERVAL_DAYS = 30
TD2_GAP_DAYS = 28
VACCINE_LIST_AGE_TO_DAYS = 2554
HBNC_AGE_TO_DAYS = 42
MUAC_AGE_FROM_DAYS = 184
MUAC_AGE_TO_DAYS = 1824
MUAC_CONSIDER_FROM_DAYS = 178  # VIS-5.2: so a child turning 184 days within 6 days is listed as due_this_week

# VIS-5.1 thresholds
HB_BELOW = 7.0
SYSTOLIC_AT_OR_ABOVE = 140
DIASTOLIC_AT_OR_ABOVE = 90
MUAC_BELOW_CM = 11.5

# VIS-2.1 ANC windows: item -> (opens, closes) in days since LMP
ANC_WINDOWS = {1: (0, 84), 2: (98, 182), 3: (196, 238), 4: (252, 280)}

# VIS-3.1 vaccine table: item -> (due from age, not after age, previous dose needed, minimum gap in days)
VACCINES: Dict[str, Tuple[int, int, Optional[str], int]] = {
    "BCG": (0, 365, None, 0),
    "HepB-0": (0, 0, None, 0),
    "OPV-0": (0, 15, None, 0),
    "OPV-1": (42, 1825, None, 0),
    "OPV-2": (70, 1825, "OPV-1", 28),
    "OPV-3": (98, 1825, "OPV-2", 28),
    "Penta-1": (42, 365, None, 0),
    "Penta-2": (70, 365, "Penta-1", 28),
    "Penta-3": (98, 365, "Penta-2", 28),
    "RVV-1": (42, 365, None, 0),
    "RVV-2": (70, 365, "RVV-1", 28),
    "RVV-3": (98, 365, "RVV-2", 28),
    "fIPV-1": (42, 365, None, 0),
    "fIPV-2": (98, 365, "fIPV-1", 56),
    "fIPV-3": (276, 729, "fIPV-2", 56),
    "PCV-1": (42, 365, None, 0),
    "PCV-2": (98, 729, "PCV-1", 60),
    "PCV-B": (276, 729, "PCV-2", 60),
    "MR-1": (276, 1825, None, 0),
    "MR-2": (490, 1825, "MR-1", 28),
    "OPV-B": (490, 1825, "OPV-3", 180),
    "DPT-B1": (490, 2554, "Penta-3", 180),
    "DPT-B2": (1827, 2554, "DPT-B1", 0),
}

# VIS-4.1 HBNC visit days
HBNC_DAYS = {"institution": [3, 7, 14, 21, 28, 42], "home": [1, 3, 7, 14, 21, 28, 42]}


def _key(code: str) -> str:
    """'Penta-3', 'PENTA 3', 'penta3' -> 'penta3' (VIS-1.4: vaccine codes are written many ways)."""
    return re.sub(r"[^a-z0-9]", "", str(code).lower())


_VACCINE_BY_KEY = {_key(k): k for k in VACCINES}


def parse_date(s: str) -> Optional[date]:
    s = (s or "").strip()
    if not s:
        return None
    try:
        return date.fromisoformat(s[:10])
    except ValueError:
        return None


def parse_bp(s: str) -> Optional[Tuple[int, int]]:
    """'154/90' -> (154, 90). '0/0', blanks and rubbish mean 'not recorded' (VIS-1.4)."""
    m = re.match(r"^\s*(\d{2,3})\s*/\s*(\d{2,3})\s*$", s or "")
    if not m:
        return None
    sys_, dia = int(m.group(1)), int(m.group(2))
    return None if sys_ == 0 and dia == 0 else (sys_, dia)


def bp_is_high(bp: Optional[Tuple[int, int]]) -> bool:
    return bp is not None and (bp[0] >= SYSTOLIC_AT_OR_ABOVE or bp[1] >= DIASTOLIC_AT_OR_ABOVE)


def _float(s: str) -> Optional[float]:
    try:
        return float((s or "").strip())
    except ValueError:
        return None


def doses(cell: str, table_keys: Dict[str, str]) -> Dict[str, Optional[date]]:
    """'BCG:2026-09-27;penta1:2026-10-01' -> {'BCG': date, 'Penta-1': date}. Duplicates count once (earliest date)."""
    out: Dict[str, Optional[date]] = {}
    for part in (cell or "").split(";"):
        part = part.strip()
        if not part:
            continue
        code, _, d = part.partition(":")
        canon = table_keys.get(_key(code))
        if canon is None:
            continue
        dt = parse_date(d)
        if canon not in out or (dt is not None and (out[canon] is None or dt < out[canon])):
            out[canon] = dt
    return out


def _status(due: date, today: date, overdue_after: Optional[date] = None) -> Optional[str]:
    """Status of an item due on [due]. overdue_after = the last day it is still due_today (default due + 28)."""
    last_ok = overdue_after if overdue_after is not None else due + timedelta(days=GRACE_DAYS)
    if due > today + timedelta(days=UPCOMING_HORIZON_DAYS):
        return None
    if due > today:
        return "due_this_week"
    return "overdue" if today > last_ok else "due_today"


Row = Tuple[str, str, int, str, str]


def _is_high_risk(r: dict, today: date, age_days: Optional[int]) -> bool:
    if r.get("pregnant", "").strip().upper() == "Y":
        hb = _float(r.get("last_hb_gdl", ""))
        if (hb is not None and hb < HB_BELOW) or bp_is_high(parse_bp(r.get("last_anc_bp", ""))):
            return True
    if age_days is not None and 0 <= age_days <= HBNC_AGE_TO_DAYS:
        return True
    if age_days is not None and MUAC_AGE_FROM_DAYS <= age_days <= MUAC_AGE_TO_DAYS:
        muac = _float(r.get("last_muac_cm", ""))
        if (muac is not None and muac < MUAC_BELOW_CM) or r.get("bilateral_pitting_oedema", "").strip().upper() == "Y":
            return True
    if r.get("ncd_condition", "").strip() and bp_is_high(parse_bp(r.get("last_bp_reading", ""))):
        return True
    return False


def member_items(r: dict, today: date) -> List[Tuple[str, str, date]]:
    """All (item, status, due_date) for one register row, before priorities."""
    items: List[Tuple[str, str, date]] = []

    def add(item: str, due: date, overdue_after: Optional[date] = None, force: Optional[str] = None) -> None:
        st = force or _status(due, today, overdue_after)
        if st:
            items.append((item, st, due))

    dob = parse_date(r.get("dob", ""))
    age = (today - dob).days if dob else None

    # ---- VIS-2 pregnant women
    if r.get("pregnant", "").strip().upper() == "Y":
        lmp = parse_date(r.get("lmp_date", ""))
        anc_dates = sorted({d for d in (parse_date(x) for x in (r.get("anc_visit_dates") or "").split(";")) if d})
        if lmp:
            k = len(anc_dates) + 1
            if k in ANC_WINDOWS:
                opens, closes = ANC_WINDOWS[k]
                add(f"ANC-{k}", lmp + timedelta(days=opens), overdue_after=lmp + timedelta(days=closes))
        # Td (VIS-2.2): Td-1 (or Td-BST) is due on the date of the first recorded ANC check-up
        if anc_dates:
            td = doses(r.get("td_doses", ""), {_key(c): c for c in ("Td-1", "Td-2", "Td-BST")})
            first = anc_dates[0]
            if r.get("td_booster_eligible", "").strip().upper() == "Y":
                if "Td-BST" not in td:
                    add("Td-BST", first)
            else:
                if "Td-1" not in td:
                    add("Td-1", first)
                if "Td-1" in td and "Td-2" not in td and td["Td-1"] is not None:
                    add("Td-2", td["Td-1"] + timedelta(days=TD2_GAP_DAYS))
        # VIS-2.3 high-risk follow-up: on every day's list, due_today
        hb = _float(r.get("last_hb_gdl", ""))
        if (hb is not None and hb < HB_BELOW) or bp_is_high(parse_bp(r.get("last_anc_bp", ""))):
            items.append(("HRP-followup", "due_today", today))

    # ---- VIS-3 vaccines
    if age is not None and 0 <= age <= VACCINE_LIST_AGE_TO_DAYS:
        given = doses(r.get("child_vaccines", ""), _VACCINE_BY_KEY)
        for item, (from_age, not_after, prev, gap) in VACCINES.items():
            if item in given or age > not_after:
                continue
            due = dob + timedelta(days=from_age)
            if prev:
                if prev not in given:
                    continue
                pd_ = given[prev]
                if pd_ is None:
                    continue
                due = max(due, pd_ + timedelta(days=gap))
            if (due - dob).days > not_after:
                continue  # its due date falls after its "not after" age
            last_ok = min(due + timedelta(days=GRACE_DAYS), dob + timedelta(days=not_after) - timedelta(days=1))
            add(item, due, overdue_after=last_ok)

    # ---- VIS-4 newborn HBNC home visits
    if age is not None and 0 <= age <= HBNC_AGE_TO_DAYS:
        place = (r.get("place_of_delivery") or "").strip().lower()
        days = HBNC_DAYS["home" if place == "home" else "institution"]
        done = {int(x) for x in re.findall(r"\d+", r.get("hbnc_visits_done", "") or "")}
        sched = [(d, dob + timedelta(days=d - 1)) for d in days]
        past = [(d, dt) for d, dt in sched if dt <= today]
        listed = False
        if past:
            d, dt = past[-1]
            if d not in done:
                items.append((f"HBNC-D{d}", "due_today" if dt == today else "overdue", dt))
                listed = True
        if not listed:
            future = [(d, dt) for d, dt in sched if dt > today]
            if future:
                d, dt = future[0]
                if (dt - today).days <= UPCOMING_HORIZON_DAYS and d not in done:
                    items.append((f"HBNC-D{d}", "due_this_week", dt))

    # ---- VIS-5.2 MUAC check
    if age is not None and MUAC_CONSIDER_FROM_DAYS <= age <= MUAC_AGE_TO_DAYS:
        last = parse_date(r.get("last_muac_date", ""))
        due = last + timedelta(days=FOLLOWUP_INTERVAL_DAYS) if last else dob + timedelta(days=MUAC_AGE_FROM_DAYS)
        add("MUAC-check", due)

    # ---- VIS-5.3 NCD follow-up
    ncd = (r.get("ncd_condition") or "").upper()
    for cond, item, col in (("HTN", "BP-followup", "last_bp_check_date"), ("DM", "Sugar-followup", "last_sugar_check_date")):
        if cond in ncd:
            last = parse_date(r.get(col, ""))
            if last is None:
                items.append((item, "overdue", today))  # no check date recorded: overdue
            else:
                add(item, last + timedelta(days=FOLLOWUP_INTERVAL_DAYS))
    return items


def build_visit_list(register: Iterable[dict], today: date) -> List[Row]:
    rows: List[Row] = []
    for r in register:
        dob = parse_date(r.get("dob", ""))
        age = (today - dob).days if dob else None
        high = _is_high_risk(r, today, age)
        for item, status, due in member_items(r, today):
            if status in ("overdue", "due_today"):
                priority = 1 if high else 2
            else:
                priority = 3
            rows.append((r["member_id"], item, priority, status, due.isoformat()))
    return rows


def load_register(path) -> List[dict]:
    with open(path, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_visit_list(rows: List[Row], path, full: bool = False) -> None:
    """The submission format is member_id,due_item,priority; full=True also writes status and due_date (handy for reading)."""
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["member_id", "due_item", "priority", "status", "due_date"] if full else ["member_id", "due_item", "priority"])
        w.writerows(rows if full else [r[:3] for r in rows])
