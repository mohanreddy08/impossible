/* Village map drawn as SVG from the GENERATED street layout (no map service, no tiles, works offline on the LAN).
   Houses: colour AND shape AND label say the urgency (▲ urgent, ■ due, ◆ this week, ● nothing due). */
"use strict";
(function () {
  const box = document.getElementById("map");
  if (!box || !box.dataset.village) return;
  const SVGNS = "http://www.w3.org/2000/svg";
  const COLORS = { URGENT: "#b3261e", DUE: "#a14a07", THIS_WEEK: "#1d4ed8", NONE: "#15803d" };
  const ICON = { URGENT: "▲", DUE: "■", THIS_WEEK: "◆", NONE: "●" };
  const L = (k) => box.dataset["l" + k.toLowerCase().replace(/_(.)/g, (m, c) => c.toUpperCase()).replace(/^./, (c) => c.toUpperCase())] || k;
  const label = (u) => box.dataset["l" + { URGENT: "Urgent", DUE: "Due", THIS_WEEK: "This_week", NONE: "None" }[u]] || u;
  const mini = box.dataset.mini === "1";
  const focusId = box.dataset.focus || null;
  const panel = document.getElementById("house-panel");

  function s(tag, attrs) { const n = document.createElementNS(SVGNS, tag); for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, v); return n; }

  function shape(u, x, y, r) {
    if (u === "URGENT") return s("polygon", { points: `${x},${y - r * 1.25} ${x + r * 1.15},${y + r * 0.85} ${x - r * 1.15},${y + r * 0.85}` });
    if (u === "DUE") return s("rect", { x: x - r, y: y - r, width: r * 2, height: r * 2 });
    if (u === "THIS_WEEK") return s("polygon", { points: `${x},${y - r * 1.3} ${x + r * 1.3},${y} ${x},${y + r * 1.3} ${x - r * 1.3},${y}` });
    return s("circle", { cx: x, cy: y, r: r });
  }

  async function openHouse(id, node) {
    document.querySelectorAll(".house.sel").forEach((n) => n.classList.remove("sel"));
    if (node) node.classList.add("sel");
    if (!panel) { location.href = "/households/" + encodeURIComponent(id); return; }
    panel.hidden = false;
    panel.replaceChildren(el("p", { text: box.dataset.loading }));
    try {
      const h = await api("GET", "/api/v1/dashboard/households/" + encodeURIComponent(id));
      const kids = [
        el("h2", { id: "panel-title", tabindex: "-1" }, (h.house_no || h.household_id) + " · " + (h.head_name || "")),
        el("p", {}, el("span", { class: "badge u-" + h.urgency.toLowerCase() }, ICON[h.urgency] + " " + label(h.urgency)), " ", h.village_name + " · " + h.asha_name),
        el("h3", { text: L("members") + " (" + h.members.length + ")" }),
        el("ul", { class: "plain" }, ...h.members.map((m) => el("li", {}, m.name + " · " + (m.relation || "") + " · " + (m.age || "")))),
        el("h3", { text: L("dueitems") + " (" + h.due_items.length + ")" }),
        el("ul", { class: "chips" }, ...h.due_items.map((d) => el("li", { class: "chip u-" + d.urgency.toLowerCase() },
          ICON[d.urgency] + " " + d.due_item + " · " + d.name + " · " + d.status.replace(/_/g, " ") + " · " + d.due_date))),
        el("p", {}, el("a", { class: "btn", href: "/households/" + encodeURIComponent(h.household_id), id: "open-household" }, L("open"))),
      ];
      panel.replaceChildren(...kids);
      document.getElementById("panel-title").focus();
      say((h.house_no || h.household_id) + ", " + label(h.urgency));
    } catch (e) {
      panel.replaceChildren(el("p", { class: "alert alert-err", text: box.dataset.error }));
    }
  }

  function draw(m) {
    const [minLat, minLng, maxLat, maxLng] = m.bounds;
    const k = Math.cos(((minLat + maxLat) / 2) * Math.PI / 180);
    const pad = 18, W = 900;
    const H = Math.round(W * (maxLat - minLat) / ((maxLng - minLng) * k)) + 2 * pad;
    const X = (lng) => pad + (lng - minLng) / (maxLng - minLng) * (W - 2 * pad);
    const Y = (lat) => pad + (maxLat - lat) / (maxLat - minLat) * (H - 2 * pad);
    let vb = `0 0 ${W} ${H}`;
    if (mini && focusId) {
      const f = m.houses.find((h) => h.household_id === focusId);
      if (f) { const cx = X(f.lng), cy = Y(f.lat); vb = `${Math.max(0, cx - 160)} ${Math.max(0, cy - 100)} 320 200`; }
    }
    const svg = s("svg", { viewBox: vb, role: "group", "aria-label": m.name + " — " + box.dataset.lMadeUp });
    svg.append(s("rect", { x: 0, y: 0, width: W, height: H, fill: "#fbfaf5" }));
    for (const r of m.roads) {
      svg.append(s("polyline", { class: "road" + (r.k === 2 ? " main" : ""), "stroke-width": r.k === 2 ? 9 : 6, points: r.p.map((p) => X(p[1]) + "," + Y(p[0])).join(" ") }));
    }
    for (const p of m.places) {
      const t = s("text", { class: "place", x: X(p.p[1]) + 6, y: Y(p.p[0]) + 4 }); t.textContent = "✚ " + p.n; svg.append(t);
    }
    const counts = {};
    for (const h of m.houses) {
      counts[h.urgency] = (counts[h.urgency] || 0) + 1;
      const g = shape(h.urgency, X(h.lng), Y(h.lat), h.household_id === focusId ? 9 : 6);
      g.setAttribute("class", "house" + (h.household_id === focusId ? " sel" : ""));
      g.setAttribute("fill", COLORS[h.urgency]);
      g.setAttribute("data-id", h.household_id);
      if (!mini) {
        g.setAttribute("tabindex", "0");
        g.setAttribute("role", "button");
        g.setAttribute("aria-label", (h.house_no || h.household_id) + ", " + (h.head_name || "") + ", " + label(h.urgency));
        g.addEventListener("click", () => openHouse(h.household_id, g));
        g.addEventListener("keydown", (ev) => { if (ev.key === "Enter" || ev.key === " ") { ev.preventDefault(); openHouse(h.household_id, g); } });
      }
      const ttl = s("title", {}); ttl.textContent = (h.house_no || h.household_id) + " · " + (h.head_name || "") + " · " + label(h.urgency); g.append(ttl);
      svg.append(g);
    }
    const mu = s("text", { class: "made-up", x: 8, y: H - 8 }); mu.textContent = "⚠ " + box.dataset.lMadeUp; svg.append(mu);
    box.replaceChildren(svg);
    document.querySelectorAll("[data-count]").forEach((n) => { n.textContent = "(" + (counts[n.dataset.count] || 0) + ")"; });
    const list = document.getElementById("house-list");
    if (list) {
      list.replaceChildren(...m.houses.slice().sort((a, b) => (a.house_no || "").localeCompare(b.house_no || "", undefined, { numeric: true }))
        .map((h) => el("li", {}, el("a", { href: "/households/" + encodeURIComponent(h.household_id) }, (h.house_no || h.household_id) + " · " + (h.head_name || "")),
          " ", el("span", { class: "badge u-" + h.urgency.toLowerCase() }, ICON[h.urgency] + " " + label(h.urgency)))));
    }
    const un = document.getElementById("unplaced");
    if (un && m.unplaced.length) {
      document.getElementById("unplaced-wrap").hidden = false;
      un.replaceChildren(...m.unplaced.map((h) => el("li", {}, el("a", { href: "/households/" + encodeURIComponent(h.household_id) }, h.household_id),
        " ", el("span", { class: "badge u-" + h.urgency.toLowerCase() }, ICON[h.urgency] + " " + label(h.urgency)))));
    }
  }

  api("GET", "/api/v1/dashboard/map/" + encodeURIComponent(box.dataset.village)).then(draw)
    .catch(() => box.replaceChildren(el("p", { class: "alert alert-err", text: box.dataset.error })));
  const sel = document.getElementById("village");
  if (sel && sel.form) sel.addEventListener("change", () => sel.form.submit());
})();
