/* Admin: phone keys (shown once), revoke, website accounts. */
"use strict";
(function () {
  const kf = document.getElementById("key-form");
  if (kf) kf.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const fd = new FormData(kf);
    try {
      const r = await api("POST", "/api/v1/admin/phones", { worker_id: fd.get("worker_id"), label: fd.get("label") });
      document.getElementById("key-value").textContent = r.api_key;
      document.getElementById("key-url").textContent = r.server_url || "—";
      const box = document.getElementById("key-out"); box.hidden = false; box.focus();
      say("key created");
    } catch (e) { alert(e.message); }
  });
  document.querySelectorAll("button.revoke").forEach((b) => b.addEventListener("click", async () => {
    if (!confirm("Revoke this phone key? The phone stops syncing until it gets a new key.")) return;
    try { await api("POST", "/api/v1/admin/phones/" + encodeURIComponent(b.dataset.key) + "/revoke", {}); b.replaceWith(el("span", { class: "badge", text: "Revoked" })); say("revoked"); }
    catch (e) { alert(e.message); }
  }));
  document.querySelectorAll("button.toggle-user").forEach((b) => b.addEventListener("click", async () => {
    try { await api("PATCH", "/api/v1/admin/users/" + b.dataset.id, { is_active: b.dataset.active !== "true" }); location.reload(); }
    catch (e) { alert(e.message); }
  }));
  const uf = document.getElementById("user-form");
  if (uf) uf.addEventListener("submit", async (ev) => {
    ev.preventDefault();
    const fd = new FormData(uf);
    const body = { username: fd.get("username"), display_name: fd.get("display_name"), role: fd.get("role"), password: fd.get("password") };
    if (fd.get("worker_id")) body.worker_id = fd.get("worker_id");
    const msg = document.getElementById("user-msg");
    try { const u = await api("POST", "/api/v1/admin/users", body); msg.textContent = "✓ " + u.username; setTimeout(() => location.reload(), 600); }
    catch (e) { msg.textContent = "✖ " + e.message; }
  });
})();
