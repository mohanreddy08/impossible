/* Escalation acknowledge/close and referral status changes (PATCH with the record's version: optimistic concurrency). */
"use strict";
(function () {
  document.querySelectorAll(".esc-act").forEach((b) => b.addEventListener("click", async () => {
    const row = document.getElementById("esc-" + b.dataset.id);
    const note = row.querySelector(".esc-note");
    b.disabled = true;
    try {
      const r = await api("PATCH", "/api/v1/dashboard/escalations/" + b.dataset.id, { status: b.dataset.status, note_code: (note && note.value) || null });
      row.querySelector(".esc-status").replaceChildren(el("strong", { text: r.status }), r.note_code ? el("br") : "", r.note_code || "");
      row.querySelector(".esc-handled").textContent = r.handled_by;
      if (r.status === "CLOSED") row.querySelectorAll("button,select").forEach((x) => x.remove());
      else b.remove();
      say(r.status);
    } catch (e) { b.disabled = false; alert(e.message); }
  }));
  document.querySelectorAll("form.ref-form").forEach((f) => f.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const action = (ev.submitter && ev.submitter.value) || "plan";
    const fd = new FormData(f);
    const body = { version: Number(f.dataset.version) };
    if (action === "plan") { body.referral_status = "PLANNED"; body.planned_visit_date = fd.get("planned_visit_date"); }
    else { body.referral_status = "ATTENDANCE_CONFIRMED"; body.attendance_record_id = fd.get("attendance_record_id"); body.attendance_confirmation_date = fd.get("attendance_confirmation_date"); }
    try {
      const r = await api("PATCH", "/api/v1/referrals/" + encodeURIComponent(f.dataset.id), body);
      const row = document.getElementById("ref-" + f.dataset.id);
      row.querySelector(".ref-status").replaceChildren(el("span", { class: "badge" }, r.referral_status), el("br"), el("span", { class: "small", text: r.status_label }));
      f.replaceWith(el("span", { class: "small", text: "✓ saved" }));
      say(r.referral_status);
    } catch (e) { alert(e.message); }
  }));
})();
