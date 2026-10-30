"""Hospital-sharing report aggregation. Counts are RECORDED referrals only: no predictions, no arrival probabilities,
and household visits are never counted as hospital attendance."""
import datetime as dt
import hashlib
import json
import uuid
from collections import Counter
from typing import Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import DomainError, NotFound
from app.core.principal import Principal
from app.db.base import utcnow
from app.db.models import Household, Referral, ReportRecord, Visit

PRIVACY_NOTICE = ("Aggregate counts only. Contains no household or patient identifiers. SYNTHETIC DATA in this environment. "
                  "Counts are recorded referrals, not predicted hospital arrivals; household visits are not hospital attendance.")


def _utc_naive(d: Optional[dt.datetime]) -> Optional[dt.datetime]:
    return d.astimezone(dt.timezone.utc).replace(tzinfo=None) if d is not None and d.tzinfo else d


def freshness(last_sync: Optional[dt.datetime], generated: dt.datetime, settings: Settings) -> str:
    if last_sync is None:
        return "NOT_PROVIDED"
    hours = (generated - last_sync).total_seconds() / 3600
    return "FRESH" if hours <= settings.fresh_hours else "RECENT" if hours <= settings.recent_hours else "STALE_OFFLINE"


def aggregate(refs: List[Referral], facility_id: str, start: dt.date, end: dt.date, status_override: Optional[Dict[str, str]] = None) -> dict:
    seen, status, cat, excl, included = set(), Counter(), Counter(), Counter(), []
    for r in refs:
        if r.referral_id in seen:
            excl["repeated_id_in_input"] += 1; continue
        seen.add(r.referral_id)
        if r.facility_id != facility_id:
            excl["other_facility"] += 1; continue
        if not (start <= r.referral_created_date <= end):
            excl["outside_period"] += 1; continue
        if r.record_state != "ACTIVE":
            excl[r.record_state.lower()] += 1; continue
        st = (status_override or {}).get(r.referral_id, r.referral_status)
        status[st] += 1; cat[r.service_category] += 1; included.append(r)
    return dict(status=status, category=cat, excluded=excl, included=included)


def build_summary(db: Session, p: Principal, settings: Settings, *, facility_id: str, period_start: dt.date, period_end: dt.date,
                  referral_ids: Optional[List[str]] = None, last_sync_at: Optional[dt.datetime] = None,
                  generated_at: Optional[dt.datetime] = None, status_override: Optional[Dict[str, str]] = None) -> dict:
    if period_end < period_start:
        raise DomainError("period_end is before period_start", code="BAD_PERIOD", status_code=422)
    generated = _utc_naive(generated_at) or utcnow()
    last_sync_at = _utc_naive(last_sync_at)
    stmt = select(Referral)
    if referral_ids is not None:
        by = {r.referral_id: r for r in db.scalars(select(Referral).where(Referral.referral_id.in_(set(referral_ids))))} if referral_ids else {}
        unknown = [i for i in referral_ids if i not in by]
        if unknown:
            raise DomainError("unknown referral ids in input", code="UNKNOWN_REFERRAL", details=unknown[:20], status_code=422)
        refs = [by[i] for i in referral_ids]
    else:
        refs = db.scalars(stmt.where(Referral.facility_id == facility_id)).all()
    if p.role == "worker":
        mine = {h for (h,) in db.execute(select(Household.household_id).where(Household.assigned_worker_id == p.worker_id))}
        refs = [r for r in refs if r.household_id in mine]
    agg = aggregate(refs, facility_id, period_start, period_end, status_override)
    inc = agg["included"]
    hh = {r.household_id for r in inc}
    due = completed = 0
    if hh:
        for v in db.scalars(select(Visit).where(Visit.household_id.in_(hh))):
            if v.visit_status == "PLANNED" and v.scheduled_date <= generated.date(): due += 1
            if v.visit_status == "COMPLETED" and v.actual_visit_date and period_start <= v.actual_visit_date <= period_end: completed += 1
    data_as_of = max((r.last_updated for r in inc), default=None)
    st = agg["status"]
    payload = dict(
        facility_id=facility_id, period_start=period_start.isoformat(), period_end=period_end.isoformat(),
        generated_at=generated.isoformat() + "Z", data_as_of=(data_as_of.isoformat() + "Z") if data_as_of else None,
        last_sync_at=(last_sync_at.isoformat() + "Z") if last_sync_at else None, data_freshness_label=freshness(last_sync_at, generated, settings),
        counts=dict(recommended=st["RECOMMENDED"], planned=st["PLANNED"], attendance_confirmed=st["ATTENDANCE_CONFIRMED"], total_included=sum(st.values())),
        counts_by_service_category=dict(sorted(agg["category"].items())), excluded_counts=dict(sorted(agg["excluded"].items())),
        follow_ups=dict(due=due, completed_in_period=completed), privacy_notice=PRIVACY_NOTICE, synthetic_data=True)
    canon = {k: payload[k] for k in ("facility_id", "period_start", "period_end", "data_as_of", "counts", "counts_by_service_category", "excluded_counts", "follow_ups")}
    payload["content_hash"] = hashlib.sha256(json.dumps(canon, sort_keys=True).encode()).hexdigest()
    return payload


def save_report(db: Session, payload: dict, p: Principal) -> dict:
    """Idempotent per data scope: identical content (facility/period/counts/data_as_of) returns the principal's existing report.
    Reports are stored with the creator's scope ('all' for admin/hospital, 'worker:<id>' for workers)."""
    ex = db.scalar(select(ReportRecord).where(ReportRecord.content_hash == payload["content_hash"], ReportRecord.facility_id == payload["facility_id"],
                                              ReportRecord.scope == p.scope_key))
    if ex:
        return dict(ex.payload, report_id=ex.report_id, duplicate_of_existing=True)
    rid = "RPT-" + uuid.uuid4().hex[:10].upper()
    body = dict(payload, report_id=rid, duplicate_of_existing=False)
    db.add(ReportRecord(report_id=rid, facility_id=payload["facility_id"], content_hash=payload["content_hash"], scope=p.scope_key, generated_at=utcnow(), payload=body))
    db.flush()
    return body


def get_report(db: Session, report_id: str, p: Principal) -> dict:
    rec = db.get(ReportRecord, report_id)
    if not rec or (p.role == "worker" and rec.scope != p.scope_key):
        raise NotFound("report not found")                      # 404: do not reveal other scopes' reports exist
    later = db.scalars(select(ReportRecord).where(ReportRecord.facility_id == rec.facility_id, ReportRecord.scope == rec.scope,
                                                  ReportRecord.generated_at >= rec.generated_at,
                                                  ReportRecord.report_id != rec.report_id).order_by(ReportRecord.generated_at)).all()
    same_period = [r for r in later if r.payload["period_start"] == rec.payload["period_start"] and r.payload["period_end"] == rec.payload["period_end"]
                   and r.content_hash != rec.content_hash]
    return dict(rec.payload, superseded_by=same_period[-1].report_id if same_period else None)
