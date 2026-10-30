"""Optional AI text for the Ask screen. Two providers, chosen by LLM_PROVIDER:

  anthropic          the Anthropic Messages API (needs ANTHROPIC_API_KEY)
  openai_compatible  a LOCAL LLM on a nearby server: Ollama, llama.cpp's llama-server, vLLM or anything that serves
                     POST {LLM_BASE_URL}/v1/chat/completions (no key needed; LOCAL_LLM_API_KEY if the server wants one)

The question and passages are forwarded to the provider and are NEVER logged or stored here. The text is not clinically validated:
it is always labelled as such by the caller, and every answer passes the deterministic dose/medicine check below."""
import re
from typing import Optional

import httpx

from app.core.config import Settings
from app.core.errors import DomainError

MAX_ANSWER_CHARS = 1500

SYSTEM = (
    "You help ASHA community health workers in rural India. Reply in the SAME language as the question (English or Telugu), "
    "in plain simple words, in under 120 words. You are not a doctor and this is not a diagnosis. Never name medicines, doses or "
    "prescriptions. If the question describes an emergency or a possible danger sign, say FIRST that the worker must contact the "
    "supervising medical officer or take the person to the nearest health facility immediately. If you are not sure, say so. "
    "Do not invent guidelines, numbers or citations."
)


SYSTEM_EXPLAIN = (
    "You explain approved health-protocol text to ASHA community health workers in rural India. You are given a QUESTION and one or "
    "more PASSAGES taken from approved protocols. Write a short, clear explanation (under 120 words) of what the passages say that "
    "answers the question, using ONLY the passages. Reply in the SAME language as the question (English or Telugu), in plain simple "
    "words. Do not add facts, numbers, medicines, doses or advice that are not in the passages. If the passages do not answer the "
    "question, say exactly that and tell the worker to ask the supervising medical officer. If the phone's safety check flagged a "
    "possible danger sign, say FIRST that the worker must contact the supervising medical officer or take the person to the nearest "
    "health facility immediately. You are not a doctor and this is not a diagnosis."
)

# Server-side RAG (app/services/rag): short, direct answers. Telugu costs many tokens per word, so a long answer is also a slow one.
SYSTEM_RAG = (
    "You answer questions from ASHA community health workers in rural India using ONLY the numbered PASSAGES. "
    "Write the answer in the SAME language as the question; if the question is in Telugu, answer ONLY in Telugu script. "
    "Give the answer directly in ONE short sentence (at most 25 words; a second only if really needed): no greeting, no preface, no labels such as 'Answer', "
    "no repeating the question, no passage numbers. Use the passages' own words. Do not add facts, advice, medicines or doses that are "
    "not in the passages. If the passages do not answer the question, reply with exactly one short sentence saying the approved text "
    "has no information on it and that the worker should ask the supervising medical officer. If a passage says something is a danger "
    "sign, say first that the worker must contact the supervising medical officer. This is not a diagnosis."
)

# The prompt forbids doses and medicine names, but a prompt is a request, not a guarantee. This deterministic check runs on every answer
# before it is returned: a dose, a tablet count or a named medicine means the answer is withheld (the phone then shows no AI box).
_DOSE = re.compile(r"\b\d+(?:[.,]\d+)?\s*(?:mg|mcg|µg|ug|ml|g|iu|units?|drops?|tablets?|tabs?|capsules?|sachets?|spoons?|teaspoons?)\b", re.I)
_WORDS = re.compile(r"\b(?:tablets?|capsules?|syrup|injection|dosage|dose|doses|antibiotics?|paracetamol|acetaminophen|ibuprofen|aspirin|amoxicillin|"
                    r"azithromycin|ciprofloxacin|metronidazole|diclofenac|cetirizine|prednisolone)\b|మాత్ర|మోతాదు|సిరప్|ఇంజెక్షన్|యాంటీబయాటిక్", re.I)


def unsafe_output(text: str) -> bool:
    return bool(_DOSE.search(text) or _WORDS.search(text))


def _post(payload: dict, headers: dict, timeout: float, base_url: str = "https://api.anthropic.com") -> httpx.Response:
    """Anthropic: the only place that touches the network for that provider (replaced in tests)."""
    return httpx.post(base_url.rstrip("/") + "/v1/messages", json=payload, headers=headers, timeout=timeout)


def _post_chat(payload: dict, headers: dict, timeout: float, base_url: str) -> httpx.Response:
    """OpenAI-compatible local LLM (Ollama, llama-server, vLLM): the only place that touches the network for that provider."""
    return httpx.post(base_url.rstrip("/") + "/v1/chat/completions", json=payload, headers=headers, timeout=timeout)


