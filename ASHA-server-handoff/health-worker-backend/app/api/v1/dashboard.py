import datetime as dt
from typing import Literal, Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.config import Settings, get_settings
from app.core.security import Principal, get_principal, require_roles
from app.db.session import get_db
from app.schemas.dashboard import EscalationPatchIn, PageOut, RevealIn
from app.services.dashboard import export as exporter
from app.services.dashboard import service as dash
from app.services.dashboard.service import as_jsonable

router = APIRouter(prefix="/dashboard", tags=["dashboard (website)"])
staff = require_roles("admin", "supervisor", "hospital")
ID = Query(None, pattern=r"^[A-Za-z0-9_-]{2,32}$")
Urgency = Literal["URGENT", "DUE", "THIS_WEEK", "NONE"]


def _day(day: Optional[dt.date], s: Settings) -> dt.date:
    return day or dash.today(s)


@router.get("/overview", response_model=dict, summary="Due today / overdue / upcoming, open referrals, today's priority-1 list, escalations (7 days), stale phones")
def overview(date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    return as_jsonable(dash.overview(db, p, _day(date, s)))


@router.get("/villages", response_model=list, summary="Villages with household counts")
def villages(db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    return dash.villages(db, p)


@router.get("/ashas", response_model=list, summary="ASHA summaries: households, people, due items by priority, open referrals, last phone sync")
def ashas(date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    return as_jsonable(dash.asha_summaries(db, p, _day(date, s)))


@router.get("/village-summaries", response_model=list, summary="Village summaries: households by urgency")
def village_summaries(date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    return dash.village_summaries(db, p, _day(date, s))


@router.get("/households", response_model=PageOut, summary="Households, filterable by village, ASHA, sync status, urgency or top VIS priority")
def households(village_id: Optional[str] = Query(None, max_length=32), worker_id: Optional[str] = ID,
               status: Optional[Literal["UPCOMING", "DUE_TODAY", "OVERDUE", "COMPLETED", "NO_VISIT_DUE"]] = None,
               urgency: Optional[Urgency] = None, priority: Optional[int] = Query(None, ge=1, le=3), q: Optional[str] = Query(None, max_length=40),
               date: Optional[dt.date] = None, limit: int = LIMIT, offset: int = OFFSET,
               db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    items, total = dash.households(db, p, _day(date, s), village_id=village_id, worker_id=worker_id, status=status, urgency=urgency,
                                   priority=priority, q=q, limit=limit, offset=offset)
    return PageOut(items=as_jsonable(items), total=total, limit=limit, offset=offset)


@router.get("/households/{household_id}", response_model=dict, summary="Household: members, due items (VIS), register history, synced visits, referrals. Phone masked.")
def household(household_id: str, date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings),
              p: Principal = Depends(get_principal)):
    return as_jsonable(dash.household_detail(db, p, _day(date, s), household_id))


@router.post("/households/{household_id}/reveal-phone", response_model=dict, summary="Show the full (synthetic) phone number. Every reveal is audit-logged.")
def reveal(household_id: str, body: Optional[RevealIn] = None, *, db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    return dash.reveal_phone(db, p, household_id, (body or RevealIn()).reason)


@router.get("/visit-list", response_model=dict, summary="Daily visit list for an ASHA and a date from the h5 VIS rules, grouped by priority 1/2/3")
def visit_list(worker_id: Optional[str] = ID, date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings),
               p: Principal = Depends(get_principal)):
    return as_jsonable(dash.visit_list(db, p, _day(date, s), worker_id))


@router.get("/map/{village_id}", response_model=dict, summary="Generated (made-up) village street layout and house points coloured by urgency")
def map_data(village_id: str, date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings),
             p: Principal = Depends(get_principal)):
    return as_jsonable(dash.map_data(db, p, _day(date, s), village_id))


@router.get("/referrals", response_model=PageOut, summary="Referral feed with who handled each one last (change status with PATCH /api/v1/referrals/{id})")
def referrals(status: Optional[Literal["RECOMMENDED", "PLANNED", "ATTENDANCE_CONFIRMED"]] = None,
              state: Optional[Literal["ACTIVE", "CANCELLED", "INVALID", "DUPLICATE"]] = None, open_only: bool = False,
              worker_id: Optional[str] = ID, village_id: Optional[str] = Query(None, max_length=32), limit: int = LIMIT, offset: int = OFFSET,
              db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    items, total = dash.referrals_feed(db, p, status=status, state=state, worker_id=worker_id, village_id=village_id, open_only=open_only,
                                       limit=limit, offset=offset)
    return PageOut(items=as_jsonable(items), total=total, limit=limit, offset=offset)


@router.get("/escalations", response_model=PageOut, summary="Danger-sign escalations from Ask (outcome only, never the question text)")
def escalations(status: Optional[Literal["OPEN", "ACKNOWLEDGED", "CLOSED"]] = None, days: Optional[int] = Query(None, ge=1, le=3650),
                limit: int = LIMIT, offset: int = OFFSET, db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    items, total = dash.escalations(db, p, status=status, days=days, limit=limit, offset=offset)
    return PageOut(items=as_jsonable(items), total=total, limit=limit, offset=offset)


@router.patch("/escalations/{escalation_id}", response_model=dict, summary="Acknowledge or close an escalation (records who handled it)")
def patch_escalation(escalation_id: int, body: EscalationPatchIn, db: Session = Depends(get_db), p: Principal = Depends(staff)):
    return as_jsonable(dash.update_escalation(db, p, escalation_id, body.status, body.note_code))


@router.get("/qa-audit", response_model=PageOut, summary="Q&A audit log: outcome, cited section ids, timestamp. Question text is never stored.")
def qa_audit(outcome: Optional[Literal["ESCALATED", "REFUSED", "ANSWERED"]] = None, limit: int = LIMIT, offset: int = OFFSET,
             db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    items, total = dash.qa_audit(db, p, outcome=outcome, limit=limit, offset=offset)
    return PageOut(items=as_jsonable(items), total=total, limit=limit, offset=offset)


@router.get("/sync-status", response_model=list, summary="Per phone: last seen, last sync, operations, unresolved conflicts/rejections, app identification")
def sync_status(db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    return as_jsonable(dash.sync_status(db, p))


@router.get("/reports/summary", response_model=dict, summary="Numbers behind the Reports page charts")
def report_summary(date: Optional[dt.date] = None, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    return as_jsonable(dash.report_summary(db, p, _day(date, s)))


@router.get("/reports/export", summary="CSV or PDF export (visit-list, households, referrals, qa-audit; summary as PDF). Every export is audit-logged.",
            response_class=Response,
            responses={200: {"content": {"text/csv": {}, "application/pdf": {}}, "description": "The file"}})
def export(kind: Literal["visit-list", "households", "referrals", "qa-audit", "summary"], format: Literal["csv", "pdf"] = "csv",
           worker_id: Optional[str] = ID, village_id: Optional[str] = Query(None, max_length=32), date: Optional[dt.date] = None,
           db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(staff)):
    body, ctype, name = exporter.export(db, p, _day(date, s), kind, format, worker_id, village_id)
    return Response(body, media_type=ctype, headers={"Content-Disposition": 'attachment; filename="%s"' % name})
