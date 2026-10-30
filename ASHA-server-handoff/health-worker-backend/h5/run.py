# -*- coding: utf-8 -*-
"""Writes the three submission files.

    python -m h5.run --split dev  --out submission_dev
    python -m h5.run --split test --out submission
"""
from __future__ import annotations

import argparse
import csv
import json
import resource
import sys
import time
from pathlib import Path

from .config import DATA, TODAY
from .pipeline import Assistant
from .visit_list import build_visit_list, load_register, write_visit_list


def peak_ram_mb() -> float:
    rss = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return round(rss / (1024 * 1024) if sys.platform == "darwin" else rss / 1024, 1)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--split", choices=["dev", "test"], default="dev")
    ap.add_argument("--out", default="submission")
    a = ap.parse_args(argv)
    out = Path(a.out)
    out.mkdir(parents=True, exist_ok=True)

    t_load = time.perf_counter()
    bot = Assistant()
    load_s = time.perf_counter() - t_load
    questions = list(csv.DictReader(open(DATA / f"questions_{a.split}.csv", encoding="utf-8")))
    answers = [bot.answer(q["question_id"], q["question_text"]) for q in questions]
    with open(out / "H5_answers.jsonl", "w", encoding="utf-8") as f:
        for r in answers:
            f.write(json.dumps({k: v for k, v in r.items() if not k.startswith("_")}, ensure_ascii=False) + "\n")

    rows = build_visit_list(load_register(DATA / "household_register.csv"), TODAY)
    write_visit_list(rows, out / "H5_visit_list.csv")

    lat = sorted(r["latency_ms"] for r in answers)
    footprint = {
        "model_names": ["none (rule engine + BM25 keyword retrieval; no neural model)"],
        "model_size_mb": 0.0,
        "protocol_text_kb": round(sum(len(s.text) for s in bot.sections.values()) / 1024, 1),
        "peak_ram_mb": peak_ram_mb(),
        "median_latency_ms_cpu": round(lat[len(lat) // 2], 3),
        "p95_latency_ms_cpu": round(lat[int(len(lat) * 0.95)], 3),
        "startup_s": round(load_s, 3),
        "offline": True,
    }
    (out / "H5_footprint.json").write_text(json.dumps(footprint, indent=2), encoding="utf-8")
    print(f"{a.split}: {len(answers)} answers, {len(rows)} visit-list rows -> {out}/  (median {footprint['median_latency_ms_cpu']} ms, peak RAM {footprint['peak_ram_mb']} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
