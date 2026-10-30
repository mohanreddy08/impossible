"""Retrieval metrics over retrieval_evaluation cases: Recall@1/@3, citation accuracy, unsupported-answer rate, no-result, by language."""
from collections import defaultdict
from typing import Dict, List

from app.services.protocol_retrieval.service import ProtocolIndex


def evaluate(cases: List[dict], questions_by_id: Dict[str, dict], index: ProtocolIndex, **kw) -> Dict:
    if not cases:
        return dict(status="NOT_EVALUABLE", reason="no retrieval_evaluation cases supplied", cases=0)
    agg = defaultdict(lambda: dict(answerable=0, r1=0, r3=0, cite=0, no_result_cases=0, correct_no_result=0, unsupported=0))
    for c in cases:
        q = questions_by_id.get(c["question_id"], {})
        lang = q.get("language_type", "unknown")
        res = index.search(q.get("question_text", ""), top_k=3, **kw)
        for key in (lang, "ALL"):
            a = agg[key]
            if c.get("expected_no_result"):
                a["no_result_cases"] += 1
                if res.status != "MATCH_FOUND": a["correct_no_result"] += 1
                else: a["unsupported"] += 1
            else:
                exp = set(c["expected_passage_ids"])
                a["answerable"] += 1
                ids = res.matched_passage_ids
                a["r1"] += bool(ids[:1] and ids[0] in exp)
                a["r3"] += bool(exp & set(ids[:3]))
                top = res.matches[0] if res.matches else None
                if top and top.passage_id in exp and top.document_id in c.get("expected_document_ids", [top.document_id]) \
                        and (not c.get("expected_page_numbers") or top.page_number in c["expected_page_numbers"]) \
                        and (not c.get("expected_section_ids") or top.section_id in c["expected_section_ids"]):
                    a["cite"] += 1
    out = {}
    for k, a in agg.items():
        d = lambda n, m: round(n / m, 4) if m else None  # noqa: E731
        out[k] = dict(answerable=a["answerable"], recall_at_1=d(a["r1"], a["answerable"]), recall_at_3=d(a["r3"], a["answerable"]),
                      citation_accuracy=d(a["cite"], a["answerable"]), no_result_cases=a["no_result_cases"],
                      correct_no_result_rate=d(a["correct_no_result"], a["no_result_cases"]),
                      unsupported_answer_rate=d(a["unsupported"], a["no_result_cases"]))
    return dict(status="EVALUATED", cases=len(cases), by_language=out)
