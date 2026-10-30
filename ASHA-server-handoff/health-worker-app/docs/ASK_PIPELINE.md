# The Ask page pipeline

```
type OR speak ──► one text box ──► (1) safety rules ──► (2) embed ──► (3) vector search ──► closest approved passages
                                      on the phone         on the phone    on the phone               │
                                                                                                      ▼
                                                              (4) network?  ── yes, AI help on, server set ──► server → local LLM  ─┐ 10 s limit
                                                                            ── no / off / slow / failing  ──► phone's explainer ◄───┘ falls back
                                                                                                      │
                                                                                                      ▼
                                              (5) ONE explanation card (same shape either way)  +  (6) severity strip and action
```

## What each step is in the code

| Step | What happens | Where |
|---|---|---|
| 1. Type or speak | Voice is turned into text first (phone's offline pack, the app's own Telugu model, or online speech if switched on). It only fills the same text box; the worker presses Check. | `lib/presentation/screens/ask_screen.dart`, `lib/services/voice_input.dart`, `lib/services/telugu_voice.dart` |
| 2. Embedding | 512-number int8 vector from character n-grams (`hashing-ngram-v1`), identical in Python and Dart. It is a lexical embedding, not a neural one: it matches wording, not meaning. | `lib/domain/retrieval/` (`HashingEmbedder`) |
| 3. Vector search | Hybrid: keyword score + cosine similarity over the stored vectors (`passage_vectors` table), with a topic guard. | `lib/domain/retrieval/local_retrieval.dart`, `lib/services/protocol_library.dart` |
| 4. Network check | `online = connectivity && "Online AI help" switch && server address set`. Online: send the question and the closest passages to the server's LLM. Otherwise, or if it is slow (10 s) or fails or answers with a dose/medicine: the phone's own explainer. | `QaService.explain` in `lib/services/qa_service.dart` |
| 4a. Server | `POST /api/v1/health-qa/explain` -> LLM (a local model on a nearby server, or Anthropic) with a prompt that allows only what the passages say. | `health-worker-backend/app/api/v1/health_qa.py`, `app/services/llm/client.py` |
| 4b. On the phone | `OfflineExplainer`: picks the sentences of the closest passages that best match the question and lists them. Every word comes from approved text; nothing is generated. | `lib/services/explainer.dart` |
| 5. Same output | Both end in an `Explanation { text, source, severity, fallback }` shown in one card; the card says which source wrote it and why a fallback happened. | `_ExplanationCard` in `ask_screen.dart` |
| 6. Severity + action | Decided only by the phone's deterministic safety rules, never by the AI: **high** = possible danger sign (red alert, supervisor call button, firm vibration), **medium** = unclear (tap-to-add-details buttons), **low** = no danger sign found (information only). | `severityOf` in `explainer.dart`, `_SeverityStrip` in `ask_screen.dart` |

Rules that never change: no approved passage found means nothing is explained (no AI call, "No verified answer"); the AI text is dropped if it names a medicine or a dose (checked on the server and again on the phone); the question and passages are never logged or saved; the danger-sign alert appears before and above any explanation.

## Folder structure (files for this feature)

```
health-worker-app/
  lib/
    services/
      qa_service.dart          ask() = rules + search;  explain() = server LLM or phone, 10 s limit
      explainer.dart           Severity, Explanation, OfflineExplainer
    data/api/api_client.dart   explain(): POST /health-qa/explain
    presentation/screens/ask_screen.dart   Ask page: severity strip, explanation card, spinner
    l10n/ (generated from tool/gen_arb.py)  English + Telugu texts
  test/
    explain_test.dart          26 tests: explainer, severity, online/offline/timeout/unsafe, Ask screen
  docs/ASK_PIPELINE.md         this file
health-worker-backend/
  app/api/v1/health_qa.py      POST /health-qa/explain (and the older /llm)
  app/services/llm/client.py   complete(): Anthropic or local OpenAI-compatible LLM; prompts; dose/medicine guard
  app/schemas/api.py           ExplainIn / ExplainOut
  app/core/config.py           llm_provider, llm_base_url, llm_model, llm_timeout_seconds
  app/core/hardening.py        explain shares the AI rate limit
  app/tests/test_explain.py    both providers, timeouts, guard, limits, logging
```

## Server: the nearby LLM (Ollama example)

```bash
ollama pull qwen2.5:3b                       # any model Ollama serves; small ones are fast, big ones are better
export LLM_PROVIDER=openai_compatible
export LLM_BASE_URL=http://127.0.0.1:11434   # the village server's address
export LLM_MODEL=qwen2.5:3b
export LLM_TIMEOUT_SECONDS=8.5               # keep under the phone's 10 s
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
Cloud instead: `LLM_PROVIDER=anthropic ANTHROPIC_API_KEY=...`. llama.cpp's `llama-server` and vLLM work like Ollama (`/v1/chat/completions`). `LOCAL_LLM_API_KEY` only if that server wants a bearer key.

On the phone: Settings -> server address (+ key), switch on **Online AI help**. It is OFF by default because turning it on sends the question and passages off the phone.

## How to test both paths

**Automated (no phone needed)**
```bash
cd health-worker-app && flutter test test/explain_test.dart      # phone side, both paths + timeout
cd health-worker-backend && .venv/bin/python -m pytest app/tests/test_explain.py
cd health-worker-app && bash tool/run_backend_integration.sh     # against a real server
```

**On a phone, network path** (Online AI help on, server set, Wi-Fi on): ask "What should I do if nobody is at home during a visit?" The spinner "Asking the AI server… (up to 10 seconds)" shows, then the card says "Explained by your server's AI".

**On a phone, no-network path:** turn Wi-Fi and mobile data off (or use airplane mode), ask the same question: the card appears at once and says "Explained on this phone". With adb: `adb shell svc wifi disable; adb shell svc data disable` (and `enable` afterwards).

**Timeout path:** make the LLM slow (e.g. a stand-in that sleeps 15 s) and set `LLM_TIMEOUT_SECONDS=30` so the server does not give up first: after 10 s the card says "The server did not answer in 10 seconds, so the phone explained it itself."

## Honest limits
- The "lightweight library" on the phone is written in Dart, not Python: Python cannot run inside a Flutter app without bundling CPython (tens of MB and a new build). It plays the same role.
- The embedding is a hashing n-gram one; a neural multilingual embedding would match meaning better but needs a model of about 100 MB.
- Small local LLMs write Telugu much worse than English; the phone's explainer is the dependable Telugu path.
- The offline explainer quotes approved text; it does not rephrase or combine it, so it can be stiff.
- The saved-AI-answers cache of the old design is no longer used (its table stays in the database, unused).


## Update: server RAG and rules v0.3.0
`POST /health-qa/rag` (bge-m3 retrieval, approved passage as the answer, optional qwen3:8b for long passages) is called after the phone's own search, online only. If the closest passage is a danger-sign passage it is raised as an alert. Rules v0.3.0-draft: any bleeding in pregnancy/after delivery escalates; spoken and misspelled Telugu variants are covered (`eval/danger_variants.jsonl`).
