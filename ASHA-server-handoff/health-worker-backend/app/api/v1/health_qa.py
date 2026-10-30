from dataclasses import asdict

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import *  # noqa
from app.core.config import Settings, get_settings
from app.core.errors import DomainError
from app.core.security import Principal, get_principal
from app.db.session import get_db
from app.schemas.common import ErrorResponse
from app.schemas.api import ExplainIn, ExplainOut, LlmIn, LlmOut, QAOut, QueryIn, RagIn, RagOut, RetrieveOut
from app.services.llm.client import ask_llm, explain_passages
from app.services.ask import service as ask_service
from app.services.rag import service as rag_service
from app.services.health_qa.orchestrator import InvalidQuestion, answer_question
from app.services.protocol_retrieval.cache import get_index

router = APIRouter(prefix="/health-qa", tags=["health-qa"])


def _log_outcome(db: Session, p: Principal, outcome: str, rule_ids, section_ids) -> None:
    """Escalations/refusals from phones show up in the website's feed. Outcome and ids only; the question is never stored."""
    if outcome not in ("ESCALATION_REQUIRED", "OUT_OF_SCOPE"):
        return
    try:
        ask_service.log_phone_qa(db, p, outcome, rule_ids, section_ids)
    except Exception:                                             # noqa: BLE001  the answer must never depend on the audit
        db.rollback()


@router.post("/query", response_model=QAOut, summary="Safety-gated, evidence-grounded answer")
def query(body: QueryIn, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    idx = get_index(db, s.eligible_statuses)
    try:
        r = answer_question(body.question, idx, top_k=s.retrieval_top_k, min_score=s.evidence_min_score, min_matched_terms=s.evidence_min_matched_terms)
    except InvalidQuestion as e:
        raise DomainError(str(e), code="INVALID_QUESTION", status_code=422)
    _log_outcome(db, p, r.outcome, r.safety_rule_ids, [c.section_id for c in r.citations if getattr(c, "section_id", None)])
    return QAOut(query_id=r.query_id, outcome=r.outcome, original_question=r.original_question, message=r.message, answer_text=r.answer_text,
                 citations=[c.__dict__ for c in r.citations], retrieval_status=r.retrieval_status,
                 safety=dict(status=r.safety_status, rule_ids=r.safety_rule_ids, reasons=r.safety_reasons, ruleset_version=r.safety_ruleset_version,
                             ruleset_review_status=r.safety_ruleset_review_status, clinically_validated=r.safety_clinically_validated, needs_human_review=r.needs_human_review))


@router.post("/retrieve", response_model=RetrieveOut, summary="Raw protocol retrieval (no answer generation)")
def retrieve(body: QueryIn, db: Session = Depends(get_db), s: Settings = Depends(get_settings), _: Principal = Depends(get_principal)):
    r = get_index(db, s.eligible_statuses).search(body.question, top_k=s.retrieval_top_k, min_score=s.evidence_min_score, min_matched_terms=s.evidence_min_matched_terms)
    return RetrieveOut(query_id=r.query_id, status=r.status, original_query=r.original_query, normalized_query=r.normalized_query,
                       matched_passage_ids=r.matched_passage_ids, indexed_passages=r.indexed_passages,
                       matches=[dict(m.__dict__, section_heading=m.section_heading) for m in r.matches])


@router.post("/llm", response_model=LlmOut, summary="Optional AI answer (not clinically verified; the question is never logged or stored)",
             responses={502: dict(model=ErrorResponse, description="AI service unreachable, refused, or returned nothing"),
                        503: dict(model=ErrorResponse, description="AI answers are not configured on this server (no API key)"),
                        504: dict(model=ErrorResponse, description="AI service did not answer within the server's time limit")})
def llm(body: LlmIn, s: Settings = Depends(get_settings), _: Principal = Depends(get_principal)):
    return LlmOut(**ask_llm(body.question, body.safety_status, s))


@router.post("/explain", response_model=ExplainOut,
             summary="Explain the phone's closest approved passages for the question (local or cloud LLM; nothing is logged or stored)",
             responses={502: dict(model=ErrorResponse, description="LLM unreachable, refused, returned nothing, or its text was withheld (medicine or dose)"),
                        503: dict(model=ErrorResponse, description="No LLM is configured on this server"),
                        504: dict(model=ErrorResponse, description="The LLM did not answer within the server's time limit")})
def explain(body: ExplainIn, s: Settings = Depends(get_settings), _: Principal = Depends(get_principal)):
    return ExplainOut(**explain_passages(body.question, [p.model_dump() for p in body.passages], body.safety_status, s))


@router.post("/rag", response_model=RagOut,
             summary="Ask a question: multilingual retrieval over the approved passages, then a short answer from them (nothing is logged or stored)",
             responses={404: dict(model=ErrorResponse, description="Server-side RAG is switched off"),
                        422: dict(model=ErrorResponse, description="Invalid question")})
def rag(body: RagIn, db: Session = Depends(get_db), s: Settings = Depends(get_settings), p: Principal = Depends(get_principal)):
    if not s.rag_enabled:
        raise DomainError("server-side RAG is switched off", code="RAG_DISABLED", status_code=404)
    try:
        out = rag_service.answer(db, s, body.question)
        _log_outcome(db, p, out.get("outcome", ""), (out.get("safety") or {}).get("rule_ids"), [])
        return RagOut(**out)
    except InvalidQuestion as e:
        raise DomainError(str(e), code="INVALID_QUESTION", status_code=422)
