"""POST /api/v1/ask: the h5 protocol engine (the same Python the phone's Dart port is checked against), run on the server.

Order inside the engine: danger signs first (always escalate, never "answered"), then the refusal rules (sex determination, medicines and
doses outside the protocols, reading scans/reports, admin, family planning), then BM25 retrieval quoting the protocol sections.
The question text is never stored or logged: the audit row keeps the outcome, cited section ids and rule ids only."""
import os
import threading
from pathlib import Path
from typing import Dict, Optional

from sqlalchemy.orm import Session

from app.core.config import Settings
from app.core.errors import DomainError
from app.core.principal import Principal
from app.db.models import QaAudit
from h5.pipeline import Assistant

DISCLAIMER = "Clinician-assisting only, not a diagnosis."
_lock = threading.Lock()
_engines: Dict[str, Assistant] = {}


def engine(s: Settings) -> Assistant:
    folder = os.path.join(s.resolved_h5_data, "protocols")
    with _lock:
        a = _engines.get(folder)
        if a is None:
            if not os.path.isdir(folder):
                raise DomainError("protocol folder not found on the server (set H5_DATA)", code="PROTOCOLS_MISSING", status_code=503)
            a = _engines[folder] = Assistant(Path(folder))
        return a


def ask(db: Session, p: Principal, s: Settings, question: str, channel: str = "web", household_id: Optional[str] = None) -> dict:
    a = engine(s)
    r = a.answer("web", question)
    outcome = "ESCALATED" if r["escalate"] else "REFUSED" if r["refused"] else "ANSWERED"
    row = QaAudit(actor=p.name[:64], channel=channel, outcome=outcome, cited_section_ids=list(r["cited_section_ids"]), rule_ids=list(r.get("_rules") or []),
                  escalate=bool(r["escalate"]), refused=bool(r["refused"]), latency_ms=r["latency_ms"], worker_id=p.worker_id,
                  household_id=household_id, status="OPEN" if r["escalate"] else None)
    db.add(row)
    db.commit()
    return dict(answer_text=r["answer_text"], cited_section_ids=r["cited_section_ids"],
                citations=[dict(section_id=sid, title=a.sections[sid].title if sid in a.sections else None) for sid in r["cited_section_ids"]],
                escalate=r["escalate"], refused=r["refused"], outcome=outcome, rule_ids=list(r.get("_rules") or []), latency_ms=r["latency_ms"],
                audit_id=row.id, disclaimer=DISCLAIMER)


def log_phone_qa(db: Session, p: Principal, outcome_code: str, rule_ids, section_ids) -> None:
    """Outcome of the older /health-qa routes (phones online). Only escalations and refusals are worth a supervisor's attention."""
    outcome = {"ESCALATION_REQUIRED": "ESCALATED", "OUT_OF_SCOPE": "REFUSED"}.get(outcome_code, "ANSWERED")
    db.add(QaAudit(actor=p.name[:64], channel="phone-qa", outcome=outcome, cited_section_ids=list(section_ids or [])[:5], rule_ids=list(rule_ids or [])[:10],
                   escalate=outcome == "ESCALATED", refused=outcome == "REFUSED", worker_id=p.worker_id, status="OPEN" if outcome == "ESCALATED" else None))
    db.commit()
