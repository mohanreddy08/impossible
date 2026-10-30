import logging

import httpx
import pytest

from app.services.llm import client as llm_client
from app.core.config import get_settings


def _live_settings(client):
    return client.app.dependency_overrides[get_settings]()      # the Settings object the app under test actually uses


@pytest.fixture
def configured(client, monkeypatch):
    s = _live_settings(client)
    monkeypatch.setattr(s, "anthropic_api_key", "test-key-not-real")
    return s


class FakeResp:
    def __init__(self, status=200, body=None):
        self.status_code, self._b = status, body

    def json(self):
        if self._b is None:
            raise ValueError("no json")
        return self._b


def ok(text="Take the person to the health centre now."):
    return FakeResp(200, {"content": [{"type": "text", "text": text}]})


def test_not_configured_is_a_clear_503(client, monkeypatch):
    monkeypatch.setattr(_live_settings(client), "anthropic_api_key", None)
    r = client.post("/api/v1/health-qa/llm", json=dict(question="fever for two days"))
    assert r.status_code == 503 and r.json()["error"]["code"] == "LLM_NOT_CONFIGURED"


def test_success_returns_answer_labelled_not_validated(client, configured, monkeypatch):
    seen = {}

    def fake(payload, headers, timeout, base_url=None):
        seen.update(payload=payload, headers=headers, timeout=timeout)
        return ok()

    monkeypatch.setattr(llm_client, "_post", fake)
    r = client.post("/api/v1/health-qa/llm", json=dict(question="child has fever", safety_status="NORMAL_PROTOCOL_QUERY"))
    j = r.json()
    assert r.status_code == 200 and j["answer"] == "Take the person to the health centre now."
    assert j["clinically_validated"] is False and "Not clinically verified" in j["disclaimer"]
    assert seen["headers"]["x-api-key"] == "test-key-not-real" and seen["timeout"] == configured.llm_timeout_seconds
    assert seen["payload"]["messages"][0]["content"] == "child has fever"
    assert "Never name medicines" in seen["payload"]["system"]


def test_danger_sign_context_is_passed_to_the_model(client, configured, monkeypatch):
    seen = {}
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: (seen.update(p=p), ok())[1])
    client.post("/api/v1/health-qa/llm", json=dict(question="pregnant woman bleeding heavily", safety_status="ESCALATION_REQUIRED"))
    assert "danger sign" in seen["p"]["messages"][0]["content"]


def test_timeout_and_network_errors_are_mapped_not_leaked(client, configured, monkeypatch):
    def boom(exc):
        def f(p, h, t, b=None):
            raise exc
        return f
    monkeypatch.setattr(llm_client, "_post", boom(httpx.ReadTimeout("slow")))
    r = client.post("/api/v1/health-qa/llm", json=dict(question="x question"))
    assert r.status_code == 504 and r.json()["error"]["code"] == "LLM_TIMEOUT"
    monkeypatch.setattr(llm_client, "_post", boom(httpx.ConnectError("down")))
    r = client.post("/api/v1/health-qa/llm", json=dict(question="x question"))
    assert r.status_code == 502 and r.json()["error"]["code"] == "LLM_UNAVAILABLE"


def test_upstream_error_body_is_not_copied_into_the_response(client, configured, monkeypatch):
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: FakeResp(429, {"error": {"message": "echo: my secret question text"}}))
    r = client.post("/api/v1/health-qa/llm", json=dict(question="my secret question text"))
    assert r.status_code == 502 and "secret question" not in r.text


def test_empty_answer_is_an_error_and_long_answers_are_clamped(client, configured, monkeypatch):
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: FakeResp(200, {"content": []}))
    assert client.post("/api/v1/health-qa/llm", json=dict(question="q one")).status_code == 502
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: ok("x" * 5000))
    assert len(client.post("/api/v1/health-qa/llm", json=dict(question="q one")).json()["answer"]) == llm_client.MAX_ANSWER_CHARS


def test_the_question_is_never_logged(client, configured, monkeypatch, caplog):
    monkeypatch.setattr(llm_client, "_post", lambda p, h, t, b=None: ok())
    caplog.set_level(logging.DEBUG)
    client.post("/api/v1/health-qa/llm", json=dict(question="zebra-quokka-7731 private words"))
    assert "quokka" not in caplog.text


def test_validation(client, configured):
    assert client.post("/api/v1/health-qa/llm", json=dict(question="")).status_code == 422
    assert client.post("/api/v1/health-qa/llm", json=dict(question="a" * 2001)).status_code == 422
    assert client.post("/api/v1/health-qa/llm", json=dict(question="ok", safety_status="BOGUS")).status_code == 422
    assert client.post("/api/v1/health-qa/llm", json=dict(question="ok", extra="no")).status_code == 422
