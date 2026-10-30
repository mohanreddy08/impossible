import json, os

from app.services.safety.engine import SafetyEngine

_M = {"ESC": "ESCALATION_REQUIRED", "OOS": "OUT_OF_SCOPE", "OK": "NORMAL_PROTOCOL_QUERY"}
_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "eval", "danger_variants.jsonl")


def test_every_spoken_misspelled_and_transliterated_danger_phrase_escalates():
    e = SafetyEngine()
    rows = [json.loads(l) for l in open(_PATH, encoding="utf-8") if l.strip()]
    assert len(rows) >= 80
    wrong = [(r["t"], e.evaluate(r["t"]).status) for r in rows if e.evaluate(r["t"]).status != _M[r["e"]]]
    assert wrong == []


def test_any_bleeding_in_pregnancy_or_after_delivery_escalates_but_a_negation_does_not():
    e = SafetyEngine()
    for t in ["bleeding in third trimester", "bleeding during pregnancy", "ప్రసవం తర్వాత రక్తస్రావం"]:
        assert e.evaluate(t).status == "ESCALATION_REQUIRED", t
    for t in ["The pregnant woman is not bleeding.", "గర్భిణీకి రక్తస్రావం లేదు"]:
        assert e.evaluate(t).status == "NORMAL_PROTOCOL_QUERY", t
