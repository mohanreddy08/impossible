import httpx
import pytest

from app.core.config import Settings, get_settings
from app.services.llm import client as llm_client
from app.services.protocol_retrieval.service import PassageRecord, ProtocolIndex
from app.services.rag import embedder, service as rag

FIX = ("TEST_FIXTURE_ONLY",)
TE_HANDS = "అనారోగ్యంగా ఉన్న కుటుంబ సభ్యుడిని చూసే ముందు మరియు తర్వాత సబ్బుతో చేతులు కడుక్కోండి."
EN_HANDS = "Wash your hands with soap before and after seeing a sick family member."
TE_FEED = "నవజాత శిశువు సరిగా పాలు తాగకపోవడం ప్రమాద సంకేతం. వెంటనే సూపర్‌వైజింగ్ వైద్యాధికారిని సంప్రదించండి."
EN_BLEED = "Heavy bleeding in a pregnant woman is a danger sign. Contact the supervising medical officer at once."

RECORDS = [
    PassageRecord("P-HANDS-EN", "DOC", "Sample", "v0", "hands", "Hygiene", 1, EN_HANDS, "TEST_FIXTURE_ONLY", True, "en"),
    PassageRecord("P-HANDS-TE", "DOC", "Sample", "v0", "hands", "Hygiene", 1, TE_HANDS, "TEST_FIXTURE_ONLY", True, "te"),
    PassageRecord("P-FEED-TE", "DOC2", "Sample 2", "v0", "feed", "పాలు తాగకపోవడం", 2, TE_FEED, "TEST_FIXTURE_ONLY", True, "te"),
    PassageRecord("P-BLEED-EN", "DOC3", "Sample 3", "v0", "bleed", "Bleeding", 3, EN_BLEED, "TEST_FIXTURE_ONLY", True, "en"),
]
# one dimension per CONCEPT, in either language: a stand-in for a multilingual embedding model
CONCEPTS = [["wash", "hands", "చేతులు", "కడుక్కో"], ["milk", "feed", "పాలు", "తాగ"], ["bleeding", "రక్తస్రావం"]]


def vec(text):
    t = text.lower()
    return [float(sum(t.count(w) for w in group)) for group in CONCEPTS]


class Resp:
    def __init__(self, status=200, body=None):
        self.status_code, self._b = status, body

    def json(self):
        if self._b is None:
            raise ValueError("no json")
        return self._b


@pytest.fixture
def world(monkeypatch):
    """Fake embedding service + fake LLM + a fixed passage index. world.calls counts what was used."""
    embedder.clear_cache()
    w = type("W", (), {})()
    w.embed_calls = []
    w.llm_calls = []
    w.llm_reply = lambda payload: Resp(200, {"message": {"content": TE_HANDS}})
    w.embed_down = False

    def fake_embed(payload, timeout, base_url):
        w.embed_calls.append(payload["input"])
        if w.embed_down:
            raise httpx.ConnectError("down")
        return Resp(200, {"embeddings": [vec(t) for t in payload["input"]]})

    def fake_llm(payload, timeout, base_url):
        w.llm_calls.append(payload)
        return w.llm_reply(payload)

    monkeypatch.setattr(embedder, "_post_embed", fake_embed)
    monkeypatch.setattr(llm_client, "_post_ollama", fake_llm)
    monkeypatch.setattr(rag, "get_index", lambda db, elig: ProtocolIndex(RECORDS, FIX))
    w.s = Settings(llm_provider="ollama", llm_base_url="http://village:11434", llm_model="qwen3:8b", rag_embed_model="bge-m3",
                   database_url="sqlite://", auth_mode="disabled", eligible_verification_statuses="TEST_FIXTURE_ONLY",
                   rag_direct_max_words=0)          # these tests exercise the model path; the short-passage shortcut has its own test
    return w


def ask(w, q, **kw):
    s = w.s.model_copy(update=kw) if kw else w.s
    return rag.answer(None, s, q)


