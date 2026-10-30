"""Offline lexical protocol retrieval (SQLite FTS5 candidates + IDF-weighted term coverage).

Independent of HTTP/ORM: it takes plain PassageRecord objects and an sqlite3 connection, so the same logic can
be ported to the phone. FTS5 uses the 'ascii' tokenizer on PRE-TOKENISED text (Telugu code points are kept intact).
FTS5's raw bm25 is unreliable on tiny corpora, so thresholding uses relevance_score = IDF-weighted share of
query terms found in the passage (0..1); raw bm25 is returned too. No vectors, no LLM.
"""
import math
import sqlite3
import uuid
from dataclasses import dataclass, field
from typing import Dict, Iterable, List, Optional, Sequence

from app.services.text import normalize_text, tokenize

STOPWORDS = {
    "the", "a", "an", "is", "are", "to", "of", "and", "or", "in", "on", "for", "do", "does", "how", "what", "when", "which",
    "should", "i", "we", "it", "be", "can", "my", "this", "that", "with", "at", "by", "if", "after", "per",
    "ఏ", "ఏం", "ఎలా", "ఎప్పుడు", "ఎన్ని", "ఏది", "ఎంత", "చేయాలి", "చేయాలా", "ఉంది", "ఉన్న", "కి", "ki", "ela", "em", "ye", "enni",
    "cheyali", "eppudu", "enta", "undi",
}


@dataclass
class PassageRecord:
    passage_id: str
    document_id: str
    document_title: Optional[str]
    document_version: Optional[str]
    section_id: Optional[str]
    section_title: Optional[str]
    page_number: Optional[int]
    text: str
    source_verification_status: str
    approved_for_retrieval: bool
    language: Optional[str] = None


@dataclass
class PassageMatch:
    passage_id: str
    document_id: str
    document_title: Optional[str]
    section_id: Optional[str]
    section_heading: Optional[str]
    page_number: Optional[int]
    source_version: Optional[str]
    relevance_score: float
    bm25_raw: float
    matched_terms: List[str]
    source_verification_status: str
    text: str


@dataclass
class RetrievalResult:
    query_id: str
    status: str                       # MATCH_FOUND | NO_RESULT | BELOW_THRESHOLD
    original_query: str
    normalized_query: str
    matches: List[PassageMatch] = field(default_factory=list)
    matched_passage_ids: List[str] = field(default_factory=list)
    candidates_considered: int = 0
    threshold: Dict = field(default_factory=dict)
    indexed_passages: int = 0


class ProtocolIndex:
    def __init__(self, passages: Iterable[PassageRecord], eligible_statuses: Sequence[str] = ("VERIFIED",), conn: Optional[sqlite3.Connection] = None):
        self.conn = conn or sqlite3.connect(":memory:")
        self.conn.execute("DROP TABLE IF EXISTS passages_fts")
        self.conn.execute("CREATE VIRTUAL TABLE passages_fts USING fts5(pid UNINDEXED, tokens, tokenize='ascii')")
        self.records: Dict[str, PassageRecord] = {}
        self.tokens: Dict[str, set] = {}
        df: Dict[str, int] = {}
        for p in passages:
            if not p.approved_for_retrieval or p.source_verification_status not in eligible_statuses or not p.text:
                continue                      # only eligible, imported passages are searchable
            toks = tokenize(p.text) + tokenize(p.section_title or "")
            self.records[p.passage_id] = p
            self.tokens[p.passage_id] = set(toks)
            self.conn.execute("INSERT INTO passages_fts(pid, tokens) VALUES (?, ?)", (p.passage_id, " ".join(toks)))
            for t in set(toks):
                df[t] = df.get(t, 0) + 1
        self.conn.commit()
        n = len(self.records)
        self.n = n
        self.idf = {t: math.log(1 + (n - d + 0.5) / (d + 0.5)) for t, d in df.items()}

    def search(self, question: str, top_k: int = 3, min_score: float = 0.5, min_matched_terms: int = 2) -> RetrievalResult:
        norm = normalize_text(question)
        res = RetrievalResult(query_id=uuid.uuid4().hex[:16], status="NO_RESULT", original_query=question, normalized_query=norm,
                              threshold=dict(min_score=min_score, min_matched_terms=min_matched_terms, top_k=top_k), indexed_passages=self.n)
        qt = [t for t in dict.fromkeys(tokenize(question)) if t not in STOPWORDS]
        if not qt or not self.n:
            return res
        match_expr = " OR ".join('"%s"' % t.replace('"', "") for t in qt)
        rows = self.conn.execute("SELECT pid, bm25(passages_fts) FROM passages_fts WHERE passages_fts MATCH ? ORDER BY bm25(passages_fts) LIMIT 50", (match_expr,)).fetchall()
        res.candidates_considered = len(rows)
        if not rows:
            return res
        # idf for query terms absent from the corpus is 0 weight -> they can only lower coverage via max_idf fallback
        max_idf = max(self.idf.values()) if self.idf else 1.0
        qw = {t: self.idf.get(t, max_idf) for t in qt}
        total = sum(qw.values()) or 1.0
        scored = []
        for pid, bm in rows:
            hit = [t for t in qt if t in self.tokens[pid]]
            scored.append((sum(qw[t] for t in hit) / total, -bm, pid, hit))
        scored.sort(key=lambda x: (-x[0], -x[1], x[2]))
        good = [s for s in scored if s[0] >= min_score and len(s[3]) >= min_matched_terms][:top_k]
        if not good:
            res.status = "BELOW_THRESHOLD"
            return res
        for score, bm, pid, hit in good:
            p = self.records[pid]
            res.matches.append(PassageMatch(pid, p.document_id, p.document_title, p.section_id, p.section_title, p.page_number, p.document_version,
                                            round(score, 4), round(bm, 6), hit, p.source_verification_status, p.text))
        res.matched_passage_ids = [m.passage_id for m in res.matches]
        res.status = "MATCH_FOUND"
        return res


def passages_from_db(db) -> List[PassageRecord]:
    from app.db.models import ProtocolDocument, ProtocolPassage
    docs = {d.document_id: d for d in db.query(ProtocolDocument)}
    out = []
    for p in db.query(ProtocolPassage):
        d = docs.get(p.document_id)
        out.append(PassageRecord(p.passage_id, p.document_id, d.title if d else None, d.version if d else None, p.section_id, p.section_title,
                                 p.page_number, p.passage_text, p.source_verification_status, p.approved_for_retrieval, p.language))
    return out
