"""Server-side RAG for the Ask page.

    safety rules  ->  embed the question  ->  nearest approved passages (cosine)  ->  gate  ->  short answer from the passages  ->  guards

Fixed behaviour:
  * the deterministic safety rules run first; a danger sign is never answered by a model (the passages are returned as support);
  * only approved, eligible passages are searched (the same ones /health-qa/query uses);
  * if no passage is close enough ("no approved text for this") the model is NOT called: nothing is explained from nothing;
  * a best passage that is already short (rag_direct_max_words) is the answer itself, word for word: summarising it could only lose
    something (a one-sentence summary can drop "contact the medical officer"), and it makes the answer instant;
  * otherwise the answer is written by the LLM only if every guard passes (right language, no foreign script, stays with the passages, no dose or
    medicine); otherwise, or when the model is slow, the answer is the approved passage itself, word for word;
  * the whole request stays inside rag_budget_seconds, so the phone's 10 s limit is met.
The question is never logged or stored."""
import logging
import re
import time
from typing import Any, Dict, List, Optional

from app.core.config import Settings
from app.core.errors import DomainError
from app.services.health_qa.orchestrator import validate_input
from app.services.llm import client as llm
from app.services.protocol_retrieval.cache import get_index
from app.services.protocol_retrieval.service import PassageRecord
from app.services.rag import embedder
from app.services.safety.engine import get_engine

log = logging.getLogger("rag")
_TELUGU = re.compile("[ఀ-౿]")
NO_TEXT = {
    "te": "ఈ ప్రశ్నకు సమాధానం ఇచ్చే ఆమోదిత ప్రోటోకాల్ పాఠం లేదు. దయచేసి మీ సూపర్‌వైజర్ లేదా వైద్యాధికారిని అడగండి.",
    "en": "No approved protocol text answers this question. Please ask your supervisor or medical officer.",
}
DANGER_PASSAGE = re.compile(r"danger sign|ప్రమాద సంకేత", re.IGNORECASE)
DANGER_MSG = {
    "te": "ఇది ప్రమాద సంకేతం కావచ్చు. వెంటనే మీ సూపర్‌వైజింగ్ వైద్యాధికారిని సంప్రదించండి. (కింద ఆమోదిత పాఠ్యం ఉంది)",
    "en": "This may be a danger sign. Contact the supervising medical officer now. (approved text below)",
}
SUPPORT_BAND = 0.12      # passages within this much of the best score are shown together (the answer is built from them)


def is_telugu(text: str) -> bool:
    return len(_TELUGU.findall(text)) >= 3


def _source(p: PassageRecord, score: float) -> Dict[str, Any]:
    return dict(passage_id=p.passage_id, document_id=p.document_id, document_title=p.document_title, section_id=p.section_id,
                section_heading=p.section_title, page_number=p.page_number, source_version=p.document_version,
                relevance_score=round(score, 4), source_verification_status=p.source_verification_status, text=p.text)


def _pick(scored: List[tuple], want_lang: Optional[str], min_score: float, top_k: int) -> List[tuple]:
    """scored = [(score, record)]. One passage per section (the Telugu and English versions of a section are the same content): the
    one in the question's language when there is one. Keep the ones within SUPPORT_BAND of the best, at most top_k."""
    best: Dict[tuple, tuple] = {}
    for sc, p in scored:
        k = (p.document_id, p.section_id or p.passage_id)
        cur = best.get(k)
        same = (p.language or "") == (want_lang or "")
        if cur is None or (same and (cur[1].language or "") != (want_lang or "")) or (same == ((cur[1].language or "") == (want_lang or "")) and sc > cur[0]):
            best[k] = (sc, p)
    ranked = sorted(best.values(), key=lambda t: -t[0])
    if not ranked or ranked[0][0] < min_score:
        return []
    top = ranked[0][0]
    return [t for t in ranked if t[0] >= max(min_score, top - SUPPORT_BAND)][:top_k]