def _post_ollama(payload: dict, timeout: float, base_url: str) -> httpx.Response:
    """Ollama's own chat route: unlike the OpenAI-style one it can switch off a model's 'thinking' (Qwen3), which would only cost seconds."""
    return httpx.post(base_url.rstrip("/") + "/api/chat", json=payload, timeout=timeout)


def configured(s: Settings) -> bool:
    if s.llm_provider in ("openai_compatible", "ollama"):
        return bool(s.llm_base_url) and "api.anthropic.com" not in s.llm_base_url
    return bool(s.anthropic_api_key)


def complete(system: str, user: str, s: Settings, *, timeout: Optional[float] = None, max_tokens: Optional[int] = None) -> str:
    """One model call with the provider from the settings. Returns the text, or raises DomainError (never leaks the upstream body)."""
    if not configured(s):
        raise DomainError("AI answers are not configured on this server", code="LLM_NOT_CONFIGURED", status_code=503)
    native = s.llm_provider == "ollama"
    local = s.llm_provider == "openai_compatible"
    t_out = s.llm_timeout_seconds if timeout is None else timeout
    n_tok = s.llm_max_tokens if max_tokens is None else max_tokens
    try:
        if native:
            payload = dict(model=s.llm_model, stream=False, think=False, options=dict(temperature=0, num_predict=n_tok),
                           messages=[dict(role="system", content=system), dict(role="user", content=user)])
            r = _post_ollama(payload, t_out, s.llm_base_url)
        elif local:
            headers = {"content-type": "application/json"}
            if s.local_llm_api_key:
                headers["authorization"] = "Bearer " + s.local_llm_api_key
            payload = dict(model=s.llm_model, max_tokens=n_tok, stream=False, temperature=0.0,
                           messages=[dict(role="system", content=system), dict(role="user", content=user)])
            r = _post_chat(payload, headers, t_out, s.llm_base_url)
        else:
            headers = {"x-api-key": s.anthropic_api_key, "anthropic-version": "2023-06-01", "content-type": "application/json"}
            payload = dict(model=s.llm_model, max_tokens=n_tok, system=system, messages=[dict(role="user", content=user)])
            r = _post(payload, headers, t_out, s.llm_base_url)
    except httpx.TimeoutException:
        raise DomainError("the AI service did not answer in time", code="LLM_TIMEOUT", status_code=504)
    except httpx.HTTPError:
        raise DomainError("the AI service could not be reached", code="LLM_UNAVAILABLE", status_code=502)
    if r.status_code != 200:
        # the body is not copied into the error: it could echo the question
        raise DomainError("the AI service refused the request (status %d)" % r.status_code, code="LLM_UPSTREAM_ERROR", status_code=502)
    try:
        j = r.json()
        cut = False
        if native:
            text = (j.get("message") or {}).get("content") or ""
            cut = j.get("done_reason") == "length"
        elif local:
            ch = (j.get("choices") or [{}])[0]
            text = (ch.get("message") or {}).get("content") or ""
            cut = ch.get("finish_reason") == "length"
        else:
            text = "".join(b.get("text", "") for b in j.get("content", []) if b.get("type") == "text")
        text = text.strip()
    except (ValueError, AttributeError, IndexError, TypeError):
        text = ""
    if not text:
        raise DomainError("the AI service returned no text", code="LLM_EMPTY", status_code=502)
    if cut and n_tok != s.llm_max_tokens:
        # a RAG answer that hit its length cap is cut off mid-sentence: refuse it (the approved passage is shown instead)
        raise DomainError("the AI answer was cut off", code="LLM_TRUNCATED", status_code=502)
    if unsafe_output(text):
        raise DomainError("the AI answer was withheld because it mentioned a medicine or a dose", code="LLM_UNSAFE_OUTPUT", status_code=502)
    return text[:MAX_ANSWER_CHARS]


_TELUGU = re.compile("[\u0c00-\u0c7f]")
_LETTERS = re.compile("[A-Za-z\u0c00-\u0c7f]")
_WORDS5 = re.compile("[A-Za-z\u0c00-\u0c7f]{5,}")
MIN_TELUGU_SHARE = 0.3     # of the letters in an explanation of a Telugu question
MIN_GROUNDED = 0.6         # of its longer words that must appear (by their first letters) in the question or the passages
MIN_GROUNDED_TELUGU = 0.9  # stricter for Telugu: small models write plausible-looking Telugu nonsense
_MIXED = re.compile("[A-Za-z][\u0c00-\u0c7f]|[\u0c00-\u0c7f][A-Za-z]")   # Telugu and Latin letters inside one word


# Indian scripts other than Telugu (Kannada, Tamil, Malayalam, Devanagari, Bengali...): small models sometimes slip one letter of a neighbouring
# script into a Telugu word ("గర్భಿణీ"). Such text is wrong whatever the rest says.
_FOREIGN = re.compile("[\u0900-\u0bff\u0c80-\u0dff]")