def test_a_telugu_question_gets_the_telugu_passage_and_a_model_answer(world):
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి")
    assert r["outcome"] == "ANSWERED" and r["language"] == "te" and r["retrieval"] == "embedding" and r["embedder"] == "bge-m3"
    assert [x["passage_id"] for x in r["sources"]] == ["P-HANDS-TE"], "the Telugu version of the section, not the English one"
    assert r["answer_source"] == "llm" and r["answer"] == TE_HANDS and r["model"] == "qwen3:8b" and r["llm_error"] is None
    user = world.llm_calls[0]["messages"][1]["content"]
    assert "చేతులు ఎలా కడుక్కోవాలి" in user and TE_HANDS in user and EN_HANDS not in user
    assert world.llm_calls[0]["think"] is False and world.llm_calls[0]["options"]["temperature"] == 0


def test_an_english_question_gets_the_english_passage(world):
    world.llm_reply = lambda p: Resp(200, {"message": {"content": "Wash your hands with soap before and after seeing a sick family member."}})
    r = ask(world, "How should I wash my hands?")
    assert [x["passage_id"] for x in r["sources"]] == ["P-HANDS-EN"] and r["answer_source"] == "llm"


def test_nothing_close_enough_means_no_approved_text_and_the_model_is_never_called(world):
    r = ask(world, "మలేరియాకు చికిత్స ఏమిటి")
    assert r["outcome"] == "NO_APPROVED_TEXT" and r["sources"] == [] and r["answer"] is None and not world.llm_calls
    assert "ఆమోదిత" in r["message"]                                        # said in Telugu
    r = ask(world, "How do I treat malaria?")
    assert r["outcome"] == "NO_APPROVED_TEXT" and r["message"].startswith("No approved") and not world.llm_calls


def test_a_danger_sign_is_never_answered_by_the_model(world):
    r = ask(world, "Pregnant woman is bleeding heavily right now")
    assert r["outcome"] == "ESCALATION_REQUIRED" and r["answer"] is None and r["message"] and not world.llm_calls
    assert [x["passage_id"] for x in r["sources"]] == ["P-BLEED-EN"], "the approved text is returned as support"
    assert r["safety"]["status"] == "ESCALATION_REQUIRED" and r["safety"]["rule_ids"]


def test_unclear_and_out_of_scope_questions_do_no_retrieval_and_no_model_call(world):
    r = ask(world, "జ్వరం వస్తే ఏమి చేయాలి")
    assert r["outcome"] == "CLARIFICATION_REQUIRED" and not world.llm_calls and not world.embed_calls
    r = ask(world, "What dose of paracetamol should I give a baby?")
    assert r["outcome"] == "OUT_OF_SCOPE" and r["answer"] is None and not world.llm_calls and not world.embed_calls


@pytest.mark.parametrize("reply,code", [
    ("Wash your hands with soap before and after seeing a sick family member.", "LLM_WRONG_LANGUAGE"),        # English for a Telugu question
    ("చేతులు కడుక్కోండి గర్భಿణీ", "LLM_WRONG_LANGUAGE"),                                                        # a Kannada letter inside a Telugu word
    ("ఈ పాస్ఫ్రెంచులో బట్టండి కొత్త సమాచారంగా చూపాయావచ్చు ఉపయోగకరంగా కావాలంటే అని", "LLM_NOT_GROUNDED"),        # Telugu-looking nonsense
    ("సబ్బుతో 500 mg మందు ఇవ్వండి", "LLM_UNSAFE_OUTPUT"),
])
def test_a_bad_model_answer_is_dropped_and_the_approved_passage_is_the_answer(world, reply, code):
    world.llm_reply = lambda p: Resp(200, {"message": {"content": reply}})
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి")
    assert r["outcome"] == "ANSWERED" and r["answer_source"] == "extract" and r["answer"] == TE_HANDS and r["llm_error"] == code


def test_a_slow_or_dead_model_still_gives_the_approved_passage(world, monkeypatch):
    def boom(payload, timeout, base_url):
        raise httpx.ReadTimeout("slow")
    monkeypatch.setattr(llm_client, "_post_ollama", boom)
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి")
    assert r["answer_source"] == "extract" and r["answer"] == TE_HANDS and r["llm_error"] == "LLM_TIMEOUT"
    monkeypatch.setattr(llm_client, "_post_ollama", lambda p, t, b: (_ for _ in ()).throw(httpx.ConnectError("down")))
    assert ask(world, "చేతులు ఎలా కడుక్కోవాలి")["llm_error"] == "LLM_UNAVAILABLE"


