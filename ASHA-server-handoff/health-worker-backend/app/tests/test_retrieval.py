import pytest

from app.services.protocol_retrieval.evaluation import evaluate
from app.services.protocol_retrieval.service import ProtocolIndex, passages_from_db
from app.services.text import normalize_text
from app.tests.fixture_corpus import CASES, QUESTIONS, passages

FIX = ("TEST_FIXTURE_ONLY",)


@pytest.fixture
def index():
    return ProtocolIndex(passages(), FIX)


def test_only_eligible_passages_indexed(index):
    assert index.n == 4                       # unverified (FX-P5) and not-approved (FX-P6) excluded
    assert index.search("lantern cupboard blue").status != "MATCH_FOUND"
    assert index.search("bicycle repair roster").status != "MATCH_FOUND"


def test_default_eligibility_rejects_fixture_status():
    assert ProtocolIndex(passages(), ("VERIFIED",)).n == 0       # production default accepts VERIFIED only


def test_english_query_returns_exact_citation(index):
    r = index.search("Who signs the visit register after the monthly review?")
    assert r.status == "MATCH_FOUND" and r.matched_passage_ids[0] == "FX-P1"
    m = r.matches[0]
    assert (m.document_id, m.document_title, m.section_id, m.section_heading, m.page_number, m.source_version) == ("FX-DOC1", "Fixture Handbook A", "S1", "Register upkeep", 4, "fixture-v0")
    assert m.text == passages()[0].text and m.source_verification_status == "TEST_FIXTURE_ONLY" and 0 < m.relevance_score <= 1
    assert r.original_query.startswith("Who signs") and r.query_id


def test_telugu_query_with_zwnj(index):
    r = index.search("రిజిస్టర్‌పై ఎవరు సంతకం చేయాలి సమీక్ష తర్వాత?")
    assert r.status == "MATCH_FOUND" and r.matched_passage_ids[0] == "FX-P3" and r.matches[0].page_number == 2


def test_code_mixed_query(index):
    r = index.search("monthly review తర్వాత register ఎవరు sign చేయాలి supervisor")
    assert r.status == "MATCH_FOUND" and r.matched_passage_ids[0] == "FX-P1"


@pytest.mark.parametrize("q", ["What is the colour of the moon cheese?", "", "   ", "????", "ఏం ఎలా"])
def test_no_result_when_no_evidence(index, q):
    r = index.search(q)
    assert r.status in ("NO_RESULT", "BELOW_THRESHOLD") and r.matches == []


def test_threshold_is_configurable(index):
    q = "visit register unknownword another"
    assert index.search(q, min_score=0.9).status == "BELOW_THRESHOLD"
    assert index.search(q, min_score=0.1, min_matched_terms=1).status == "MATCH_FOUND"


def test_normalisation_preserves_original_and_collapses_whitespace(index):
    r = index.search("  Visit   REGISTER ​ signs ")
    assert r.original_query == "  Visit   REGISTER ​ signs " and r.normalized_query == normalize_text("  Visit   REGISTER ​ signs ")
    assert "  " not in r.normalized_query and "​" not in r.normalized_query


def test_evaluation_metrics_computed(index):
    res = evaluate(CASES, QUESTIONS, index)
    a = res["by_language"]["ALL"]
    assert res["status"] == "EVALUATED" and a["recall_at_1"] == 1.0 and a["recall_at_3"] == 1.0 and a["citation_accuracy"] == 1.0
    assert a["correct_no_result_rate"] == 1.0 and a["unsupported_answer_rate"] == 0.0
    assert set(res["by_language"]) == {"english", "telugu", "ALL"}


def test_evaluation_reports_not_evaluable_without_cases(index):
    assert evaluate([], {}, index)["status"] == "NOT_EVALUABLE"


def test_real_corpus_is_honest_when_empty(db, settings):
    idx = ProtocolIndex(passages_from_db(db), settings.eligible_statuses)
    if idx.n == 0:
        assert idx.search("antenatal care visits").status == "NO_RESULT"
