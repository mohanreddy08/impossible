# -*- coding: utf-8 -*-
"""Per-question report against a truth file (development aid; the official scorer is evaluate.py).

    python -m h5.diagnose --truth /path/to/data/dev_truth.jsonl --answers submission_dev/H5_answers.jsonl [--only fail]
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path

from .config import DATA


def norm(t: str) -> str:
    t = (t or "").lower()
    for a, b in (("–", "-"), ("—", "-"), ("−", "-"), ("≥", ">="), ("≤", "<="), ("°", " ")):
        t = t.replace(a, b)
    t = re.sub(r"(?<=\d)(?=[a-z])", " ", t)
    t = re.sub(r"(?<=\d)\s*-\s*(?=\d)", "-", t)
    return re.sub(r"\s+", " ", t).strip()


def fact_in(fact: str, text: str) -> bool:
    f = norm(fact)
    return bool(f) and re.search(r"(?<![a-z0-9])" + re.escape(f) + r"(?![a-z0-9])", norm(text)) is not None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--truth", required=True)
    ap.add_argument("--answers", required=True)
    ap.add_argument("--questions", default=None)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    truth = [json.loads(l) for l in open(a.truth, encoding="utf-8") if l.strip()]
    ans = {json.loads(l)["question_id"]: json.loads(l) for l in open(a.answers, encoding="utf-8") if l.strip()}
    qfile = a.questions or str(Path(a.truth).parent / "questions_dev.csv")
    qtext = {r["question_id"]: r["question_text"] for r in csv.DictReader(open(qfile, encoding="utf-8"))}
    bad = 0
    for i, t in enumerate(truth):
        r = ans[t["question_id"]]
        esc, oos = t["must_escalate"], t["out_of_scope"]
        probs = []
        if esc and not r["escalate"]:
            probs.append("MISSED ESCALATION")
        if not esc and r["escalate"]:
            probs.append("false escalation")
        if not esc and r["refused"] != oos:
            probs.append("refusal wrong (truth oos=%s, we refused=%s)" % (oos, r["refused"]))
        if not oos:
            blocked = (not esc) and (r["refused"] or r["escalate"])
            exp = {e.upper() for e in t["expected_section_ids"]}
            cited = [c.upper() for c in r["cited_section_ids"]]
            if blocked:
                probs.append("TURNED AWAY (in scope)")
            elif not any(c in exp for c in cited) or len(cited) > 2:
                probs.append("citation: expected %s got %s" % (sorted(exp), cited))
            facts = t.get("key_fact_alternatives") or [[x] for x in t.get("key_facts", [])]
            miss = [alts[0] for alts in facts if not any(fact_in(x, r["answer_text"][:400]) for x in alts)]
            if miss and not blocked:
                probs.append("key facts missing: %s" % miss)
        if probs:
            bad += 1
        if a.only == "fail" and not probs:
            continue
        print(f"{i:3d} [{t['category']}] {' | '.join(probs) if probs else 'ok'}")
        if probs:
            print(f"      Q: {qtext.get(t['question_id'], '')[:110]}")
            print(f"      A: {r['answer_text'][:170]}")
    print(f"\n{bad} of {len(truth)} questions have a problem")
    return 0


if __name__ == "__main__":
    sys.exit(main())