def test_the_model_gets_only_what_is_left_of_the_time_budget(world):
    seen = {}
    orig = llm_client._post_ollama

    def spy(payload, timeout, base_url):
        seen["t"] = timeout
        return orig(payload, timeout, base_url)
    llm_client._post_ollama = spy
    try:
        ask(world, "చేతులు ఎలా కడుక్కోవాలి")
        assert 1.5 <= seen["t"] <= world.s.rag_budget_seconds
        world.llm_calls.clear()
        r = ask(world, "చేతులు ఎలా కడుక్కోవాలి", rag_budget_seconds=1.0)      # no time for a model: approved text at once
        assert r["answer_source"] == "extract" and r["llm_error"] == "no_time" and not world.llm_calls
    finally:
        llm_client._post_ollama = orig


def test_no_llm_configured_still_answers_with_the_approved_text(world):
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి", llm_provider="anthropic", llm_base_url="https://api.anthropic.com",
             rag_embed_base_url="http://village:11434")      # a cloud LLM without a key, but local embeddings
    assert r["outcome"] == "ANSWERED" and r["answer_source"] == "extract" and r["llm_error"] == "not_configured"


def test_embedding_service_down_falls_back_to_keyword_search(world):
    world.embed_down = True
    r = ask(world, "wash hands soap family member")
    assert r["retrieval"] == "keyword" and r["embedder"] is None and r["outcome"] == "ANSWERED" and r["sources"][0]["passage_id"] == "P-HANDS-EN"
    assert ask(world, "మలేరియాకు చికిత్స ఏమిటి")["outcome"] == "NO_APPROVED_TEXT"


def test_passage_vectors_are_computed_once(world):
    ask(world, "చేతులు ఎలా కడుక్కోవాలి")
    ask(world, "How should I wash my hands?")
    passage_batches = [c for c in world.embed_calls if len(c) > 1]
    assert len(passage_batches) == 1 and len(passage_batches[0]) == len(RECORDS), "the library is embedded once, then cached"


def test_the_cache_survives_a_restart(world, tmp_path):
    path = str(tmp_path / "vec.json")
    ask(world, "చేతులు ఎలా కడుక్కోవాలి", rag_cache_path=path)
    embedder.clear_cache()                        # a new process
    world.embed_calls.clear()
    ask(world, "చేతులు ఎలా కడుక్కోవాలి", rag_cache_path=path)
    assert all(len(c) == 1 for c in world.embed_calls), "only the question is embedded; the passages came from the file"


def test_pick_one_passage_per_section_prefers_the_question_language_and_the_best_band():
    a = PassageRecord("a-en", "D", "T", "v", "s1", "t", 1, "x", "V", True, "en")
    b = PassageRecord("a-te", "D", "T", "v", "s1", "t", 1, "x", "V", True, "te")
    c = PassageRecord("c", "D", "T", "v", "s2", "t", 1, "x", "V", True, "te")
    d = PassageRecord("d", "D", "T", "v", "s3", "t", 1, "x", "V", True, "te")
    got = rag._pick([(0.80, a), (0.78, b), (0.75, c), (0.50, d)], "te", 0.45, 3)
    assert [p.passage_id for _, p in got] == ["a-te", "c"], "Telugu variant of s1; d is too far below the best"
    assert [p.passage_id for _, p in rag._pick([(0.80, a), (0.78, b)], "en", 0.45, 3)] == ["a-en"]
    assert rag._pick([(0.40, a)], "te", 0.45, 3) == []


def test_the_prompt_is_short_and_direct():
    sp = llm_client.SYSTEM_RAG
    assert "ONLY the numbered PASSAGES" in sp and "Telugu script" in sp and "ONE short sentence" in sp and "no preface" in sp


