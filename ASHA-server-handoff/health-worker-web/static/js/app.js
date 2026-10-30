/* Shared helpers. All JSON calls go to the same origin with the session cookie and the X-Requested-With header (CSRF guard). */
"use strict";
window.api = async function api(method, url, body) {
  const opt = { method, credentials: "same-origin", headers: { "X-Requested-With": "fetch", "Accept": "application/json" } };
  if (body !== undefined) { opt.headers["Content-Type"] = "application/json"; opt.body = JSON.stringify(body); }
  const r = await fetch(url, opt);
  let data = null;
  try { data = await r.json(); } catch (e) { data = null; }
  if (r.status === 401) { window.location.href = "/login?next=" + encodeURIComponent(location.pathname + location.search); }
  if (!r.ok) { const e = new Error((data && data.error && data.error.message) || ("HTTP " + r.status)); e.status = r.status; e.data = data; throw e; }
  return data;
};
window.say = function say(text) { const l = document.getElementById("live"); if (l) { l.textContent = ""; setTimeout(() => { l.textContent = text; }, 30); } };
window.el = function el(tag, attrs, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === null || v === undefined || v === false) continue;
    if (k === "class") n.className = v; else if (k === "text") n.textContent = v; else n.setAttribute(k, v === true ? "" : v);
  }
  for (const c of kids) if (c !== null && c !== undefined) n.append(c.nodeType ? c : document.createTextNode(String(c)));
  return n;
};
document.addEventListener("DOMContentLoaded", () => {
  const nav = document.getElementById("navwrap");
  if (nav && window.matchMedia("(min-width: 1000px)").matches) nav.open = true;
  // whole table rows open the household (the name cell keeps a real link for keyboard and screen readers)
  document.querySelectorAll("tr[data-href]").forEach((tr) => {
    tr.addEventListener("click", (ev) => { if (!ev.target.closest("a,button,input,select")) location.href = tr.dataset.href; });
  });
});
