import json
import logging

import httpx
import pytest

from app.core.config import get_settings
from app.services.llm import client as llm_client

PASSAGES = [
    dict(passage_id="P-1", title="Danger signs in pregnancy", text="Heavy bleeding in pregnancy is a danger sign. Refer at once."),
    dict(passage_id="P-2", title=None, text="Severe headache with blurred vision needs urgent referral."),
]
BODY = dict(question="What are the danger signs in pregnancy?", passages=PASSAGES, safety_status="NORMAL_PROTOCOL_QUERY")
URL = "/api/v1/health-qa/explain"


def _live(client):
    return client.app.dependency_overrides[get_settings]()


class Resp:
    def __init__(self, status=200, body=None):
        self.status_code, self._b = status, body

    def json(self):
        if self._b is None:
            raise ValueError("no json")
        return self._b


def chat(text="Heavy bleeding and severe headache with blurred vision are danger signs. Contact your supervisor."):
    return Resp(200, {"choices": [{"message": {"role": "assistant", "content": text}}]})


def anthropic(text="Heavy bleeding is a danger sign."):
    return Resp(200, {"content": [{"type": "text", "text": text}]})


@pytest.fixture
def local(client, monkeypatch):
    s = _live(client)
    monkeypatch.setattr(s, "llm_provider", "openai_compatible")
    monkeypatch.setattr(s, "llm_base_url", "http://village-server:11434")
    monkeypatch.setattr(s, "llm_model", "qwen2.5:3b")
    monkeypatch.setattr(s, "llm_telugu_explain", True)      # the tests below exercise Telugu; the default is off
    return s


def test_nothing_configured_is_a_clear_503(client):
    assert client.post(URL, json=BODY).status_code == 503
    s = _live(client)
    s.llm_provider = "openai_compatible"          # still pointing at the Anthropic default URL: not a local server
    r = client.post(URL, json=BODY)
    assert r.status_code == 503 and r.json()["error"]["code"] == "LLM_NOT_CONFIGURED"


def test_local_llm_gets_question_and_passages_and_answers(client, local, monkeypatch):
    seen = {}

    def fake(payload, headers, timeout, base_url):
        seen.update(payload=payload, headers=headers, timeout=timeout, base_url=base_url)
        return chat()

    monkeypatch.setattr(llm_client, "_post_chat", fake)
    r = client.post(URL, json=BODY)
    j = r.json()
    assert r.status_code == 200 and j["explanation"].startswith("Heavy bleeding")
    assert j["provider"] == "openai_compatible" and j["model"] == "qwen2.5:3b" and j["clinically_validated"] is False
    assert seen["base_url"] == "http://village-server:11434"
    assert seen["timeout"] == local.llm_timeout_seconds and local.llm_timeout_seconds < 10, "the server gives up before the phone's 10 s"
    assert "authorization" not in seen["headers"]
    msgs = seen["payload"]["messages"]
    assert msgs[0]["role"] == "system" and "ONLY the passages" in msgs[0]["content"]
    user = msgs[1]["content"]
    assert "What are the danger signs in pregnancy?" in user
    assert "[1] Danger signs in pregnancy" in user and "Heavy bleeding in pregnancy" in user and "[2]" in user and "blurred vision" in user
    assert seen["payload"]["model"] == "qwen2.5:3b" and seen["payload"]["stream"] is False


def test_local_llm_key_is_sent_only_when_set(client, local, monkeypatch):
    seen = {}
    monkeypatch.setattr(local, "local_llm_api_key", "lan-key")
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: (seen.update(h=h), chat())[1])
    client.post(URL, json=BODY)
    assert seen["h"]["authorization"] == "Bearer lan-key"


def test_anthropic_provider_works_for_explain_too(client, monkeypatch):
    s = _live(client)
    monkeypatch.setattr(s, "anthropic_api_key", "test-key-not-real")
    seen = {}
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: (seen.update(p=p), anthropic())[1])
    r = client.post(URL, json=BODY)
    assert r.status_code == 200 and r.json()["provider"] == "anthropic"
    assert "PASSAGES" in seen["p"]["messages"][0]["content"] and "ONLY the passages" in seen["p"]["system"]


def test_danger_sign_context_is_passed(client, local, monkeypatch):
    seen = {}
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: (seen.update(p=p), chat())[1])
    client.post(URL, json=dict(BODY, safety_status="ESCALATION_REQUIRED"))
    assert "danger sign" in seen["p"]["messages"][1]["content"]


def test_timeout_down_and_refusal_are_mapped_not_leaked(client, local, monkeypatch):
    def boom(exc):
        def f(p, h, t, b):
            raise exc
        return f
    monkeypatch.setattr(llm_client, "_post_chat", boom(httpx.ReadTimeout("slow")))
    r = client.post(URL, json=BODY)
    assert r.status_code == 504 and r.json()["error"]["code"] == "LLM_TIMEOUT"
    monkeypatch.setattr(llm_client, "_post_chat", boom(httpx.ConnectError("down")))
    r = client.post(URL, json=BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_UNAVAILABLE"
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: Resp(500, {"error": "echo: What are the danger signs"}))
    r = client.post(URL, json=BODY)
    assert r.status_code == 502 and "danger signs" not in r.text