def foreign_script(text: str) -> bool:
    return bool(_FOREIGN.search(text))


def wrong_language(question: str, text: str) -> bool:
    """A Telugu question must get a mostly-Telugu explanation (small local models often answer in English)."""
    if len(_TELUGU.findall(question)) < 3:
        return False
    letters = _LETTERS.findall(text)
    return not letters or len(_TELUGU.findall(text)) / len(letters) < MIN_TELUGU_SHARE


def not_grounded(text: str, source: str) -> bool:
    """The model was told to use ONLY the passages. A cheap check on that: most of the longer words of the explanation must appear in
    the question or the passages (compared by their first 4 letters, 5 for Telugu, so word endings do not matter). An explanation
    that fails is dropped and the phone shows the approved text itself."""
    src = source.lower()
    words = _WORDS5.findall(text.lower())
    if not words:
        return True
    if any(_MIXED.search(w) for w in words):
        return True          # a word that mixes the two scripts is garbage, not a quotation
    ok = sum(1 for w in words if w[: 5 if _TELUGU.search(w) else 4] in src)
    telugu = len(_TELUGU.findall(text)) > len(_LETTERS.findall(text)) / 2
    return ok / len(words) < (MIN_GROUNDED_TELUGU if telugu else MIN_GROUNDED)


def _safety_note(safety_status: Optional[str]) -> str:
    if safety_status == "ESCALATION_REQUIRED":
        return "\n\n[The phone's safety check flagged a possible danger sign in this question.]"
    if safety_status == "CLARIFICATION_REQUIRED":
        return "\n\n[The phone's safety check says the description is unclear; ask for who, which symptom and whether it is happening now.]"
    return ""


def ask_llm(question: str, safety_status: Optional[str], s: Settings) -> dict:
    """Question only (no passages). Kept for the documented /health-qa/llm route."""
    return dict(answer=complete(SYSTEM, question + _safety_note(safety_status), s), model=s.llm_model)


def check_text(question: str, text: str, source: str) -> None:
    """The deterministic checks every generated explanation must pass; raises DomainError(502) for the first that fails."""
    if foreign_script(text) or wrong_language(question, text):
        raise DomainError("the AI answered in a different language than the question", code="LLM_WRONG_LANGUAGE", status_code=502)
    if not_grounded(text, source):
        raise DomainError("the AI text did not stay with the approved passages", code="LLM_NOT_GROUNDED", status_code=502)


def rag_generate(question: str, passages: list, safety_status: Optional[str], s: Settings, timeout: float) -> str:
    """A short answer to the question from ONLY these passages (dicts with title, text), inside `timeout` seconds, checked by the guards."""
    blocks = ["[%d]%s\n%s" % (n, (" " + p["title"]) if p.get("title") else "", p["text"]) for n, p in enumerate(passages, 1)]
    user = "QUESTION:\n" + question + "\n\nPASSAGES:\n" + "\n\n".join(blocks) + _safety_note(safety_status)
    text = complete(SYSTEM_RAG, user, s, timeout=timeout, max_tokens=s.rag_answer_max_tokens)
    check_text(question, text, question + "\n" + "\n".join(p["text"] + " " + (p.get("title") or "") for p in passages))
    return text


def explain_passages(question: str, passages: list, safety_status: Optional[str], s: Settings) -> dict:
    """The Ask pipeline's online step: the phone searched its vector database and sends the closest approved passages with the
    question; the model explains them. `passages` are dicts with passage_id, title (optional) and text."""
    if len(_TELUGU.findall(question)) >= 3 and not s.llm_telugu_explain:
        # not even asked: see Settings.llm_telugu_explain (the code is the one the phone already treats as "the server refused its text")
        raise DomainError("Telugu explanations are switched off on this server; the approved text is shown instead",
                          code="LLM_WRONG_LANGUAGE", status_code=502)
    blocks = []
    for n, p in enumerate(passages, 1):
        head = "[%d]%s" % (n, (" " + p["title"]) if p.get("title") else "")
        blocks.append(head + "\n" + p["text"])
    user = "QUESTION:\n" + question + "\n\nPASSAGES:\n" + "\n\n".join(blocks) + _safety_note(safety_status)
    text = complete(SYSTEM_EXPLAIN, user, s)
    # a small model can answer in the wrong language or drift away from the passages: refuse such text instead of showing it
    if foreign_script(text) or wrong_language(question, text):
        raise DomainError("the AI answered in a different language than the question", code="LLM_WRONG_LANGUAGE", status_code=502)
    if not_grounded(text, question + "\n" + "\n".join(p["text"] + " " + (p.get("title") or "") for p in passages)):
        raise DomainError("the AI text did not stay with the approved passages", code="LLM_NOT_GROUNDED", status_code=502)
    return dict(explanation=text, model=s.llm_model, provider=s.llm_provider)
