"""Read models for the supervisor website. Framework-free: the API layer and the HTML pages both call these functions.

Scope: ASHA accounts (principal role 'worker') only ever see their own worker_id; supervisors and admins see the whole block."""
import datetime as dt
from collections import Counter, defaultdict
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import DomainError, NotFound
from app.core.principal import Principal, scoped_worker
from app.db.base import utcnow
from app.db.models import (Asha, AuditLog, Household, HouseholdProfile, Member, PhoneKey, QaAudit, Referral, SyncOperation, Village, Visit)
from app.schemas.domain import referral_label
from app.services.accounts import service as accounts
from app.services.dashboard import vis

ESCALATION_NOTES = ("REFERRED_108", "FAMILY_INFORMED", "ANM_VISITED", "MO_INFORMED", "FALSE_ALARM", "OTHER")
STALE_HOURS = 48


def today(s: Settings) -> dt.date:
    return dt.date.fromisoformat(s.demo_today) if s.demo_today else dt.date.today()


def mask_phone(num: Optional[str]) -> Optional[str]:
    if not num:
        return None
    digits = [c for c in num if c.isdigit()]
    return "+91 ••••• ••" + "".join(digits[-3:]) if len(digits) >= 3 else "•••"


def age_text(dob: Optional[dt.date], day: dt.date) -> str:
    if not dob:
        return ""
    days = (day - dob).days
    if days < 0:
        return ""
    if days < 61:
        return "%d d" % days
    months = (day.year - dob.year) * 12 + day.month - dob.month - (1 if day.day < dob.day else 0)
    return "%d mo" % months if months < 24 else "%d y" % (months // 12)


def _scope(p: Principal, worker_id: Optional[str] = None) -> Optional[str]:
    return scoped_worker(p, worker_id)


def _household_or_404(db: Session, p: Principal, household_id: str) -> Household:
    h = db.get(Household, household_id)
    if not h or (p.role == "worker" and h.assigned_worker_id != p.worker_id):
        raise NotFound("household not found")
    return h


def _names(db: Session) -> Tuple[Dict[str, str], Dict[str, str]]:
    villages = {v.village_id: v.name for v in db.scalars(select(Village))}
    ashas = {a.worker_id: a.name for a in db.scalars(select(Asha))}
    return villages, ashas


def _urgency_map(db: Session, day: dt.date, households: List[Household]) -> Dict[str, str]:
    vis_u = vis.household_urgency(db, day)
    with_members = {hid for (hid,) in db.execute(select(Member.household_id).distinct())}
    out = {}
    for h in households:
        if h.household_id in with_members:
            out[h.household_id] = vis_u.get(h.household_id, "NONE")
        else:
            out[h.household_id] = vis.urgency_from_status(h.record_status, h.next_visit_due_date, day)
    return out


# ---------------------------------------------------------------- villages and ASHAs
def villages(db: Session, p: Principal) -> List[dict]:
    w = _scope(p)
    q = select(Household.village_id, func.count()).group_by(Household.village_id)
    if w:
        q = q.where(Household.assigned_worker_id == w)
    counts = dict(db.execute(q).all())
    out = []
    for v in db.scalars(select(Village).order_by(Village.source, Village.name)):
        if w and v.village_id not in counts:
            continue
        out.append(dict(village_id=v.village_id, name=v.name, block=v.block, source=v.source, households=counts.get(v.village_id, 0),
                        has_map=v.map_json is not None))
    known = {v["village_id"] for v in out}
    for vid, n in sorted(counts.items()):                  # villages typed on a phone that the server has never seen before
        if vid not in known:
            out.append(dict(village_id=vid, name=vid, block="(new, from a phone)", source="phone", households=n, has_map=False))
    return out


def ashas(db: Session, p: Principal) -> List[dict]:
    w = _scope(p)
    q = select(Asha).order_by(Asha.source, Asha.name)
    if w:
        q = q.where(Asha.worker_id == w)
    return [dict(worker_id=a.worker_id, name=a.name, villages=a.villages, source=a.source) for a in db.scalars(q)]


# ---------------------------------------------------------------- households
def households(db: Session, p: Principal, day: dt.date, *, village_id=None, worker_id=None, status=None, urgency=None, priority=None,
               q=None, limit=50, offset=0) -> Tuple[List[dict], int]:
    w = _scope(p, worker_id)
    stmt = select(Household, HouseholdProfile).outerjoin(HouseholdProfile, HouseholdProfile.household_id == Household.household_id)
    if w:
        stmt = stmt.where(Household.assigned_worker_id == w)
    if village_id:
        stmt = stmt.where(Household.village_id == village_id)
    if status:
        stmt = stmt.where(Household.record_status == status)
    if q:
        like = "%" + q.replace("%", "").strip() + "%"
        stmt = stmt.where(Household.household_id.ilike(like) | HouseholdProfile.house_no.ilike(like) | HouseholdProfile.head_name.ilike(like))
    rows = db.execute(stmt.order_by(Household.village_id, HouseholdProfile.house_no, Household.household_id)).all()
    urg = _urgency_map(db, day, [h for h, _ in rows])
    vrows = vis.rows_for(db, day)
    hh_of = vis.household_of(db, day)
    min_prio: Dict[str, int] = {}
    due_count: Counter = Counter()
    for r in vrows:
        hid = hh_of[r[0]]
        due_count[hid] += 1
        min_prio[hid] = min(min_prio.get(hid, 9), r[2])
    if urgency:
        rows = [(h, pr) for h, pr in rows if urg[h.household_id] == urgency]
    if priority:
        rows = [(h, pr) for h, pr in rows if min_prio.get(h.household_id) == priority]
    vnames, anames = _names(db)
    total = len(rows)
    page = rows[offset:offset + limit]
    items = [dict(household_id=h.household_id, village_id=h.village_id, village_name=vnames.get(h.village_id, h.village_id),
                  worker_id=h.assigned_worker_id, asha_name=anames.get(h.assigned_worker_id, h.assigned_worker_id),
                  house_no=pr.house_no if pr else None, head_name=pr.head_name if pr else None, members=h.household_member_count,
                  record_status=h.record_status, next_visit_due_date=h.next_visit_due_date, urgency=urg[h.household_id],
                  top_priority=min_prio.get(h.household_id), due_items=due_count.get(h.household_id, 0), version=h.version,
                  from_phone=pr is None and not h.household_id.startswith("HH-SYN-"), last_updated=h.last_updated)
             for h, pr in page]
    return items, total


def _register_history(m: Member) -> List[dict]:
    r = m.register or {}
    ev: List[dict] = []
    for d in (r.get("anc_visit_dates") or "").split(";"):
        if d.strip():
            ev.append(dict(date=d.strip()[:10], member_id=m.member_id, name=m.name, what="ANC check-up"))
    for cell, label in (("child_vaccines", "Vaccine"), ("td_doses", "Td dose")):
        for part in (r.get(cell) or "").split(";"):
            if ":" in part:
                code, d = part.split(":", 1)
                ev.append(dict(date=d.strip()[:10], member_id=m.member_id, name=m.name, what="%s %s" % (label, code.strip())))
    if r.get("last_muac_date"):
        ev.append(dict(date=r["last_muac_date"][:10], member_id=m.member_id, name=m.name, what="MUAC %s cm" % (r.get("last_muac_cm") or "?")))
    if r.get("last_bp_check_date"):
        ev.append(dict(date=r["last_bp_check_date"][:10], member_id=m.member_id, name=m.name, what="BP check %s" % (r.get("last_bp_reading") or "")))
    if r.get("last_sugar_check_date"):
        ev.append(dict(date=r["last_sugar_check_date"][:10], member_id=m.member_id, name=m.name, what="Sugar check %s mg/dl" % (r.get("last_rbs_mg_dl") or "?")))
    return ev


def household_detail(db: Session, p: Principal, day: dt.date, household_id: str) -> dict:
    h = _household_or_404(db, p, household_id)
    prof = db.get(HouseholdProfile, household_id)
    members = list(db.scalars(select(Member).where(Member.household_id == household_id).order_by(Member.dob)))
    names = {m.member_id: m for m in members}
    due = [dict(member_id=r[0], name=names[r[0]].name if r[0] in names else r[0], due_item=r[1], priority=r[2], status=r[3], due_date=r[4],
                urgency=vis.PRIORITY_URGENCY[r[2]]) for r in vis.household_rows(db, day, household_id)]
    history = sorted([e for m in members for e in _register_history(m)], key=lambda e: e["date"], reverse=True)
    visits = [dict(visit_id=v.visit_id, scheduled_date=v.scheduled_date, actual_visit_date=v.actual_visit_date, visit_status=v.visit_status,
                   visit_reason=v.visit_reason, worker_id=v.worker_id, next_followup_date=v.next_followup_date, recorded_at=v.recorded_at)
              for v in db.scalars(select(Visit).where(Visit.household_id == household_id).order_by(Visit.scheduled_date.desc()))]
    refs = [_referral_dict(r, None, None, None) for r in db.scalars(select(Referral).where(Referral.household_id == household_id).order_by(Referral.referral_created_date.desc()))]
    vnames, anames = _names(db)
    urg = _urgency_map(db, day, [h])[h.household_id]
    vil = db.get(Village, h.village_id)
    return dict(household_id=h.household_id, village_id=h.village_id, village_name=vnames.get(h.village_id, h.village_id), worker_id=h.assigned_worker_id,
                asha_name=anames.get(h.assigned_worker_id, h.assigned_worker_id), house_no=prof.house_no if prof else None,
                head_name=prof.head_name if prof else None, members_count=h.household_member_count, record_status=h.record_status,
                categories=[c for c in h.eligible_followup_categories.split("|") if c], next_visit_due_date=h.next_visit_due_date,
                version=h.version, last_updated=h.last_updated, urgency=urg, phone_masked=mask_phone(prof.phone_number if prof else None),
                has_phone=bool(prof and prof.phone_number), position=[prof.lat, prof.lng] if prof and prof.lat is not None else None,
                has_map=bool(vil and vil.map_json), as_of=day,
                members=[dict(member_id=m.member_id, name=m.name, relation=m.relation, sex=m.sex, dob=m.dob, age=age_text(m.dob, day),
                              pregnant=(m.register or {}).get("pregnant") == "Y", ncd=(m.register or {}).get("ncd_condition") or None) for m in members],
                due_items=due, register_history=history[:60], visits=visits, referrals=refs)


def reveal_phone(db: Session, p: Principal, household_id: str, reason: str) -> dict:
    _household_or_404(db, p, household_id)
    prof = db.get(HouseholdProfile, household_id)
    if not prof or not prof.phone_number:
        raise NotFound("no phone number recorded for this household")
    accounts.audit(db, p.name, "phone_reveal", household_id, {"reason": reason})
    db.commit()
    return dict(household_id=household_id, phone_number=prof.phone_number, synthetic=True)


# ---------------------------------------------------------------- visit list
def visit_list(db: Session, p: Principal, day: dt.date, worker_id: Optional[str]) -> dict:
    w = _scope(p, worker_id)
    rows = vis.rows_for(db, day, w)
    ids = {r[0] for r in rows}
    mem = {m.member_id: m for m in db.scalars(select(Member).where(Member.member_id.in_(ids)))} if ids else {}
    hids = {m.household_id for m in mem.values()}
    profs = {x.household_id: x for x in db.scalars(select(HouseholdProfile).where(HouseholdProfile.household_id.in_(hids)))} if hids else {}
    vnames, anames = _names(db)
    groups: Dict[int, List[dict]] = {1: [], 2: [], 3: []}
    for member_id, item, prio, status, due in rows:
        m = mem.get(member_id)
        hid = m.household_id if m else None
        reg = (m.register if m else {}) or {}
        pr = profs.get(hid) if hid else None
        groups[prio].append(dict(member_id=member_id, name=m.name if m else member_id, age=age_text(m.dob, day) if m else "",
                                 relation=m.relation if m else None, household_id=hid, house_no=pr.house_no if pr else None,
                                 village_name=reg.get("village"), worker_id=reg.get("asha_id"), asha_name=anames.get(reg.get("asha_id", ""), ""),
                                 due_item=item, priority=prio, status=status, due_date=due, urgency=vis.PRIORITY_URGENCY[prio]))
    return dict(date=day, worker_id=w, asha_name=anames.get(w) if w else None, total=len(rows),
                groups=[dict(priority=k, urgency=vis.PRIORITY_URGENCY[k], count=len(v), items=v) for k, v in groups.items()])


# ---------------------------------------------------------------- map
def map_data(db: Session, p: Principal, day: dt.date, village_id: str) -> dict:
    v = db.get(Village, village_id)
    if not v:
        raise NotFound("village not found")
    w = _scope(p)
    q = select(Household, HouseholdProfile).outerjoin(HouseholdProfile, HouseholdProfile.household_id == Household.household_id).where(Household.village_id == village_id)
    if w:
        q = q.where(Household.assigned_worker_id == w)
    rows = db.execute(q).all()
    if w and not rows:
        raise NotFound("village not found")
    urg = _urgency_map(db, day, [h for h, _ in rows])
    houses, unplaced = [], []
    for h, pr in rows:
        d = dict(household_id=h.household_id, house_no=pr.house_no if pr else None, head_name=pr.head_name if pr else None,
                 urgency=urg[h.household_id], members=h.household_member_count)
        if pr and pr.lat is not None:
            houses.append(dict(d, lat=pr.lat, lng=pr.lng))
        else:
            unplaced.append(d)
    m = v.map_json or {}
    return dict(village_id=v.village_id, name=v.name, made_up=True, as_of=day, bounds=m.get("bounds"), roads=m.get("roads", []),
                places=m.get("places", []), houses=houses, unplaced=unplaced, counts=dict(Counter(x["urgency"] for x in houses + unplaced)))


# ---------------------------------------------------------------- referrals and escalations
def _referral_dict(r: Referral, h: Optional[Household], vnames, handled) -> dict:
    return dict(referral_id=r.referral_id, household_id=r.household_id, visit_id=r.visit_id, facility_id=r.facility_id,
                service_category=r.service_category, referral_created_date=r.referral_created_date, planned_visit_date=r.planned_visit_date,
                referral_status=r.referral_status, record_state=r.record_state, attendance_confirmed=r.attendance_confirmed,
                attendance_confirmation_date=r.attendance_confirmation_date, version=r.version, last_updated=r.last_updated,
                status_label=referral_label(r.referral_status, r.attendance_confirmed, r.record_state),
                worker_id=h.assigned_worker_id if h else None, village_id=h.village_id if h else None,
                village_name=(vnames or {}).get(h.village_id) if h else None,
                handled_by=(handled or {}).get(r.referral_id, (None, None))[0], handled_at=(handled or {}).get(r.referral_id, (None, None))[1])


def referrals_feed(db: Session, p: Principal, *, status=None, state=None, worker_id=None, village_id=None, open_only=False,
                   limit=50, offset=0) -> Tuple[List[dict], int]:
    w = _scope(p, worker_id)
    q = select(Referral, Household).join(Household, Household.household_id == Referral.household_id)
    if w:
        q = q.where(Household.assigned_worker_id == w)
    if village_id:
        q = q.where(Household.village_id == village_id)
    if status:
        q = q.where(Referral.referral_status == status)
    if state:
        q = q.where(Referral.record_state == state)
    if open_only:
        q = q.where(Referral.record_state == "ACTIVE", Referral.referral_status != "ATTENDANCE_CONFIRMED")
    total = db.scalar(select(func.count()).select_from(q.subquery())) or 0
    rows = db.execute(q.order_by(Referral.last_updated.desc(), Referral.referral_id).limit(limit).offset(offset)).all()
    ids = [r.referral_id for r, _ in rows]
    handled: Dict[str, tuple] = {}
    if ids:
        for a in db.scalars(select(AuditLog).where(AuditLog.entity_type == "referral", AuditLog.entity_id.in_(ids)).order_by(AuditLog.at)):
            handled[a.entity_id] = (a.actor, a.at)
    vnames, _ = _names(db)
    return [_referral_dict(r, h, vnames, handled) for r, h in rows], total


def _qa_dict(a: QaAudit) -> dict:
    return dict(id=a.id, at=a.at, actor=a.actor, channel=a.channel, outcome=a.outcome, cited_section_ids=a.cited_section_ids, rule_ids=a.rule_ids,
                escalate=a.escalate, refused=a.refused, latency_ms=a.latency_ms, worker_id=a.worker_id, household_id=a.household_id,
                status=a.status, handled_by=a.handled_by, handled_at=a.handled_at, note_code=a.note_code)


def escalations(db: Session, p: Principal, *, status=None, days: Optional[int] = None, limit=50, offset=0) -> Tuple[List[dict], int]:
    q = select(QaAudit).where(QaAudit.escalate.is_(True))
    if p.role == "worker":
        q = q.where(QaAudit.worker_id == p.worker_id)
    if status:
        q = q.where(QaAudit.status == status)
    if days:
        q = q.where(QaAudit.at >= utcnow() - dt.timedelta(days=days))
    total = db.scalar(select(func.count()).select_from(q.subquery())) or 0
    return [_qa_dict(a) for a in db.scalars(q.order_by(QaAudit.at.desc(), QaAudit.id.desc()).limit(limit).offset(offset))], total


def update_escalation(db: Session, p: Principal, esc_id: int, status: str, note_code: Optional[str]) -> dict:
    a = db.get(QaAudit, esc_id)
    if not a or not a.escalate:
        raise NotFound("escalation not found")
    if note_code and note_code not in ESCALATION_NOTES:
        raise DomainError("note_code must be one of " + ", ".join(ESCALATION_NOTES), code="BAD_NOTE", status_code=422)
    order = {"OPEN": 0, "ACKNOWLEDGED": 1, "CLOSED": 2}
    if order[status] < order.get(a.status or "OPEN", 0):
        raise DomainError("an escalation cannot go back to %s" % status, code="INVALID_TRANSITION", status_code=409)
    a.status, a.handled_by, a.handled_at = status, p.name, utcnow()
    if note_code:
        a.note_code = note_code
    accounts.audit(db, p.name, "escalation_" + status.lower(), str(esc_id), {"note_code": note_code})
    db.commit()
    return _qa_dict(a)


def qa_audit(db: Session, p: Principal, *, outcome=None, limit=50, offset=0) -> Tuple[List[dict], int]:
    q = select(QaAudit)
    if p.role == "worker":
        q = q.where(QaAudit.worker_id == p.worker_id)
    if outcome:
        q = q.where(QaAudit.outcome == outcome)
    total = db.scalar(select(func.count()).select_from(q.subquery())) or 0
    return [_qa_dict(a) for a in db.scalars(q.order_by(QaAudit.at.desc(), QaAudit.id.desc()).limit(limit).offset(offset))], total


# ---------------------------------------------------------------- phones
def sync_status(db: Session, p: Principal) -> List[dict]:
    w = _scope(p)
    now = utcnow()
    q = select(PhoneKey).order_by(PhoneKey.revoked_at.is_not(None), PhoneKey.worker_id, PhoneKey.created_at)
    if w:
        q = q.where(PhoneKey.worker_id == w)
    keys = list(db.scalars(q))
    insts = [k.last_installation_hash for k in keys if k.last_installation_hash]
    unresolved: Dict[str, Counter] = defaultdict(Counter)
    if insts:
        for inst, st, n in db.execute(select(SyncOperation.installation_hash, SyncOperation.status, func.count())
                                      .where(SyncOperation.installation_hash.in_(insts), SyncOperation.status.in_(("CONFLICT", "REJECTED")))
                                      .group_by(SyncOperation.installation_hash, SyncOperation.status)):
            unresolved[inst][st] = n
    _, anames = _names(db)
    out = []
    for k in keys:
        seen = k.last_sync_at
        stale = not k.revoked_at and (seen is None or (now - seen).total_seconds() > STALE_HOURS * 3600)
        u = unresolved.get(k.last_installation_hash or "", Counter())
        out.append(dict(key_id=k.key_id, label=k.label, worker_id=k.worker_id, asha_name=anames.get(k.worker_id, k.worker_id), created_at=k.created_at,
                        revoked=k.revoked_at is not None, revoked_at=k.revoked_at, last_seen_at=k.last_seen_at, last_sync_at=k.last_sync_at,
                        stale=stale, client_agent=k.client_agent, pushes=k.pushes, ops_received=k.ops_received, ops_acknowledged=k.ops_acknowledged,
                        conflicts=u.get("CONFLICT", 0), rejected=u.get("REJECTED", 0),
                        pending_note="changes still waiting on the phone are not reported by the current app; conflicts/rejected are ops the server could not apply"))
    return out


# ---------------------------------------------------------------- overview, summaries, reports
def overview(db: Session, p: Principal, day: dt.date) -> dict:
    w = _scope(p)
    rows = vis.rows_for(db, day, w)
    by_status = Counter(r[3] for r in rows)
    hh_of = vis.household_of(db, day)
    hstat = select(Household.record_status, func.count()).where(~Household.household_id.in_(select(Member.household_id).distinct())).group_by(Household.record_status)
    if w:
        hstat = hstat.where(Household.assigned_worker_id == w)
    synced = dict(db.execute(hstat).all())
    _, total_open = referrals_feed(db, p, open_only=True, limit=1)
    esc, esc_total = escalations(db, p, days=7, limit=10)
    _, esc_open = escalations(db, p, status="OPEN", limit=1)
    phones = sync_status(db, p)
    p1 = visit_list(db, p, day, w)["groups"][0]["items"]
    hq = select(func.count()).select_from(Household)
    mq = select(func.count()).select_from(Member)
    if w:
        hq = hq.where(Household.assigned_worker_id == w)
        mq = mq.join(Household, Household.household_id == Member.household_id).where(Household.assigned_worker_id == w)
    return dict(date=day, households=db.scalar(hq) or 0, people=db.scalar(mq) or 0,
                due_today=by_status.get("due_today", 0), overdue=by_status.get("overdue", 0), upcoming=by_status.get("due_this_week", 0),
                households_with_due=len({hh_of[r[0]] for r in rows if r[3] != "due_this_week"}),
                synced_records=dict(OVERDUE=synced.get("OVERDUE", 0), DUE_TODAY=synced.get("DUE_TODAY", 0), UPCOMING=synced.get("UPCOMING", 0)),
                open_referrals=total_open, priority1=p1, escalations_7d=esc, escalations_7d_total=esc_total, escalations_open=esc_open,
                phones_stale=[x for x in phones if x["stale"]], phones_total=len([x for x in phones if not x["revoked"]]))


def asha_summaries(db: Session, p: Principal, day: dt.date) -> List[dict]:
    rows = vis.rows_for(db, day)
    asha_of = vis._load(db, day)["asha_of"]
    by = defaultdict(Counter)
    for r in rows:
        by[asha_of.get(r[0])]["p%d" % r[2]] += 1
    hh = dict(db.execute(select(Household.assigned_worker_id, func.count()).group_by(Household.assigned_worker_id)).all())
    ppl = dict(db.execute(select(Household.assigned_worker_id, func.count()).join(Member, Member.household_id == Household.household_id).group_by(Household.assigned_worker_id)).all())
    refs = dict(db.execute(select(Household.assigned_worker_id, func.count()).join(Referral, Referral.household_id == Household.household_id)
                           .where(Referral.record_state == "ACTIVE", Referral.referral_status != "ATTENDANCE_CONFIRMED").group_by(Household.assigned_worker_id)).all())
    last = {}
    for k in db.scalars(select(PhoneKey).where(PhoneKey.revoked_at.is_(None))):
        if k.last_sync_at and (k.worker_id not in last or k.last_sync_at > last[k.worker_id]):
            last[k.worker_id] = k.last_sync_at
    out = []
    for a in ashas(db, p):
        c = by.get(a["worker_id"], Counter())
        out.append(dict(a, households=hh.get(a["worker_id"], 0), people=ppl.get(a["worker_id"], 0), priority1=c["p1"], priority2=c["p2"],
                        priority3=c["p3"], open_referrals=refs.get(a["worker_id"], 0), last_phone_sync=last.get(a["worker_id"])))
    return out


def village_summaries(db: Session, p: Principal, day: dt.date) -> List[dict]:
    w = _scope(p)
    q = select(Household)
    if w:
        q = q.where(Household.assigned_worker_id == w)
    hs = list(db.scalars(q))
    urg = _urgency_map(db, day, hs)
    by = defaultdict(Counter)
    for h in hs:
        by[h.village_id][urg[h.household_id]] += 1
    out = []
    for v in villages(db, p):
        c = by.get(v["village_id"], Counter())
        out.append(dict(v, urgent=c["URGENT"], due=c["DUE"], this_week=c["THIS_WEEK"], nothing_due=c["NONE"]))
    return out


def report_summary(db: Session, p: Principal, day: dt.date) -> dict:
    since = utcnow() - dt.timedelta(days=13)
    q = select(QaAudit.at, QaAudit.outcome).where(QaAudit.at >= since.replace(hour=0, minute=0, second=0))
    if p.role == "worker":
        q = q.where(QaAudit.worker_id == p.worker_id)
    per_day: Dict[str, Counter] = defaultdict(Counter)
    for at, outcome in db.execute(q):
        per_day[at.date().isoformat()][outcome] += 1
    days = [(since.date() + dt.timedelta(days=i)).isoformat() for i in range(14)]
    rq = select(Referral.referral_status, Referral.record_state, func.count()).group_by(Referral.referral_status, Referral.record_state)
    w = _scope(p)
    if w:
        rq = rq.join(Household, Household.household_id == Referral.household_id).where(Household.assigned_worker_id == w)
    refs = [dict(referral_status=s, record_state=st, count=n) for s, st, n in db.execute(rq)]
    items = Counter(r[1].split("-")[0] for r in vis.rows_for(db, day, w))
    return dict(date=day, ashas=asha_summaries(db, p, day) if p.role != "worker" else [x for x in asha_summaries(db, p, day)],
                villages=village_summaries(db, p, day), referrals=refs,
                qa_by_day=[dict(day=d, ANSWERED=per_day[d]["ANSWERED"], REFUSED=per_day[d]["REFUSED"], ESCALATED=per_day[d]["ESCALATED"]) for d in days],
                due_items_by_kind=[dict(kind=k, count=n) for k, n in items.most_common(12)])


def as_jsonable(x: Any) -> Any:
    if isinstance(x, (dt.date, dt.datetime)):
        return x.isoformat()
    if isinstance(x, dict):
        return {k: as_jsonable(v) for k, v in x.items()}
    if isinstance(x, list):
        return [as_jsonable(v) for v in x]
    return x
