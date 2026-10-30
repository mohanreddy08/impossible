"""Phase 3: the whole server-side RAG pipeline (real embedding model + real LLM) on the 22 Telugu questions.

For answerable questions: the right passage is first, and the answer contains an expected word. For not-covered ones: "no approved text",
no model call. Reports how often the answer was written by the model vs the approved passage itself, and the response times (the phone waits 10 s).

  .venv/bin/python scripts/telugu_rag_eval.py            (settings from the environment: LLM_PROVIDER=ollama LLM_BASE_URL=... LLM_MODEL=...)
"""
import json, os, sys, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.core.config import Settings
from app.services.protocol_retrieval.service import PassageRecord, ProtocolIndex
from app.services.rag import service as rag

ROOT = os.path.join(os.path.dirname(__file__), "..")
PASSAGES = os.environ.get("PASSAGES_JSON", os.path.join(ROOT, "..", "health-worker-app", "assets", "data", "passages.json"))
recs = [PassageRecord(p["passage_id"], p["document_id"], p["document_id"], "sample-0", p["section_id"], p["section_title"], p["page_number"],
                      p["passage_text"], "TEST_FIXTURE_ONLY", True, p["language"]) for p in json.load(open(PASSAGES, encoding="utf-8"))["passages"]]
idx = ProtocolIndex(recs, ("TEST_FIXTURE_ONLY",))
rag.get_index = lambda db, elig: idx
s = Settings(llm_provider=os.environ.get("LLM_PROVIDER", "ollama"), llm_base_url=os.environ.get("LLM_BASE_URL", "http://127.0.0.1:11500"),
             llm_model=os.environ.get("LLM_MODEL", "qwen3:8b"), database_url="sqlite://", auth_mode="disabled",
             eligible_verification_statuses="TEST_FIXTURE_ONLY", rag_cache_path=os.environ.get("RAG_CACHE", "/tmp/rag_eval_vectors.json"))
qs = [json.loads(l) for l in open(os.path.join(ROOT, "eval", "telugu_rag_questions.jsonl"), encoding="utf-8") if l.strip()]
rag.answer(None, s, "చేతులు ఎలా కడుక్కోవాలి")            # warm the library vectors and the model, so timings are the steady state
good = n = llm = 0; times = []; notes = []; refused = 0; nref = 0
for q in qs:
    t0 = time.time(); r = rag.answer(None, s, q["question"]); dt = time.time() - t0
    top = ["%s#%s" % (x["document_id"], x["section_id"]) for x in r["sources"]]
    if q["gold"]:
        n += 1; times.append(dt)
        right_first = bool(top[:1]) and top[0] in q["gold"]
        if r["outcome"] == "ESCALATION_REQUIRED":      # a danger sign: no answer text by design, the right approved passage must come with the alert
            ok = right_first
        else:
            ok = r["outcome"] == "ANSWERED" and right_first and any(m in (r["answer"] or "") for m in q["must_any"])
        good += bool(ok); llm += r["answer_source"] == "llm"
        if not ok: notes.append("MISS %s %s -> %s %s :: %s" % (q["id"], q["question"], r["outcome"], top[:2], (r["answer"] or "")[:80]))
        elif r["answer_source"] != "llm": notes.append("extract %s (%s)" % (q["id"], r["llm_error"]))
    else:
        nref += 1; refused += r["outcome"] == "NO_APPROVED_TEXT"
        if r["outcome"] != "NO_APPROVED_TEXT": notes.append("NOT REFUSED %s -> %s %s" % (q["id"], r["outcome"], top[:1]))
times.sort()
print("answerable : %d/%d correct (right passage first; the answer holds its expected words, or the danger-sign alert came with that passage)" % (good, n))
print("answer text: model-written %d, approved passage itself %d" % (llm, n - llm))
print("not covered: %d/%d correctly answered 'no approved text'" % (refused, nref))
print("time       : median %.1fs  p90 %.1fs  max %.1fs   (budget %.0fs)" % (times[len(times) // 2], times[int(len(times) * 0.9) - 1], times[-1], s.rag_budget_seconds))
for x in notes: print("  ", x)
