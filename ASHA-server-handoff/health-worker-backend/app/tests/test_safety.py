import json
import os

import pytest

from app.services.dataset_import.manifest import load
from app.services.safety.engine import SafetyEngine, get_engine
from app.services.safety.evaluation import evaluate_cases
from app.tests.conftest import DATASETS

CASES = load(DATASETS, "danger_sign_tests")


@pytest.mark.parametrize("case", CASES, ids=[c["test_id"] for c in CASES])
def test_every_supplied_safety_case(case):
    d = get_engine().evaluate(case["input_text"])
    assert d.status == case["expected_safety_status"], (case["input_text"], d.reasons)


def test_dataset_has_cases_and_positive_negative_balance():
    assert len(CASES) >= 100
    st = {c["expected_safety_status"] for c in CASES}
    assert st == {"ESCALATION_REQUIRED", "CLARIFICATION_REQUIRED", "NORMAL_PROTOCOL_QUERY", "OUT_OF_SCOPE"}


def test_false_negatives_and_false_positives_reported_separately():
    rep = evaluate_cases(CASES, get_engine())
    for split, r in rep["by_split"].items():
        assert r["false_negatives"] == [], (split, r["false_negatives"])       # synthetic-set target: 100% detection
        assert r["false_positives"] == [], (split, r["false_positives"])
    assert set(rep["by_split"]) >= {"ALL", "RULE_DEVELOPMENT", "FINAL_EVALUATION"}


def test_decision_records_ruleset_version_and_hash():
    d = get_engine().evaluate("Pregnant woman is bleeding heavily right now")
    assert d.status == "ESCALATION_REQUIRED" and d.rule_ids == ["DSR-BLEEDING-SEVERE"] and d.reasons
    assert d.ruleset_version and d.ruleset_sha256 and "UNREVIEWED" in d.ruleset_review_status


def test_negation_history_hypothetical_do_not_escalate():
    e = get_engine()
    assert e.evaluate("The pregnant woman has no fits").status == "NORMAL_PROTOCOL_QUERY"
    assert e.evaluate("She had heavy bleeding last month but is fine now").status == "NORMAL_PROTOCOL_QUERY"
    assert e.evaluate("What should I do if a woman has fits?").status == "NORMAL_PROTOCOL_QUERY"
    assert e.evaluate("no fits but she is bleeding heavily now").status == "ESCALATION_REQUIRED"      # mixed: current wins


def test_trailing_english_not_does_not_negate_earlier_symptom():
    assert get_engine().evaluate("she is having fits and not waking up").status == "ESCALATION_REQUIRED"


def test_ambiguous_and_short_route_to_clarification():
    e = get_engine()
    for t in ["she is not feeling well", "fits", "జ్వరం"]:
        assert e.evaluate(t).status == "CLARIFICATION_REQUIRED", t


def test_dosage_requests_are_out_of_scope():
    for t in ["What dose of amoxicillin should I give a child?", "పిల్లలకు యాంటీబయాటిక్ డోసు ఎంత?", "pillalaku antibiotic dose enta ivvali"]:
        assert get_engine().evaluate(t).status == "OUT_OF_SCOPE"


def test_ruleset_is_configurable_and_versioned(tmp_path):
    cfg = json.load(open(os.path.join(os.path.dirname(__import__("app.services.safety.engine", fromlist=["x"]).__file__), "rules", "danger_rules.json"), encoding="utf-8"))
    cfg["version"] = "9.9.9-test"
    cfg["rules"] = [r for r in cfg["rules"] if r["rule_id"] != "DSR-FITS"]
    p = tmp_path / "r.json"; p.write_text(json.dumps(cfg), encoding="utf-8")
    e = SafetyEngine(str(p))
    d = e.evaluate("she is having fits right now")
    assert d.ruleset_version == "9.9.9-test" and d.status != "ESCALATION_REQUIRED"
    assert e.sha256 != get_engine().sha256


def test_safety_module_does_not_depend_on_llm_or_retrieval():
    import app.services.safety.engine as m
    src = open(m.__file__, encoding="utf-8").read()
    assert "retrieval" not in src and "openai" not in src.lower() and "anthropic" not in src.lower()
