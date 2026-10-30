# -*- coding: utf-8 -*-
"""Turns the hackathon pack into the phone app's assets (health-worker-app/assets/h5/).

    H5_DATA=/path/to/pack/data python -m h5.export_assets --app ../health-worker-app

What it writes (all derived from the pack, none of it committed to git; see the README):
  rules.json       the concept lexicon, the Hinglish->English expansion, the document cues: the SAME words the Python engine uses
  protocols.json   the 107 leaf sections and their quotable sentences
  register.json    the household register (members), one compact row each
  households.json  the 500 households with village, ASHA, house number and a generated map position
  ashas.json       the five ASHAs and their villages
  maps/<village>.json   one small offline map pack per village (roads, landmarks, one point per house)
The house positions are GENERATED: the pack has no coordinates. Each village is a made-up street grid (not a real place) and houses are
laid out along it in house-number order, so neighbouring numbers are neighbours. The same seed always gives the same map."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import random
import re
from pathlib import Path

from .config import DATA, PROTOCOLS
from .expand import EXPAND
from .facts import compiled_source
from .lexicon import CONCEPTS
from .normalize import fold_pattern
from .protocols import load_sections
from .retrieve import _STOP

# the block's centre is made up too (central India); villages sit about 1 km from it
BLOCK_LAT, BLOCK_LNG = 22.3000, 80.1000
M_LAT = 1 / 111320.0


def slug(v: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", v.lower()).strip("-")


def village_layout(village: str, houses: list, index: int = 0) -> dict:
    """A fictional village: 5 east-west streets, 6 north-south lanes, a curved main road, and the houses along the streets.
    Villages sit on a 3 x 2 grid (1.2 km by 0.9 km apart, each about 0.66 km by 0.5 km) so no two of them overlap."""
    seed = int(hashlib.sha256(village.encode()).hexdigest()[:8], 16)
    rnd = random.Random(seed)
    col, row = index % 3, index // 3
    cx = (col - 1) * 1200 + rnd.uniform(-80, 80)
    cy = (row - 0.5) * 900 + rnd.uniform(-60, 60)
    lat0 = BLOCK_LAT + cy * M_LAT
    lng0 = BLOCK_LNG + cx * M_LAT / math.cos(math.radians(BLOCK_LAT))

    def ll(x: float, y: float):
        return [round(lat0 + y * M_LAT, 6), round(lng0 + x * M_LAT / math.cos(math.radians(lat0)), 6)]

    ew = [-200, -100, 0, 100, 200]
    ns = [-250, -150, -50, 50, 150, 250]
    roads = [{"n": f"Street {i + 1}", "k": 1, "p": [ll(-300, y), ll(300, y)]} for i, y in enumerate(ew)]
    roads += [{"n": f"Lane {i + 1}", "k": 1, "p": [ll(x, -240), ll(x, 240)]} for i, x in enumerate(ns)]
    roads.append({"n": "Main road", "k": 2, "p": [ll(-330 + i * 41, 18 * math.sin(i / 2.0) + 8) for i in range(17)]})

    # plots along the streets, west to east on each street, a little off the road, alternating sides
    plots = []
    for y in ew:
        for k, x in enumerate(range(-285, 286, 24)):
            side = 1 if k % 2 == 0 else -1
            plots.append((x + rnd.uniform(-3, 3), y + side * rnd.uniform(9, 14)))
    houses = sorted(houses, key=lambda h: (int(re.sub(r"\D", "", h["house_no"]) or 0), h["house_no"]))
    pos = {}
    for h, (x, y) in zip(houses, plots):
        pos[h["household_id"]] = ll(x, y)
    places = [
        {"n": "Anganwadi", "t": "anganwadi", "p": ll(-120, 100 + 30)},
        {"n": "School", "t": "school", "p": ll(170, -100 - 30)},
        {"n": "Temple", "t": "temple", "p": ll(0, 0 + 34)},
    ]
    lats = [p[0] for r in roads for p in r["p"]]
    lngs = [p[1] for r in roads for p in r["p"]]
    return {
        "v": 1, "id": "H5-" + slug(village).upper(), "name": village + " (made-up map, not a real place)",
        "bounds": [min(lats), min(lngs), max(lats), max(lngs)],
        "roads": roads, "places": places,
        "houses": [[hid] + p for hid, p in pos.items()],
    }, pos


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True, help="path to health-worker-app")
    a = ap.parse_args(argv)
    out = Path(a.app) / "assets" / "h5"
    (out / "maps").mkdir(parents=True, exist_ok=True)
    dump = lambda name, obj: (out / name).write_text(json.dumps(obj, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")

    # ---- rules (the exact compiled regex sources, so Dart cannot drift from Python)
    dump("rules.json", {
        "version": "1.0.0",
        "concepts": {k: [compiled_source(p) for p in v] for k, v in CONCEPTS.items()},
        "expand": EXPAND,
        "stop": sorted(_STOP),
    })

    # ---- protocols
    secs, local = load_sections(PROTOCOLS)
    dump("protocols.json", {
        "sections": [{"id": s.id, "doc": s.doc, "title": s.title, "group": s.group, "text": s.text, "units": s.units()} for s in secs.values()],
        "local_terms": local,
    })

    # ---- people and places
    reg = list(csv.DictReader(open(DATA / "household_register.csv", encoding="utf-8-sig", newline="")))
    cols = list(reg[0].keys())
    dump("register.json", {"cols": cols, "rows": [[r[c] for c in cols] for r in reg]})
    hh = list(csv.DictReader(open(DATA / "households.csv", encoding="utf-8-sig", newline="")))
    ashas = list(csv.DictReader(open(DATA / "ashas.csv", encoding="utf-8-sig", newline="")))
    by_village: dict = {}
    for h in hh:
        by_village.setdefault(h["village"], []).append(h)
    positions = {}
    villages = []
    for i, (v, houses) in enumerate(sorted(by_village.items())):
        pack, pos = village_layout(v, houses, i)
        positions.update(pos)
        (out / "maps" / f"{slug(v)}.json").write_text(json.dumps(pack, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        villages.append({"village": v, "slug": slug(v), "households": len(houses)})
    dump("households.json", [{
        "id": h["household_id"], "village": h["village"], "asha": h["asha_id"], "house_no": h["house_no"], "head": h["head_name"],
        "head_member": h["head_member_id"], "members": int(h["members_count"]), "lat": positions[h["household_id"]][0], "lng": positions[h["household_id"]][1],
    } for h in hh])
    dump("ashas.json", {"ashas": [{"id": r["asha_id"], "name": r["asha_name"], "villages": r["villages"].split(";")} for r in ashas], "villages": villages})
    size = sum(f.stat().st_size for f in out.rglob("*.json"))
    print(f"wrote {len(list(out.rglob('*.json')))} files to {out} ({size // 1024} KB): {len(secs)} sections, {len(reg)} members, {len(hh)} households, {len(villages)} village maps")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
