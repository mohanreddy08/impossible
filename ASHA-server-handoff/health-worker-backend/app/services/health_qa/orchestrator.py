"""Evidence-grounded QA pipeline. Order is fixed:
validate -> normalise -> deterministic safety -> (escalate/clarify/refuse return immediately) -> retrieve ->
evidence sufficiency -> template answer + citations -> final validation -> answer or safe fallback.
No LLM is involved. Nothing generated can override a triggered escalation."""
import logging
import re
import uuid
from dataclasses import dataclass, field
from typing import List, Optional

from app.services.protocol_retrieval.service import ProtocolIndex, RetrievalResult
from app.services.safety.engine import SafetyDecision, SafetyEngine, get_engine

log = logging.getLogger("health_qa")
MAX_LEN = 2000
_CTRL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

FALLBACK = "No verified protocol passage was found for this question. Please consult your supervisor or the approved protocol document."
ANSWER_TEMPLATE = "According to {title}{section}{page}: {text}"


class InvalidQuestion(ValueError):
    pass


@dataclass
class Citation:
    passage_id: str
    document_id: str
    document_title: Optional[str]
    section_id: Optional[str]
    section_heading: Optional[str]
    page_number: Optional[int]
    source_version: Optional[str]
    relevance_score: float
    source_verification_status: str


@dataclass
class QAResponse:
    query_id: str
    outcome: str
    original_question: str
    message: str
    answer_text: Optional[str] = None
    citations: List[Citation] = field(default_factory=list)
    safety_status: str = ""
    safety_rule_ids: List[str] = field(default_factory=list)
    safety_reasons: List[str] = field(default_factory=list)
    safety_ruleset_version: str = ""
    safety_ruleset_review_status: str = ""
    safety_clinically_validated: bool = False
    needs_human_review: bool = False
    retrieval_status: Optional[str] = None


def validate_input(q) -> str:
    if not isinstance(q, str):
        raise InvalidQuestion("question must be text")
    q = _CTRL.sub("", q).strip()
    if not q:
        raise InvalidQuestion("question is empty")
    if len(q) > MAX_LEN:
        raise InvalidQuestion("question longer than %d characters" % MAX_LEN)
    return q


def answer_question(question: str, index: ProtocolIndex, *, engine: Optional[SafetyEngine] = None, top_k: int = 3,
                    min_score: float = 0.5, min_matched_terms: int = 2) -> QAResponse:
    q = validate_input(question)                                    # 1-2 (normalisation happens in safety/retrieval, original preserved)
    engine = engine or get_engine()
    d: SafetyDecision = engine.evaluate(q)                          # 3
    base = dict(original_question=q, safety_status=d.status, safety_rule_ids=d.rule_ids, safety_reasons=d.reasons,
                safety_ruleset_version=d.ruleset_version, safety_ruleset_review_status=d.ruleset_review_status, safety_clinically_validated=d.clinically_validated,
                needs_human_review=d.needs_human_review)
    qid = uuid.uuid4().hex[:16]
    if d.status != "NORMAL_PROTOCOL_QUERY":                         # 4: return immediately, no retrieval, no answer text
        outcome = d.status
        log.info("qa query_id=%s outcome=%s rules=%s", qid, outcome, ",".join(d.rule_ids))
        return QAResponse(query_id=qid, outcome=outcome, message=d.message or "", **base)
    r: RetrievalResult = index.search(q, top_k=top_k, min_score=min_score, min_matched_terms=min_matched_terms)   # 5-6
    resp = QAResponse(query_id=qid, outcome="INSUFFICIENT_EVIDENCE", message=FALLBACK, retrieval_status=r.status, **base)
    if r.status == "MATCH_FOUND":                                   # 7-9
        top = r.matches[0]
        if top.source_verification_status and top.text:
            sec = ", section %s" % (top.section_heading or top.section_id) if (top.section_heading or top.section_id) else ""
            page = ", page %s" % top.page_number if top.page_number is not None else ""
            resp.answer_text = ANSWER_TEMPLATE.format(title=top.document_title or top.document_id, section=sec, page=page, text=top.text)
            resp.citations = [Citation(m.passage_id, m.document_id, m.document_title, m.section_id, m.section_heading, m.page_number,
                                       m.source_version, m.relevance_score, m.source_verification_status) for m in r.matches]
            resp.outcome, resp.message = "ANSWERED_WITH_EVIDENCE", "Answer is the verbatim approved protocol passage; see citations."
    if resp.outcome == "ANSWERED_WITH_EVIDENCE" and not resp.citations:   # 9: final validation
        resp.outcome, resp.answer_text, resp.message = "INSUFFICIENT_EVIDENCE", None, FALLBACK
    log.info("qa query_id=%s outcome=%s retrieval=%s", qid, resp.outcome, r.status)
    return resp
