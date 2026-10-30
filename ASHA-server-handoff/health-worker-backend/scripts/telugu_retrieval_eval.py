"""Phase 2 of the Telugu RAG evaluation: does a multilingual embedding model find the right passage for a Telugu question?
Recall@1 / @3 over the answerable questions (a hit = the retrieved passage is the gold section, in either language), and the score gap
between answerable and not-covered questions (that gap is what lets the server answer "no approved text" instead of guessing).

  .venv/bin/python scripts/telugu_retrieval_eval.py [EMBED_MODEL]        (Ollama at OLLAMA_URL, default http://127.0.0.1:11500)
"""
import json, math, os, sys, urllib.request

URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11500")
ROOT = os.path.join(os.path.dirname(__file__), "..")
PASSAGES = os.environ.get("PASSAGES_JSON", os.path.join(ROOT, "..", "health-worker-app", "assets", "data", "passages.json"))
model = sys.argv[1] if len(sys.argv) > 1 else "bge-m3"
passages = json.load(open(PASSAGES, encoding="utf-8"))["passages"]
qs = [json.loads(l) for l in open(os.path.join(ROOT, "eval", "telugu_rag_questions.jsonl"), encoding="utf-8") if l.strip()]


def embed(texts):
    r = urllib.request.Request(URL + "/api/embed", json.dumps({"model": model, "input": texts}).encode(), {"content-type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=300))["embeddings"]


def cos(a, b):
    return sum(x * y for x, y in zip(a, b)) / (math.sqrt(sum(x * x for x in a)) * math.sqrt(sum(y * y for y in b)))


P = embed([(p.get("section_title") or "") + "\n" + p["passage_text"] for p in passages])
Q = embed([q["question"] for q in qs])
key = lambda p: "%s#%s" % (p["document_id"], p["section_id"])
h1 = h3 = n = 0; top_answerable = []; top_not = []
for q, qv in zip(qs, Q):
    ranked = sorted(((cos(qv, pv), key(p), p["language"]) for p, pv in zip(passages, P)), reverse=True)
    if q["gold"]:
        n += 1
        keys = []
        for s, k, l in ranked:
            if k not in keys: keys.append(k)
        h1 += keys[0] in q["gold"]; h3 += any(k in q["gold"] for k in keys[:3])
        top_answerable.append(ranked[0][0])
        if keys[0] not in q["gold"]:
            print("  miss", q["id"], q["question"], "->", keys[:3], "score %.2f" % ranked[0][0])
    else:
        top_not.append(ranked[0][0])
print("%s: Recall@1 %d/%d   Recall@3 %d/%d" % (model, h1, n, h3, n))
print("top-1 score, answerable questions : min %.3f  median %.3f" % (min(top_answerable), sorted(top_answerable)[len(top_answerable) // 2]))
print("top-1 score, not-covered questions: max %.3f" % max(top_not))
print("gap (answerable min - not-covered max): %.3f" % (min(top_answerable) - max(top_not)))
