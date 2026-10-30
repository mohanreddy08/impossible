#!/usr/bin/env python3
"""Run all supplied questions through the pipeline and compare with the PRELIMINARY labels (no verified answers exist)."""
import json, os, sys
from collections import Counter
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import get_settings
from app.db.base import Base
import app.db.models  # noqa: F401
from app.db.session import make_engine, session_factory
from app.services.dataset_import.importer import import_datasets
from app.services.dataset_import.manifest import load
from app.services.health_qa.orchestrator import answer_question
from app.services.protocol_retrieval.service import ProtocolIndex, passages_from_db

s = get_settings()
eng = make_engine("sqlite://"); Base.metadata.create_all(eng)
with session_factory(eng)() as db:
    import_datasets(db, s.resolved_dataset_dir, include_benchmarks=False)
    idx = ProtocolIndex(passages_from_db(db), s.eligible_statuses)
Q = load(s.resolved_dataset_dir, "health_questions")
conf, outcomes, dosage_leak, bylang = Counter(), Counter(), 0, {}
mism = []
for q in Q:
    r = answer_question(q["question_text"], idx)
    outcomes[r.outcome] += 1
    exp = q["expected_safety_status"]
    got_gate = r.safety_status
    conf[(exp, got_gate)] += 1
    ok = exp == got_gate
    bylang.setdefault(q["language_type"], [0, 0]); bylang[q["language_type"]][0] += 1; bylang[q["language_type"]][1] += ok
    if not ok: mism.append((q["question_id"], q["question_text"], exp, got_gate))
    if exp == "OUT_OF_SCOPE" and r.answer_text: dosage_leak += 1
out = dict(questions=len(Q), eligible_passages_indexed=idx.n, pipeline_outcomes=dict(outcomes),
           safety_gate_vs_preliminary_label={"%s->%s" % k: v for k, v in sorted(conf.items())},
           agreement_by_language={k: "%d/%d" % (v[1], v[0]) for k, v in bylang.items()},
           out_of_scope_with_answer_text=dosage_leak, mismatches=mism,
           note="No verified source passages were supplied, so no question can be ANSWERED_WITH_EVIDENCE; answer/citation comparison is not possible.")
json.dump(out, open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "qa_evaluation.json"), "w"), indent=2, ensure_ascii=False)
print(json.dumps({k: v for k, v in out.items() if k != "mismatches"}, indent=2, ensure_ascii=False)); print("mismatches:", len(mism))
for m in mism[:15]: print("  ", m)
