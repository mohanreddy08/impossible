import pytest

from app.services.dataset_import.manifest import load
from app.services.health_qa.orchestrator import InvalidQuestion, answer_question, validate_input
from app.services.protocol_retrieval.service import PassageRecord, ProtocolIndex
from app.tests.conftest import DATASETS
from app.tests.fixture_corpus import passages

FIX = ("TEST_FIXTURE_ONLY",)
QS = load(DATASETS, "health_questions")


@pytest.fixture
def index():
    return ProtocolIndex(passages(), FIX)


def test_answered_with_evidence_has_verbatim_text_and_citation(index):
    r = answer_question("Who signs the visit register after the monthly review?", index)
    assert r.outcome == "ANSWERED_WITH_EVIDENCE" and r.citations[0].passage_id == "FX-P1"
    assert passages()[0].text in r.answer_text and "page 4" in r.answer_text and r.safety_status == "NORMAL_PROTOCOL_QUERY"


def test_insufficient_evidence_is_honest(index):
    r = answer_question("How many antenatal check-ups should a pregnant woman have?", index)
    assert r.outcome == "INSUFFICIENT_EVIDENCE" and r.answer_text is None and r.citations == []


def test_escalation_returns_immediately_and_cannot_be_overridden():
    # corpus contains text that would match the question perfectly; escalation must still win with no answer text
    p = [PassageRecord("FX-X", "D", "Doc", "v", "S", "Sec", 1, "pregnant woman is bleeding heavily right now call the van", "TEST_FIXTURE_ONLY", True)]
    r = answer_question("Pregnant woman is bleeding heavily right now", ProtocolIndex(p, FIX))
    assert r.outcome == "ESCALATION_REQUIRED" and r.answer_text is None and r.citations == [] and r.retrieval_status is None
    assert r.safety_rule_ids and r.message


def test_out_of_scope_refusal_never_supplies_dosage(index):
    r = answer_question("What dose of amoxicillin should I give a child?", index)
    assert r.outcome == "OUT_OF_SCOPE" and r.answer_text is None and "mg" not in r.message.lower()


def test_clarification_outcome(index):
    assert answer_question("she is not feeling well", index).outcome == "CLARIFICATION_REQUIRED"


@pytest.mark.parametrize("bad", ["", "   ", None, 5, "x" * 2001])
def test_input_validation(bad):
    with pytest.raises(InvalidQuestion):
        validate_input(bad)


def test_control_characters_stripped():
    assert validate_input("hello\x00 world\x07") == "hello world"


def test_all_supplied_questions_run_through_pipeline(index):
    """Safety gate vs PRELIMINARY labels; no answer is claimed correct (no verified answers exist)."""
    mism = []
    for q in QS:
        r = answer_question(q["question_text"], index)
        assert r.outcome in ("ANSWERED_WITH_EVIDENCE", "ESCALATION_REQUIRED", "CLARIFICATION_REQUIRED", "OUT_OF_SCOPE", "INSUFFICIENT_EVIDENCE")
        if r.safety_status != q["expected_safety_status"]:
            mism.append(q["question_id"])
        if q["expected_safety_status"] == "OUT_OF_SCOPE":
            assert r.answer_text is None
        if q.get("answerable_from_supplied_protocol") is False and q["expected_safety_status"] == "NORMAL_PROTOCOL_QUERY":
            assert r.outcome != "ANSWERED_WITH_EVIDENCE"
    assert mism == []


def test_api_query_and_retrieve_endpoints(client):
    r = client.post("/api/v1/health-qa/query", json={"question": "Pregnant woman is bleeding heavily right now"})
    assert r.status_code == 200 and r.json()["outcome"] == "ESCALATION_REQUIRED" and r.json()["safety"]["ruleset_version"]
    r = client.post("/api/v1/health-qa/query", json={"question": "How often should a diabetic person be followed up?"})
    assert r.json()["outcome"] in ("INSUFFICIENT_EVIDENCE", "ANSWERED_WITH_EVIDENCE")
    r = client.post("/api/v1/health-qa/retrieve", json={"question": "diabetes follow up"})
    assert r.status_code == 200 and r.json()["status"] in ("NO_RESULT", "BELOW_THRESHOLD", "MATCH_FOUND")
    assert client.post("/api/v1/health-qa/query", json={"question": ""}).status_code == 422