@pytest.mark.parametrize("bad", [None, {}, {"choices": []}, {"choices": [{"message": {"content": ""}}]}, {"choices": [{"message": {}}]}])
def test_empty_or_odd_replies_are_an_error(client, local, monkeypatch, bad):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: Resp(200, bad))
    r = client.post(URL, json=BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_EMPTY"


@pytest.mark.parametrize("text", ["Give 500 mg every 6 hours.", "Give paracetamol for the fever.", "ఈ మాత్ర ఇవ్వండి"])
def test_a_dose_or_medicine_in_the_text_is_withheld(client, local, monkeypatch, text):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat(text))
    r = client.post(URL, json=BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_UNSAFE_OUTPUT" and "paracetamol" not in r.text


def test_long_text_is_clamped(client, local, monkeypatch):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat("heavy bleeding " * 500))
    assert len(client.post(URL, json=BODY).json()["explanation"]) == llm_client.MAX_ANSWER_CHARS


def test_validation(client, local):
    ok = dict(BODY)
    assert client.post(URL, json=dict(ok, passages=[])).status_code == 422
    assert client.post(URL, json=dict(ok, passages=PASSAGES * 3)).status_code == 422          # more than 4
    assert client.post(URL, json=dict(ok, passages=[dict(passage_id="P", text="a" * 1501)])).status_code == 422
    assert client.post(URL, json=dict(ok, question="")).status_code == 422
    assert client.post(URL, json=dict(ok, safety_status="BOGUS")).status_code == 422
    assert client.post(URL, json=dict(ok, extra="no")).status_code == 422
    assert client.post(URL, json=dict(ok, passages=[dict(passage_id="P", text="t", extra=1)])).status_code == 422


def test_a_full_size_telugu_request_fits_the_body_limit(client, local, monkeypatch):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat("ప" * 60))
    big = dict(question="ప" * 2000, passages=[dict(passage_id="P%d" % i, title="శీర్షిక", text="ప" * 1500) for i in range(4)])
    raw = json.dumps(big, ensure_ascii=False).encode("utf-8")      # the app sends raw UTF-8 (3 bytes per Telugu character), not \\u escapes
    assert 20_000 < len(raw) < 32_768
    assert client.post(URL, content=raw, headers={"content-type": "application/json"}).status_code == 200


def test_the_route_shares_the_ai_rate_limit(make_client, monkeypatch):
    c = make_client(llm_provider="openai_compatible", llm_base_url="http://village:11434", llm_rate_limit_per_minute=2)
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat())
    codes = [c.post(URL, json=BODY).status_code for _ in range(3)]
    assert codes == [200, 200, 429]


def test_question_and_passages_are_never_logged(client, local, monkeypatch, caplog):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat())
    caplog.set_level(logging.DEBUG)
    client.post(URL, json=dict(question="zebra-quokka-7731 private words", passages=[dict(passage_id="P", text="marmot-kiwi-4410 secret passage")]))
    assert "quokka" not in caplog.text and "marmot" not in caplog.text


TE_BODY = dict(question="చేతులు ఎలా కడుక్కోవాలి", passages=[dict(passage_id="P", title="Hygiene", text="అనారోగ్యంగా ఉన్న కుటుంబ సభ్యుడిని చూసే ముందు మరియు తర్వాత సబ్బుతో చేతులు కడుక్కోండి.")])


def test_a_telugu_question_needs_a_telugu_explanation(client, local, monkeypatch):
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat("Wash your hands with soap before and after visiting a sick family member."))
    r = client.post(URL, json=TE_BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_WRONG_LANGUAGE"
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat("అనారోగ్యంగా ఉన్న కుటుంబ సభ్యుడిని చూసే ముందు మరియు తర్వాత సబ్బుతో చేతులు కడుక్కోండి."))
    r = client.post(URL, json=TE_BODY)
    assert r.status_code == 200 and "సబ్బుతో" in r.json()["explanation"]


def test_an_explanation_that_leaves_the_passages_is_refused(client, local, monkeypatch):
    drift = "Hygiene is crucial for maintaining good health. Avoid touching your eyes, nose and mouth, especially after using the toilet."
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat(drift))
    r = client.post(URL, json=BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_NOT_GROUNDED"
    assert not llm_client.not_grounded("If nobody is at home, record the visit as not done and plan a new visit.",
                                       "What if nobody is at home? If nobody is at home, record the visit as not done and plan a new visit date.")
    assert llm_client.not_grounded("", "anything")


def test_garbled_telugu_is_refused_but_a_faithful_telugu_explanation_passes(client, local, monkeypatch):
    garbled = "చేతులు కడుక్కోవడం అని అనారోగ్యంగా ఉన్న కుటుంబ సభ్యుడి మరియు తర్వాత సబ్బుతో చేతులు కడుక్కోండి. ఈ పాస్ఫ్రెంచులో కొత్త సమాచారంగా ఉపయోgable కావాలంటే అని చూపాయావచ్చు."
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat(garbled))
    r = client.post(URL, json=TE_BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_NOT_GROUNDED"
    faithful = "అనారోగ్యంగా ఉన్న కుటుంబ సభ్యుడిని చూసే ముందు మరియు తర్వాత సబ్బుతో చేతులు కడుక్కోండి."
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: chat(faithful))
    assert client.post(URL, json=TE_BODY).status_code == 200
    assert llm_client.not_grounded("అనారోగ్యంగా ఉపయోgable సబ్బుతో", "అనారోగ్యంగా ఉపయోగ సబ్బుతో")      # mixed-script word


def test_telugu_explanations_are_off_by_default_and_the_model_is_not_called(client, monkeypatch):
    s = _live(client)
    monkeypatch.setattr(s, "llm_provider", "openai_compatible")
    monkeypatch.setattr(s, "llm_base_url", "http://village-server:11434")
    called = []
    monkeypatch.setattr(llm_client, "_post_chat", lambda p, h, t, b: (called.append(1), chat())[1])
    r = client.post(URL, json=TE_BODY)
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_WRONG_LANGUAGE" and not called
    assert client.post(URL, json=BODY).status_code == 200 and called          # English is unaffected
