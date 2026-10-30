from fastapi import APIRouter, Depends, Response
from sqlalchemy.orm import Session

from app.core.config import Settings, get_settings
from app.core.errors import DomainError
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.api import ReportIn, ReportOut
from app.services.reports import export, service

router = APIRouter(prefix="/reports", tags=["reports"])


@router.post("/summary", response_model=ReportOut, summary="Build (and idempotently store) a hospital-sharing summary")
def create_summary(body: ReportIn, db: Session = Depends(get_db), p: Principal = Depends(get_principal), s: Settings = Depends(get_settings)):
    payload = service.build_summary(db, p, s, facility_id=body.facility_id, period_start=body.period_start, period_end=body.period_end,
                                    referral_ids=body.referral_ids, last_sync_at=body.last_sync_at)
    out = service.save_report(db, payload, p); db.commit()
    return out


@router.get("/{report_id}", response_model=ReportOut, summary="Fetch a stored report as JSON (format=json) or download CSV/PDF",
            responses={200: {"content": {"text/csv": {}, "application/pdf": {}}, "description": "JSON by default; CSV or PDF when format=csv|pdf"}})
def get_report(report_id: str, format: str = "json", db: Session = Depends(get_db), p: Principal = Depends(get_principal)):
    r = service.get_report(db, report_id, p)
    if format == "json": return r
    if format == "csv": return Response(export.to_csv(r), media_type="text/csv", headers={"Content-Disposition": "attachment; filename=%s.csv" % report_id})
    if format == "pdf": return Response(export.to_pdf(r), media_type="application/pdf", headers={"Content-Disposition": "attachment; filename=%s.pdf" % report_id})
    raise DomainError("format must be json, csv or pdf", code="BAD_FORMAT", status_code=422)
