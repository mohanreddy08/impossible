/* Ask the protocol: POST /api/v1/ask. Danger signs get a red REFER IMMEDIATELY card (never an "answer"); out-of-scope gets a refusal card. */
"use strict";
(function () {
  const f = document.getElementById("ask-form");
  if (!f) return;
  const out = document.getElementById("ask-result");
  const q = document.getElementById("question");
  const btn = document.getElementById("ask-btn");
  const d = f.dataset;
  document.querySelectorAll("button.ex").forEach((b) => b.addEventListener("click", () => { q.value = b.textContent; q.focus(); }));
  f.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const text = q.value.trim();
    if (!text) return;
    btn.disabled = true;
    try {
      const r = await api("POST", "/api/v1/ask", { question: text });
      const cites = el("p", { class: "small" }, d.lCited + ": ", ...r.citations.map((c, i) => el("span", { class: "tag", "data-section": c.section_id },
        c.section_id + (c.title ? " — " + c.title : ""))).flatMap((x, i) => i ? [" ", x] : [x]));
      let card;
      if (r.escalate) {
        card = el("div", { class: "result-card refer", role: "alert", id: "result-refer" },
          el("h2", {}, el("span", { "aria-hidden": "true" }, "▲ "), d.lRefer), el("p", { text: d.lReferNote }), el("p", { text: r.answer_text }), cites);
      } else if (r.refused) {
        card = el("div", { class: "result-card refused", id: "result-refused" },
          el("h2", {}, el("span", { "aria-hidden": "true" }, "⊘ "), d.lRefused), el("p", { text: d.lRefusedNote }), el("p", { text: r.answer_text }), cites);
      } else {
        card = el("div", { class: "result-card answer", id: "result-answer" },
          el("h2", {}, el("span", { "aria-hidden": "true" }, "✓ "), d.lAnswer), el("p", { text: r.answer_text }), cites);
      }
      card.append(el("p", { class: "assist", text: "⚕ " + d.lAssist }));
      out.replaceChildren(card);
      say(r.escalate ? d.lRefer : r.refused ? d.lRefused : d.lAnswer);
    } catch (e) {
      out.replaceChildren(el("p", { class: "alert alert-err", role: "alert", text: d.lError + " (" + e.message + ")" }));
    } finally { btn.disabled = false; }
  });
})();
