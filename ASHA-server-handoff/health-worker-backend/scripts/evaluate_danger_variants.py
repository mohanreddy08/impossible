#!/usr/bin/env python3
"""Spoken, misspelled and transliterated danger-sign phrasings (eval/danger_variants.jsonl): every ESC line must escalate (100% needed),
OOS lines must be refused, OK lines (negated / harmless) must not escalate. Prints every miss; exit 1 on any."""
import json, os, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)
from app.services.safety.engine import SafetyEngine
M = {"ESC": "ESCALATION_REQUIRED", "OOS": "OUT_OF_SCOPE", "OK": "NORMAL_PROTOCOL_QUERY"}
e = SafetyEngine()
rows = [json.loads(l) for l in open(os.path.join(ROOT, "eval", "danger_variants.jsonl"), encoding="utf-8") if l.strip()]
bad = [(r, e.evaluate(r["t"]).status) for r in rows if e.evaluate(r["t"]).status != M[r["e"]]]
esc = [r for r in rows if r["e"] == "ESC"]
print("escalation detected %d/%d; all cases correct %d/%d" % (len(esc) - sum(1 for r, _ in bad if r["e"] == "ESC"), len(esc), len(rows) - len(bad), len(rows)))
for r, got in bad:
    print("  MISS expected %s got %s | %s" % (r["e"], got, r["t"]))
sys.exit(1 if bad else 0)
