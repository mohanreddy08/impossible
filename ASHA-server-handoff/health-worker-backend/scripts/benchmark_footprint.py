#!/usr/bin/env python3
"""Footprint of the server-side answer path, measured on THIS machine, CPU only (Ollama option num_gpu=0 forces CPU):
model size on disk, resident memory of the model process, embedding latency, retrieval + answer latency over the Telugu question set
(approved-passage path, no LLM) and, optionally, the LLM path. Prints a table; nothing here is estimated.

  OLLAMA=127.0.0.1:11500 .venv/bin/python scripts/benchmark_footprint.py [--llm]
"""
import json, os, statistics as st, subprocess, sys, time, urllib.request

OLL = "http://" + os.environ.get("OLLAMA", "127.0.0.1:11500")
EMB, LLM = os.environ.get("EMBED_MODEL", "bge-m3"), os.environ.get("LLM_MODEL", "qwen3:8b")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)


def post(path, body, t=300):
    r = urllib.request.Request(OLL + path, json.dumps(body).encode(), {"content-type": "application/json"})
    return json.load(urllib.request.urlopen(r, timeout=t))


def loaded_mb(name):
    """Memory Ollama reports for the loaded model (weights + context), from /api/ps."""
    for m in json.load(urllib.request.urlopen(OLL + "/api/ps"))["models"]:
        if m["name"].split(":")[0] == name.split(":")[0] and (":" not in name or m["name"] == name or name.endswith(":latest")):
            return round(m["size"] / 1e6)
    return 0


def pct(xs, p):
    xs = sorted(xs); return xs[min(len(xs) - 1, int(round(p / 100 * (len(xs) - 1))))]


tags = {m["name"]: m["size"] / 1e6 for m in json.load(urllib.request.urlopen(OLL + "/api/tags"))["models"]}
rows = [("embedding model %s on disk (MB)" % EMB, round(tags.get(EMB + ":latest", tags.get(EMB, 0))))]
qs = [json.loads(l)["question"] for l in open(os.path.join(ROOT, "eval", "telugu_rag_questions.jsonl"), encoding="utf-8") if l.strip()]

post("/api/embed", {"model": EMB, "input": "warm", "options": {"num_gpu": 0}, "keep_alive": "10m"})
ts = []
for q in qs:
    t = time.time(); post("/api/embed", {"model": EMB, "input": q, "options": {"num_gpu": 0}, "keep_alive": "10m"}); ts.append((time.time() - t) * 1000)
rows += [("embedding model loaded in memory (MB, CPU)", loaded_mb(EMB)),
         ("question embedding, CPU only: median / p95 (ms)", "%d / %d" % (st.median(ts), pct(ts, 95)))]

if "--llm" in sys.argv:
    rows.append(("LLM %s on disk (MB)" % LLM, round(tags.get(LLM, 0))))
    t = time.time()
    r = post("/api/chat", {"model": LLM, "stream": False, "think": False, "keep_alive": "5m",
                           "options": {"num_gpu": 0, "temperature": 0, "num_predict": 48},
                           "messages": [{"role": "user", "content": "చేతులు ఎలా కడుక్కోవాలి? ఒక వాక్యంలో చెప్పండి."}]})
    dt = time.time() - t; n = r.get("eval_count", 0)
    rows += [("LLM loaded in memory (MB, CPU)", loaded_mb(LLM)),
             ("LLM CPU generation (tokens/s, Telugu)", round(n / max(r.get("eval_duration", 1) / 1e9, 1e-9), 1)),
             ("LLM 48-token Telugu answer, CPU (s)", round(dt, 1))]
    post("/api/chat", {"model": LLM, "keep_alive": 0, "messages": []})

print("\n| measurement | value |\n|---|---|")
for k, v in rows: print("| %s | %s |" % (k, v))
