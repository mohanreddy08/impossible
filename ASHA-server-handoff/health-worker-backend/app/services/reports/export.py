"""CSV and PDF renderers (pure functions of the report payload, so they can also run on-device)."""
import csv
import io

from fpdf import FPDF


def to_csv(r: dict) -> bytes:
    buf = io.StringIO()
    w = csv.writer(buf)
    w.writerow(["field", "value"])
    for k in ("report_id", "facility_id", "period_start", "period_end", "generated_at", "data_as_of", "last_sync_at", "data_freshness_label"):
        w.writerow([k, r.get(k) or ""])
    for k, v in r["counts"].items(): w.writerow(["count_" + k, v])
    for k, v in r["counts_by_service_category"].items(): w.writerow(["service_category_" + k, v])
    for k, v in r["excluded_counts"].items(): w.writerow(["excluded_" + k, v])
    w.writerow(["follow_ups_due", r["follow_ups"]["due"]]); w.writerow(["follow_ups_completed_in_period", r["follow_ups"]["completed_in_period"]])
    w.writerow(["privacy_notice", r["privacy_notice"]])
    return buf.getvalue().encode("utf-8")


def to_pdf(r: dict) -> bytes:
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Helvetica", "B", 15)
    pdf.cell(0, 10, "Referral summary (SYNTHETIC DATA)", new_x="LMARGIN", new_y="NEXT")
    pdf.set_font("Helvetica", "", 11)

    def line(text, bold=False):
        pdf.set_font("Helvetica", "B" if bold else "", 11)
        pdf.multi_cell(0, 6, text, new_x="LMARGIN", new_y="NEXT")

    line("Facility: %s" % r["facility_id"])
    line("Reporting period: %s to %s" % (r["period_start"], r["period_end"]))
    line("Report generated: %s" % r["generated_at"])
    line("Data as of: %s | Last sync: %s | Freshness: %s" % (r.get("data_as_of") or "n/a", r.get("last_sync_at") or "n/a", r["data_freshness_label"]))
    pdf.ln(3); line("Recorded referrals by status", True)
    c = r["counts"]
    line("Recommended: %d   Planned: %d   Attendance confirmed: %d   Total: %d" % (c["recommended"], c["planned"], c["attendance_confirmed"], c["total_included"]))
    pdf.ln(2); line("By service category", True)
    for k, v in r["counts_by_service_category"].items(): line("  %s: %d" % (k, v))
    pdf.ln(2); line("Follow-ups", True)
    line("Due: %d   Completed in period: %d" % (r["follow_ups"]["due"], r["follow_ups"]["completed_in_period"]))
    if r["excluded_counts"]:
        pdf.ln(2); line("Excluded records", True)
        for k, v in r["excluded_counts"].items(): line("  %s: %d" % (k.replace("_", " "), v))
    pdf.ln(4); line("Privacy notice", True); line(r["privacy_notice"])
    return bytes(pdf.output())