def _retrieve(db, s: Settings, question: str, want_lang: Optional[str], deadline: float) -> tuple:
    """-> (method, [(score, record)]). Embeddings when the embedding service answers, otherwise the keyword index (weaker for Telugu)."""
    idx = get_index(db, s.eligible_statuses)
    records = list(idx.records.values())
    if not records:
        return "none", []
    try:
        texts = [(r.section_title or "") + "\n" + r.text for r in records]
        vecs = embedder.passage_vectors(texts, s)
        qv = embedder.embed([question], s, timeout=max(1.0, min(s.rag_embed_timeout_seconds, deadline - time.time())))[0]
        scored = [(sum(a * b for a, b in zip(qv, v)), r) for v, r in zip(vecs, records)]
        return "embedding", _pick(scored, want_lang, s.rag_min_score, s.rag_top_k)
    except embedder.EmbedUnavailable as e:
        log.warning("rag: embeddings unavailable (%s), using the keyword index", e)
    r = idx.search(question, top_k=s.rag_top_k, min_score=s.evidence_min_score, min_matched_terms=s.evidence_min_matched_terms)
    got = [(m.relevance_score, idx.records[m.passage_id]) for m in r.matches if m.passage_id in idx.records]
    return "keyword", got


def answer(db, s: Settings, question: str) -> Dict[str, Any]:
    t0 = time.time()
    deadline = t0 + s.rag_budget_seconds
    q = validate_input(question)
    lang = "te" if is_telugu(q) else "en"
    d = get_engine().evaluate(q)
    out: Dict[str, Any] = dict(
        outcome="", answer=None, answer_source=None, message="", sources=[], model=None, embedder=None, retrieval=None, llm_error=None,
        language=lang,
        safety=dict(status=d.status, rule_ids=d.rule_ids, reasons=d.reasons, ruleset_version=d.ruleset_version,
                    clinically_validated=d.clinically_validated, needs_human_review=d.needs_human_review))
    if d.status not in ("NORMAL_PROTOCOL_QUERY", "ESCALATION_REQUIRED"):
        out.update(outcome=d.status, message=d.message or "")                  # clarify / out of scope: no retrieval, no model
        return out
    method, got = _retrieve(db, s, q, lang, deadline)
    out.update(retrieval=method, embedder=s.rag_embed_model if method == "embedding" else None,
               sources=[_source(p, sc) for sc, p in got], timings_ms=dict(retrieve=int((time.time() - t0) * 1000)))
    if d.status == "ESCALATION_REQUIRED":
        out.update(outcome="ESCALATION_REQUIRED", message=d.message or "")     # the passages are support; a danger sign is never explained by a model
        return out
    if not got:
        out.update(outcome="NO_APPROVED_TEXT", message=NO_TEXT[lang])           # gate: nothing is explained from nothing
        return out
    top = got[0][1]
    if DANGER_PASSAGE.search(" ".join(filter(None, [top.document_title, top.section_title, top.text]))):
        # the question matched a DANGER-SIGN passage although the word rules found no danger phrase (a spelling slip, a spoken variant):
        # never show it as an ordinary answer. It is raised as a possible danger sign and the passage is shown as support.
        out["safety"] = dict(out["safety"], status="ESCALATION_REQUIRED", rule_ids=["RAG-DANGER-PASSAGE"],
                             reasons=["The closest approved passage describes a danger sign"])
        out.update(outcome="ESCALATION_REQUIRED", message=DANGER_MSG[lang])
        return out
    extract = top.text
    out.update(outcome="ANSWERED", answer=extract, answer_source="extract", message="Answer is the approved passage, word for word.")
    if len(extract.split()) <= s.rag_direct_max_words:
        out["message"] = "Answer is the approved passage, word for word (it is short enough to be the answer)."
        return out                                                              # no model call: nothing to summarise, nothing can be dropped
    left = deadline - time.time() - 0.3
    if left < 1.5 or not llm.configured(s):
        out["llm_error"] = "no_time" if llm.configured(s) else "not_configured"
        return out
    g0 = time.time()
    try:
        text = llm.rag_generate(q, [dict(title=p.section_title, text=p.text) for _, p in got], d.status, s, timeout=left)
        out.update(answer=text, answer_source="llm", model=s.llm_model, message="Answer written by the AI from the approved passages.")
    except DomainError as e:
        out["llm_error"] = e.code                                               # the approved passage stays as the answer
    out["timings_ms"]["generate"] = int((time.time() - g0) * 1000)
    return out