# ------------------------------------------------------------------------------------------------------ the HTTP route
@pytest.fixture
def served(client, world, monkeypatch):
    s = client.app.dependency_overrides[get_settings]()
    for k, v in dict(llm_provider="ollama", llm_base_url="http://village:11434", llm_model="qwen3:8b", eligible_verification_statuses="TEST_FIXTURE_ONLY", rag_direct_max_words=0).items():
        monkeypatch.setattr(s, k, v)
    return client


def test_route_returns_the_documented_shape(served):
    r = served.post("/api/v1/health-qa/rag", json=dict(question="చేతులు ఎలా కడుక్కోవాలి"))
    j = r.json()
    assert r.status_code == 200 and j["outcome"] == "ANSWERED" and j["answer_source"] == "llm" and j["clinically_validated"] is False
    src = j["sources"][0]
    assert src["passage_id"] == "P-HANDS-TE" and src["source_verification_status"] == "TEST_FIXTURE_ONLY" and src["text"] == TE_HANDS
    assert {"retrieve", "generate"} <= set(j["timings_ms"]) and j["safety"]["status"] == "NORMAL_PROTOCOL_QUERY"


def test_route_validation_and_switch(served, monkeypatch):
    assert served.post("/api/v1/health-qa/rag", json=dict(question="")).status_code == 422
    assert served.post("/api/v1/health-qa/rag", json=dict(question="a" * 2001)).status_code == 422
    assert served.post("/api/v1/health-qa/rag", json=dict(question="ok", extra=1)).status_code == 422
    monkeypatch.setattr(served.app.dependency_overrides[get_settings](), "rag_enabled", False)
    r = served.post("/api/v1/health-qa/rag", json=dict(question="చేతులు ఎలా కడుక్కోవాలి"))
    assert r.status_code == 404 and r.json()["error"]["code"] == "RAG_DISABLED"


def test_route_shares_the_ai_rate_limit(make_client, world):
    c = make_client(llm_provider="ollama", llm_base_url="http://village:11434", llm_rate_limit_per_minute=2, eligible_verification_statuses="TEST_FIXTURE_ONLY")
    codes = [c.post("/api/v1/health-qa/rag", json=dict(question="చేతులు ఎలా కడుక్కోవాలి")).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_the_question_is_never_logged(served, caplog):
    import logging
    caplog.set_level(logging.DEBUG)
    served.post("/api/v1/health-qa/rag", json=dict(question="zebra-quokka-7731 చేతులు private words"))
    assert "quokka" not in caplog.text


def test_an_answer_cut_off_by_the_length_cap_is_refused(world):
    world.llm_reply = lambda p: Resp(200, {"message": {"content": TE_HANDS[:40]}, "done_reason": "length"})
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి")
    assert r["answer_source"] == "extract" and r["llm_error"] == "LLM_TRUNCATED" and r["answer"] == TE_HANDS
    assert world.llm_calls[0]["options"]["num_predict"] == world.s.rag_answer_max_tokens


def test_a_short_best_passage_is_the_answer_word_for_word_and_the_model_is_not_called(world):
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి", rag_direct_max_words=60)
    assert r["outcome"] == "ANSWERED" and r["answer_source"] == "extract" and r["answer"] == TE_HANDS and r["llm_error"] is None
    assert not world.llm_calls and "word for word" in r["message"]
    assert [x["passage_id"] for x in r["sources"]] == ["P-HANDS-TE"]
    r = ask(world, "చేతులు ఎలా కడుక్కోవాలి", rag_direct_max_words=5)       # a longer passage than the limit goes to the model
    assert r["answer_source"] == "llm" and world.llm_calls


def test_route_with_the_default_settings_answers_a_short_passage_without_the_model(client, world, monkeypatch):
    s = client.app.dependency_overrides[get_settings]()
    for k, v in dict(llm_provider="ollama", llm_base_url="http://village:11434", eligible_verification_statuses="TEST_FIXTURE_ONLY").items():
        monkeypatch.setattr(s, k, v)
    assert s.rag_direct_max_words == 60
    j = client.post("/api/v1/health-qa/rag", json=dict(question="చేతులు ఎలా కడుక్కోవాలి")).json()
    assert j["answer"] == TE_HANDS and j["answer_source"] == "extract" and not world.llm_calls
