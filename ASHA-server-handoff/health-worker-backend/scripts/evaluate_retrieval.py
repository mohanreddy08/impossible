#!/usr/bin/env python3
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import get_settings
from app.db.base import Base
import app.db.models  # noqa: F401
from app.db.session import make_engine, session_factory
from app.services.dataset_import.importer import import_datasets
from app.services.dataset_import.manifest import load
from app.services.protocol_retrieval.evaluation import evaluate
from app.services.protocol_retrieval.service import ProtocolIndex, passages_from_db

s = get_settings()
eng = make_engine("sqlite://"); Base.metadata.create_all(eng)
with session_factory(eng)() as db:
    import_datasets(db, s.resolved_dataset_dir, include_benchmarks=False)
    idx = ProtocolIndex(passages_from_db(db), s.eligible_statuses)
cases = load(s.resolved_dataset_dir, "retrieval_evaluation") or []
qs = {q["question_id"]: q for q in load(s.resolved_dataset_dir, "health_questions") or []}
r = evaluate(cases, qs, idx, min_score=s.evidence_min_score, min_matched_terms=s.evidence_min_matched_terms)
r["indexed_eligible_passages"] = idx.n
print(json.dumps(r, indent=2))
