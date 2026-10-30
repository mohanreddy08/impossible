"""CSV and PDF exports for the website. Every export is written to the admin audit (who, what, filters). Exports never contain phone
numbers or question text. The PDF uses the built-in Helvetica font, so it is English only (Telugu needs an embedded font: known limit)."""
import csv
import datetime as dt
import io
from typing import List, Tuple

from fpdf import FPDF
from sqlalchemy.orm import Session

from app.core.errors import DomainError
from app.core.principal import Principal
from app.services.accounts import service as accounts
from app.services.dashboard import service as dash

KINDS = ("visit-list", "households", "referrals", "qa-audit", "summary")
BANNER = "SYNTHETIC DATA - not real people. Clinician-assisting only, not a diagnosis."


def _csv(header: List[str], rows: List[list]) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["# " + BANNER])
    w.writerow(header)
    for r in rows:
        w.writerow(["" if v is None else (v.isoformat() if isinstance(v, (dt.date, dt.datetime)) else v) for v in r])
    return ("﻿" + buf.getvalue()).encode("utf-8")        # BOM: spreadsheet programs then open UTF-8 correctly


def _table(db: Session, p: Principal, day: dt.date, kind: str, worker_id, village_id) -> Tuple[str, List[str], List[list]]:
    if kind == "visit-list":
        vl = dash.visit_list(db, p, day, worker_id)
        rows = [[i["priority"], i["status"], i["due_date"], i["due_item"], i["name"], i["age"], i["house_no"], i["household_id"], i["village_name"], i["asha_name"]]
                for g in vl["groups"] for i in g["items"]]
        return "Visit list %s%s" % (day, " - " + (vl["asha_name"] or "") if worker_id else ""), \
            ["priority", "status", "due_date", "due_item", "name", "age", "house_no", "household_id", "village", "asha"], rows
    if kind == "households":
        items, _ = dash.households(db, p, day, village_id=village_id, worker_id=worker_id, limit=100000)
        return "Households %s" % day, ["household_id", "house_no", "head_name", "village", "asha", "members", "urgency", "due_items", "record_status"], \
            [[h["household_id"], h["house_no"], h["head_name"], h["village_name"], h["asha_name"], h["members"], h["urgency"], h["due_items"], h["record_status"]] for h in items]
    if kind == "referrals":
        items, _ = dash.referrals_feed(db, p, worker_id=worker_id, village_id=village_id, limit=100000)
        return "Referrals", ["referral_id", "household_id", "village", "service", "created", "planned", "status", "state", "label", "handled_by"], \
            [[r["referral_id"], r["household_id"], r["village_name"], r["service_category"], r["referral_created_date"], r["planned_visit_date"],
              r["referral_status"], r["record_state"], r["status_label"], r["handled_by"]] for r in items]
    if kind == "qa-audit":
        items, _ = dash.qa_audit(db, p, limit=100000)
        return "Q&A audit (no question text is stored)", ["at_utc", "channel", "outcome", "cited_sections", "rules", "status", "handled_by"], \
            [[a["at"], a["channel"], a["outcome"], " ".join(a["cited_section_ids"]), " ".join(a["rule_ids"]), a["status"], a["handled_by"]] for a in items]
    raise DomainError("summary is available as PDF only", code="BAD_FORMAT", status_code=422)


def _pdf(title: str, header: List[str], rows: List[list], summary: dict = None) -> bytes:
    pdf = FPDF(orientation="L")
    pdf.set_auto_page_break(True, 12)
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 14)
    pdf.cell(0, 9, _latin(title), new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 9)
    pdf.set_text_color(160, 0, 0)
    pdf.cell(0, 6, BANNER, new_x="LMARGIN", new_y="NEXT")
    pdf.set_text_color(0, 0, 0)
    pdf.cell(0, 6, "Generated %s UTC" % dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M"), new_x="LMARGIN", new_y="NEXT")
    pdf.ln(2)
    if summary:
        for k, v in summary.items():
            pdf.cell(0, 6, _latin("%s: %s" % (k, v)), new_x="LMARGIN", new_y="NEXT")
        pdf.ln(2)
    if header:
        width = (pdf.w - 20) / len(header)
        pdf.set_font("Helvetica", "B", 8)
        for h in header:
            pdf.cell(width, 6, _latin(h), border=1)
        pdf.ln()
        pdf.set_font("Helvetica", "", 8)
        for r in rows:
            for v in r:
                s = "" if v is None else (v.isoformat() if isinstance(v, (dt.date, dt.datetime)) else str(v))
                pdf.cell(width, 5, _latin(s)[: int(width / 1.6)], border=1)
            pdf.ln()
    return bytes(pdf.output())


def _latin(s: str) -> str:
    return s.encode("latin-1", "replace").decode("latin-1")


def export(db: Session, p: Principal, day: dt.date, kind: str, fmt: str, worker_id=None, village_id=None) -> Tuple[bytes, str, str]:
    if kind not in KINDS:
        raise DomainError("kind must be one of " + ", ".join(KINDS), code="BAD_KIND", status_code=422)
    if fmt not in ("csv", "pdf"):
        raise DomainError("format must be csv or pdf", code="BAD_FORMAT", status_code=422)
    if kind == "summary":
        if fmt != "pdf":
            raise DomainError("summary is available as PDF only", code="BAD_FORMAT", status_code=422)
        o = dash.overview(db, p, day)
        s = dash.asha_summaries(db, p, day)
        body = _pdf("Block summary %s" % day, ["ASHA", "households", "people", "priority 1", "priority 2", "priority 3", "open referrals"],
                    [[a["name"], a["households"], a["people"], a["priority1"], a["priority2"], a["priority3"], a["open_referrals"]] for a in s],
                    {"Households": o["households"], "People": o["people"], "Due today": o["due_today"], "Overdue": o["overdue"],
                     "Due this week": o["upcoming"], "Open referrals": o["open_referrals"], "Escalations (7 days)": o["escalations_7d_total"]})
    else:
        title, header, rows = _table(db, p, day, kind, worker_id, village_id)
        body = _csv(header, rows) if fmt == "csv" else _pdf(title, header, rows)
    accounts.audit(db, p.name, "export", kind, {"format": fmt, "date": day.isoformat(), "worker_id": worker_id, "village_id": village_id})
    db.commit()
    name = "asha-%s-%s.%s" % (kind, day.isoformat(), fmt)
    return body, ("text/csv; charset=utf-8" if fmt == "csv" else "application/pdf"), name
