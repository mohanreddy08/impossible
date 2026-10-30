"""TEST-ONLY retrieval fixture. NOT a protocol, NOT medical content, NOT part of any dataset.
Used only to exercise retrieval mechanics (ranking, thresholds, eligibility, languages) because the real
protocol corpus was not supplied. Status 'TEST_FIXTURE_ONLY' is accepted only when a test enables it."""
from app.services.protocol_retrieval.service import PassageRecord

FIX = "TEST_FIXTURE_ONLY"


def passages():
    return [
        PassageRecord("FX-P1", "FX-DOC1", "Fixture Handbook A", "fixture-v0", "S1", "Register upkeep", 4,
                      "The visit register must be signed by the supervisor after each monthly review meeting.", FIX, True, "en"),
        PassageRecord("FX-P2", "FX-DOC1", "Fixture Handbook A", "fixture-v0", "S2", "Storage of cards", 7,
                      "Immunisation cards are stored in a dry folder kept at the sub-centre cabinet.", FIX, True, "en"),
        PassageRecord("FX-P3", "FX-DOC2", "Fixture Handbook B", "fixture-v0", "T1", "రిజిస్టర్ నిర్వహణ", 2,
                      "ప్రతి నెల సమీక్ష తర్వాత రిజిస్టర్‌పై పర్యవేక్షకుడు సంతకం చేయాలి.", FIX, True, "te"),
        PassageRecord("FX-P4", "FX-DOC2", "Fixture Handbook B", "fixture-v0", "T2", "Transport desk", 9,
                      "The transport desk opens at nine and records every vehicle request in the logbook.", FIX, True, "en"),
        PassageRecord("FX-P5", "FX-DOC3", "Unverified Draft", None, "U1", "Unverified section", None,
                      "The unverified draft says the lantern cupboard is painted blue.", "UNVERIFIED", True, "en"),
        PassageRecord("FX-P6", "FX-DOC3", "Unverified Draft", None, "U2", "Not approved", None,
                      "The not approved passage mentions a bicycle repair roster.", FIX, False, "en"),
    ]


CASES = [
    dict(retrieval_test_id="FX-R1", question_id="FQ1", expected_passage_ids=["FX-P1"], expected_document_ids=["FX-DOC1"], expected_section_ids=["S1"], expected_page_numbers=[4], expected_no_result=False),
    dict(retrieval_test_id="FX-R2", question_id="FQ2", expected_passage_ids=["FX-P3"], expected_document_ids=["FX-DOC2"], expected_section_ids=["T1"], expected_page_numbers=[2], expected_no_result=False),
    dict(retrieval_test_id="FX-R3", question_id="FQ3", expected_passage_ids=[], expected_document_ids=[], expected_section_ids=[], expected_page_numbers=[], expected_no_result=True),
]
QUESTIONS = {
    "FQ1": dict(question_id="FQ1", question_text="Who signs the visit register after the monthly review?", language_type="english"),
    "FQ2": dict(question_id="FQ2", question_text="రిజిస్టర్‌పై ఎవరు సంతకం చేయాలి సమీక్ష తర్వాత?", language_type="telugu"),
    "FQ3": dict(question_id="FQ3", question_text="What is the colour of the moon cheese?", language_type="english"),
}
