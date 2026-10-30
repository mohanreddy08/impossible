"""Run the engine over danger_sign_tests and report confusion, false positives and false negatives separately."""
from collections import Counter, defaultdict
from typing import Dict, List

from app.services.safety.engine import SafetyEngine


def evaluate_cases(cases: List[dict], engine: SafetyEngine) -> Dict:
    out = dict(total=len(cases), by_split={}, ruleset_version=engine.cfg["version"], ruleset_review_status=engine.cfg["review_status"])
    groups = defaultdict(list)
    for c in cases:
        groups[c.get("split", "ALL")].append(c)
        groups["ALL"].append(c)
    for name, items in groups.items():
        conf, fn, fp, wrong = Counter(), [], [], []
        pos = tp = 0
        for c in items:
            d = engine.evaluate(c["input_text"])
            exp, got = c["expected_safety_status"], d.status
            conf[(exp, got)] += 1
            if exp == "ESCALATION_REQUIRED":
                pos += 1
                tp += got == "ESCALATION_REQUIRED"
                if got != "ESCALATION_REQUIRED":
                    fn.append(dict(test_id=c["test_id"], text=c["input_text"], expected=exp, got=got, scenario=c["scenario_type"]))
            elif got == "ESCALATION_REQUIRED":
                fp.append(dict(test_id=c["test_id"], text=c["input_text"], expected=exp, got=got, scenario=c["scenario_type"]))
            if exp != got:
                wrong.append(dict(test_id=c["test_id"], text=c["input_text"], expected=exp, got=got, scenario=c["scenario_type"]))
        out["by_split"][name] = dict(
            cases=len(items), exact_status_matches=len(items) - len(wrong), exact_status_accuracy=round((len(items) - len(wrong)) / max(1, len(items)), 4),
            escalation_positives=pos, escalation_detected=tp, escalation_recall=round(tp / pos, 4) if pos else None,
            false_negatives=fn, false_positives=fp, other_mismatches=[w for w in wrong if w not in fn and w not in fp],
            confusion={"%s->%s" % k: v for k, v in sorted(conf.items())})
    return out
