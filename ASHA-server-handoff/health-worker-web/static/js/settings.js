/* Settings: is the public address answering (checked by the server, through the tunnel and back)? Admin settings form. */
"use strict";
(function () {
  const pub = document.getElementById("public");
  const st = document.getElementById("pub-status");
  async function check() {
    st.replaceChildren(el("span", { class: "badge", text: "…" }));
    try {
      const r = await api("GET", "/api/v1/admin/server-info?check=true");
      const ok = r.reachable === true, bad = r.reachable === false;
      st.replaceChildren(el("span", { class: "badge " + (ok ? "u-none" : bad ? "u-urgent" : "") },
        (ok ? "✓ " + pub.dataset.lOk : bad ? "✖ " + pub.dataset.lBad : "? " + pub.dataset.lUnknown)), " ", el("span", { class: "small muted", text: r.detail || "" }));
    } catch (e) { st.textContent = e.message; }
  }
  const b = document.getElementById("check");
  if (b) b.addEventListener("click", check);
  if (document.getElementById("pub-url") && document.getElementById("pub-url").classList.contains("mono")) check();
  const f = document.getElementById("settings-form");
  if (f) f.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const fd = new FormData(f);
    const body = { retention_days: Number(fd.get("retention_days")), public_url: fd.get("public_url") || "", default_language: fd.get("default_language") };
    const msg = document.getElementById("settings-msg");
    try { await api("PATCH", "/api/v1/admin/settings", body); msg.textContent = "✓"; setTimeout(() => location.reload(), 500); }
    catch (e) { msg.textContent = "✖ " + e.message; }
  });
})();
