"""Phase 1 of the Telugu RAG evaluation: which local LLM writes a CORRECT Telugu explanation from the right passage?

Isolates the model: every question is given its gold passage (plus one unrelated distractor), so retrieval is not a factor.
Scores per answer: written in Telugu, no word that mixes Telugu and Latin letters, stays with the passages (the server's own guard),
contains at least one expected word from the passage. Not-covered questions get only a distractor: the right behaviour is to say so.

  .venv/bin/python scripts/telugu_llm_eval.py MODEL [MODEL ...]       (Ollama at OLLAMA_URL, default http://127.0.0.1:11500)
"""
import json, os, sys, time, urllib.request
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from app.services.llm import client as c

URL = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11500")
ROOT = os.path.join(os.path.dirname(__file__), "..")
CORPUS = {}
PASSAGES = os.environ.get("PASSAGES_JSON", os.path.join(ROOT, "..", "health-worker-app", "assets", "data", "passages.json"))   # built by asha-data/build_data.py
for p in json.load(open(PASSAGES, encoding="utf-8"))["passages"]:
    if p["language"] == "te":
        CORPUS["%s#%s" % (p["document_id"], p["section_id"])] = p
QS = [json.loads(l) for l in open(os.path.join(ROOT, "eval", "telugu_rag_questions.jsonl"), encoding="utf-8") if l.strip()]
DISTRACTOR = "SAMPLE-APP-WORKFLOW#privacy"


def chat(model, system, user):
    body = {"model": model, "stream": False, "think": False, "options": {"temperature": 0, "num_predict": 400},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    for attempt in (0, 1):
        r = urllib.request.Request(URL + "/api/chat", json.dumps(body).encode(), {"content-type": "application/json"})
        try:
            return json.load(urllib.request.urlopen(r, timeout=180))["message"]["content"].strip()
        except urllib.error.HTTPError:
            body.pop("think", None)           # a model without a thinking mode rejects the flag
    return ""


def prompt(q, ids):
    blocks = ["[%d] %s\n%s" % (n, CORPUS[i]["section_title"], CORPUS[i]["passage_text"]) for n, i in enumerate(ids, 1)]
    return "QUESTION:\n" + q + "\n\nPASSAGES:\n" + "\n\n".join(blocks)


def main(models):
    for model in models:
        chat(model, "hi", "hi")                                   # load the model so timings are fair
        ok = tot = 0; times = []; fails = []; refuse_shown = []; ratios = []
        for q in QS:
            ids = q["gold"] + [DISTRACTOR] if q["gold"] else [DISTRACTOR]
            t0 = time.time(); out = chat(model, getattr(c, os.environ.get("SYSTEM", "SYSTEM_EXPLAIN")), prompt(q["question"], ids)); dt = time.time() - t0
            src = q["question"] + "\n" + "\n".join(CORPUS[i]["passage_text"] + " " + CORPUS[i]["section_title"] for i in ids)
            if q["gold"]:
                tot += 1; times.append(dt)
                te = not c.wrong_language(q["question"], out) if any("ఀ" <= ch <= "౿" for ch in q["question"]) else True
                garble = any(c._MIXED.search(w) for w in c._WORDS5.findall(out.lower()))
                words = c._WORDS5.findall(out.lower()); low = src.lower()
                ratio = sum(1 for w in words if w[:5 if c._TELUGU.search(w) else 4] in low) / max(len(words), 1)
                grounded = ratio >= 0.75          # reported as a number; the server's own guard is stricter and is tested separately
                garble = garble or c.foreign_script(out)
                has = any(m in out for m in q["must_any"])
                ratios.append(ratio)
                good = te and not garble and grounded and has and not c.unsafe_output(out)
                ok += good
                if not good: fails.append("%s te=%s garble=%s grounded=%.2f has=%s :: %s" % (q["id"], te, garble, ratio, has, out.replace("\n", " ")[:100]))
            else:
                refuse_shown.append("%s :: %s" % (q["id"], out.replace("\n", " ")[:130]))
        print("=== %-12s correct %d/%d   median %.1fs   max %.1fs" % (model, ok, tot, sorted(times)[len(times)//2], max(times)))
        if ratios: print("   grounding ratios: min %.2f  p25 %.2f  median %.2f" % (min(ratios), sorted(ratios)[len(ratios)//4], sorted(ratios)[len(ratios)//2]))
        for f in fails: print("   FAIL", f)
        for r in refuse_shown: print("   not-covered", r)


if __name__ == "__main__":
    main(sys.argv[1:])
