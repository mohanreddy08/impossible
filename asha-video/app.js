// Deterministic timeline: window.render(t) draws the frame at time t (seconds).
// No CSS transitions or real-time animation: every style is a pure function of t.
(function () {
  const SCENES = [
    [1, 0, 12], [2, 12, 24], [3, 24, 34], [4, 34, 58], [5, 58, 80], [6, 80, 98],
    [7, 98, 116], [8, 116, 140], [9, 140, 158], [10, 158, 170], [11, 170, 180],
  ];
  const T_IN = 0.45, T_OUT = 0.35;
  const clamp = (x) => Math.max(0, Math.min(1, x));
  const easeOut = (x) => 1 - Math.pow(1 - x, 3);
  const backOut = (x) => { const c = 1.6; return 1 + (c + 1) * Math.pow(x - 1, 3) + c * Math.pow(x - 1, 2); };
  const prog = (lt, a, d) => clamp((lt - a) / d);
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => Array.from(r.querySelectorAll(s));

  let CUES = {};
  const sfx = [];
  const scenes = [];

  // "c2+0.5" -> local seconds (cue 2 start of this scene + 0.5); "e2" = cue 2 end
  function resolve(expr, sid, start) {
    if (expr == null || expr === "") return null;
    const js = expr.replace(/([ce])(\d+)/g, (_, k, i) => {
      const c = CUES[sid][+i];
      return "(" + ((k === "c" ? c[0] : c[1]) - start) + ")";
    });
    return Function("return " + js)();
  }

  function init(cues) {
    CUES = cues;
    const stage = $("#stage");
    for (const [sid, start, end] of SCENES) {
      const root = $("#s" + sid);
      root.style.visibility = "visible";
      const sc = { sid, start, end, root, anim: [], taps: [], cnt: [] };
      for (const el of $$("[data-in],[data-out]", root)) {
        el._in = resolve(el.dataset.in, sid, start);
        el._out = resolve(el.dataset.out, sid, start);
        el._a = el.dataset.a || "up";
        el._d = parseFloat(el.dataset.d || (el._a === "pop" ? 0.45 : 0.4));
        sc.anim.push(el);
        if (el.hasAttribute("data-whoosh")) sfx.push({ t: start + el._in, type: "whoosh" });
      }
      // taps: ripple at element centre + click sound
      const sr = root.getBoundingClientRect();
      for (const el of $$("[data-tap]", root)) for (const expr of el.dataset.tap.split(",")) {
        const at = resolve(expr, sid, start);
        const r = el.getBoundingClientRect();
        const rp = document.createElement("div");
        rp.className = "ripple";
        rp.style.left = r.left - sr.left + r.width / 2 + "px";
        rp.style.top = r.top - sr.top + r.height / 2 + "px";
        root.appendChild(rp);
        sc.taps.push({ el, at, rp });
        sfx.push({ t: start + at, type: "click" });
      }
      for (const el of $$(".cnt", root)) {
        sc.cnt.push({ el, to: +el.dataset.to, at: resolve(el.dataset.at, sid, start), dur: parseFloat(el.dataset.dur || 1.0) });
      }
      root.style.visibility = "hidden";
      scenes.push(sc);
    }
    HOOKS.init();
    sfx.sort((a, b) => a.t - b.t);
    window.SFX = sfx;
  }

  function applyAnim(el, lt) {
    const v = el._in == null ? 1 : prog(lt, el._in, el._d);
    const o = el._out == null ? 0 : prog(lt, el._out, 0.3);
    const vis = v * (1 - o);
    const ev = easeOut(v), eo = easeOut(o);
    let tr = "none", sc = "none";
    switch (el._a) {
      case "up": tr = `0 ${(1 - ev) * 46 - eo * 24}px`; break;
      case "down": tr = `0 ${-(1 - ev) * 120}px`; break;
      case "left": tr = `${-(1 - ev) * 80}px 0`; break;
      case "right": tr = `${(1 - ev) * 80}px 0`; break;
      case "slide": tr = `${(1 - ev) * 480 - eo * 160}px 0`; break;
      case "pop": sc = `${0.7 + 0.3 * backOut(v) - eo * 0.05}`; break;
    }
    el.style.opacity = el._a === "slide" ? (v > 0 ? 1 - eo : 0) : vis;
    el.style.translate = tr;
    el.style.scale = sc;
    const hidden = (el._a === "slide" ? (v <= 0 || o >= 1) : vis <= 0.001);
    el.style.visibility = hidden ? "hidden" : "";
    if (el.hasAttribute("data-collapse")) el.style.display = hidden ? "none" : "";
  }

  function render(t) {
    for (const sc of scenes) {
      const last = sc.sid === 11;
      const vis = t >= sc.start - 0.001 && (last || t < sc.end + T_OUT);
      if (!vis) { sc.root.style.visibility = "hidden"; continue; }
      const lt = t - sc.start;
      const pin = sc.sid === 1 ? 1 : easeOut(prog(lt, 0, T_IN));
      const pout = last ? 0 : easeOut(prog(t, sc.end, T_OUT));
      sc.root.style.visibility = "visible";
      sc.root.style.opacity = Math.min(pin, 1 - pout);
      sc.root.style.translate = `${(1 - pin) * 70 - pout * 70}px 0`;
      for (const el of sc.anim) applyAnim(el, lt);
      for (const tp of sc.taps) {
        const p = prog(lt, tp.at, 0.5);
        tp.rp.style.opacity = p > 0 && p < 1 ? 0.75 * (1 - p) : 0;
        tp.rp.style.scale = 0.4 + 1.3 * easeOut(p);
      }
      for (const tp of sc.taps) if (tp.el._a === undefined) tp.el.style.scale = "";
      for (const tp of sc.taps) if (lt >= tp.at && lt < tp.at + 0.18) tp.el.style.scale = 0.95;
      for (const c of sc.cnt) {
        const p = easeOut(prog(lt, c.at, c.dur));
        c.el.textContent = Math.round(c.to * p);
      }
      const h = HOOKS["s" + sc.sid];
      if (h) h(lt, sc);
    }
    // ambient background drift
    $(".g1").style.translate = `${Math.sin(t / 9) * 60}px ${Math.cos(t / 11) * 40}px`;
    $(".g2").style.translate = `${Math.cos(t / 13) * 60}px ${Math.sin(t / 7) * 30}px`;
  }

  // ---------- scene-specific hooks ----------
  const L = (sid, i, k = 0) => CUES[sid][i][k] - SCENES[sid - 1][1];
  function typeText(el, text, lt, a, b) {
    const n = Math.round(text.length * clamp((lt - a) / (b - a)));
    el.textContent = text.slice(0, n);
  }
  const blink = (lt) => (Math.floor(lt * 2.2) % 2 === 0 ? 1 : 0);

  const HOOKS = {
    init() {
      // scene 5 timeline (local seconds)
      const s5 = (i, k = 0) => L(5, i, k);
      HOOKS.k5 = {
        tapMic: s5(0) + 2.4, words0: s5(1) - 0.1, words1: s5(1) + 1.3, micOff: s5(1) + 1.6,
        fix: s5(2) + 1.1, check: s5(2) + 2.2, ans: s5(2) + 2.55,
        q2a: s5(4) + 2.5, q2b: s5(4) + 3.6, check2: s5(4) + 3.9, ref: s5(4) + 4.15,
      };
      const k = HOOKS.k5;
      HOOKS.s5words = $$("#s5q1 .w");
      // scene 4 settings voice-pack tap, scene 1 alert
      sfx.push({ t: 34 + L(4, 6) + 0.6, type: "click" });
    },
    s1(lt) {
      const bars = $$("#s1bars i");
      const drop = (i) => prog(lt, 0.6 + (3 - i) * 0.55, 0.45); // top bar falls first
      bars.forEach((b, i) => {
        const p = easeOut(drop(i));
        b.style.opacity = 1 - 0.82 * p;
        b.style.background = p > 0.5 ? "#334155" : "#14B8A6";
        b.style.scale = `1 ${1 - 0.15 * p}`;
        b.style.transformOrigin = "bottom";
      });
      const lvl = 4 - bars.filter((_, i) => drop(i) > 0.5).length;
      const txt = $("#s1sigtxt");
      txt.textContent = ["", "Weak signal", "Weak signal", "3G", "4G"][lvl] || "";
      txt.style.opacity = lt < 3.0 ? 1 : 0;
      const d = $("#s1drop");
      d.style.boxShadow = `0 0 0 ${10 + 14 * Math.abs(Math.sin(lt * 2.4))}px rgba(220,38,38,.28)`;
    },
    s4(lt) {
      const a = L(4, 6) + 0.6;
      $("#s4prog").style.width = 100 * easeOut(prog(lt, a, 1.4)) + "%";
      // phone slides left a little when the tablet joins
      const p = easeOut(prog(lt, L(4, 7) - 0.1, 0.45));
      $("#s4phone").style.translate = `${-90 * p}px ${60 * p}px`;
      $("#s4phone").style.scale = 1 - 0.18 * p;
    },
    s5(lt) {
      const k = HOOKS.k5;
      const listening = lt >= k.tapMic && lt < k.micOff;
      const mic = $("#s5mic");
      mic.style.background = listening ? "#DC2626" : "";
      mic.style.boxShadow = listening ? "0 12px 30px rgba(220,38,38,.45)" : "";
      const ml = $("#s5micl");
      ml.textContent = listening ? "Listening… speak now" : "Speak";
      ml.style.color = listening ? "#DC2626" : "";
      ["#s5r1", "#s5r2"].forEach((s, i) => {
        const ph = ((lt - k.tapMic) * 0.9 + i * 0.5) % 1;
        $(s).style.opacity = listening ? 0.7 * (1 - ph) : 0;
        $(s).style.scale = 1 + 0.7 * ph;
      });
      $("#s5check").style.background = (lt >= k.check && lt < k.check + 0.3) || (lt >= k.check2 && lt < k.check2 + 0.3) ? "#0B5E58" : "";
      // words appear one by one
      const ws = HOOKS.s5words;
      const q1on = lt >= k.words0 && lt < k.q2a - 0.2;
      $("#s5q1").style.display = q1on ? "" : "none";
      ws.forEach((w, i) => {
        const at = k.words0 + (i / ws.length) * (k.words1 - k.words0);
        w.style.opacity = clamp((lt - at) / 0.15);
      });
      const fixed = lt >= k.fix;
      $("#s5bad").style.display = fixed ? "none" : "";
      $("#s5good").style.display = fixed ? "" : "none";
      $("#s5bad").style.background = !fixed && lt > k.fix - 0.9 ? "rgba(220,38,38,.12)" : "";
      $("#s5good").style.opacity = clamp((lt - k.fix) / 0.2);
      $("#s5ph").style.display = lt < k.words0 ? "" : "none";
      $("#s5hint").style.opacity = clamp((lt - k.words1) / 0.3) * (lt < k.check ? 1 : 0);
      // second question typed
      typeText($("#s5q2"), "Paracetamol dose for a baby?", lt, k.q2a, k.q2b);
      $("#s5q2").style.display = lt >= k.q2a - 0.2 ? "" : "none";
      $("#s5caret").style.opacity = (lt >= k.q2a - 0.2 && lt < k.check2) ? blink(lt) : 0;
      // answer sheets slide up
      const sa = easeOut(prog(lt, k.ans, 0.4)) * (1 - easeOut(prog(lt, k.q2a - 0.3, 0.3)));
      $("#s5ans").style.translate = `0 ${(1 - sa) * 110}%`;
      const sr = easeOut(prog(lt, k.ref, 0.4));
      $("#s5ref").style.translate = `0 ${(1 - sr) * 110}%`;
    },
    s6(lt) {
      const a = L(6, 1) + 0.25, b = a + 1.6;
      typeText($("#s6q"), "bleeding in third trimester", lt, a, b);
      $("#s6caret").style.opacity = lt < L(6, 2) - 0.15 ? blink(lt) : 0;
      // dot travels: box1 -> rules -> alert
      const d0 = L(6, 2) - 0.6;
      const p = easeOut(prog(lt, d0, 1.1));
      const x = 101 + p * 600; // centre of p1 -> centre of p3
      const dot = $("#pdot");
      dot.style.left = x + "px";
      dot.style.opacity = lt > d0 - 0.1 && lt < d0 + 1.6 ? 1 : 0;
      dot.style.background = p > 0.85 ? "#DC2626" : "";
      $("#p2").style.background = p > 0.35 && p < 0.9 ? "rgba(20,184,166,.25)" : "";
      $("#p3").style.background = p >= 0.95 ? "rgba(220,38,38,.3)" : "";
      // footnote emphasis when the clinician line is spoken
      const f = $("#s6foot");
      const e = prog(lt, L(6, 4), 0.3);
      f.style.borderColor = e > 0 ? "#F59E0B" : "";
      f.style.color = e > 0 ? "#FDE68A" : "";
    },
    s7(lt) {
      // after the tool-note, shrink the diagram to make room for the rules
      const p = easeOut(prog(lt, L(7, 2) - 0.4, 0.5));
      const arch = $("#s7arch");
      arch.style.scale = 1 - 0.12 * p;
      arch.style.translate = `0 ${-40 * p}px`;
    },
    s8(lt) {
      const p = prog(lt, L(8, 3) + 0.4, 0.3);
      $("#s8vosk").style.opacity = Math.min(parseFloat($("#s8vosk").style.opacity || 1), 1 - 0.45 * p);
    },
  };

  window.init = init;
  window.render = render;
})();
