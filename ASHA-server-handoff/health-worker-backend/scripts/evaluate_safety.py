#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import get_settings
from app.services.dataset_import.manifest import load
from app.services.safety.engine import SafetyEngine
from app.services.safety.evaluation import evaluate_cases

r = evaluate_cases(load(get_settings().resolved_dataset_dir, "danger_sign_tests"), SafetyEngine())
for k, v in r["by_split"].items():
    print(k, {x: v[x] for x in ("cases", "exact_status_accuracy", "escalation_positives", "escalation_detected", "escalation_recall")},
          "FN=%d FP=%d other=%d" % (len(v["false_negatives"]), len(v["false_positives"]), len(v["other_mismatches"])))
    for w in v["false_negatives"] + v["false_positives"] + v["other_mismatches"]:
        if k == "ALL": print("   ", w)
json.dump(r, open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "safety_evaluation.json"), "w"), indent=2, ensure_ascii=False)
