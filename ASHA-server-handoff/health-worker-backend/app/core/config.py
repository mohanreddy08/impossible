import os
from functools import lru_cache
from typing import Optional

from pydantic_settings import BaseSettings, SettingsConfigDict

BACKEND_ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "development"
    database_url: str = "sqlite:///./health_companion.db"
    dataset_dir: str = "../health-worker-datasets"
    # offline Telugu speech model files served to phones (see scripts/build_telugu_asr_pack.py); large, not in git
    speech_model_dir: str = "models/te-asr"

    # auth_mode: "disabled" (local development ONLY) | "api_key"
    auth_mode: str = "disabled"
    # "role|worker_id|key;role|worker_id|key"   role: worker|admin|hospital  (worker_id blank for admin/hospital)
    api_keys: str = ""
    device_hash_salt: str = "dev-only-salt-change-me"   # production refuses to start with this value

    # Abuse limits (per process; see app/core/hardening.py)
    max_body_bytes: int = 2_000_000          # /health-qa/* is capped at 32 KB regardless
    rate_limit_per_minute: int = 600         # per API key (or address when no key); 0 = off
    llm_rate_limit_per_minute: int = 12      # the AI route costs money and forwards text to a third party
    failed_auth_per_minute: int = 20         # wrong keys per client address before that address is locked out for the rest of the minute

    # Optional AI helper. LLM_PROVIDER=anthropic (the Anthropic API) or openai_compatible (a LOCAL LLM on a nearby server: Ollama,
    # llama-server, vLLM; set LLM_BASE_URL=http://<server>:11434 and LLM_MODEL=<model name>). Keys come ONLY from the environment.
    llm_provider: str = "anthropic"
    anthropic_api_key: Optional[str] = None
    local_llm_api_key: Optional[str] = None   # only if the local LLM server asks for a bearer key
    llm_base_url: str = "https://api.anthropic.com"   # for openai_compatible: the local server, e.g. http://192.168.1.20:11434
    llm_model: str = "claude-haiku-5-5"       # for openai_compatible: the model name on that server, e.g. qwen2.5:3b
    llm_timeout_seconds: float = 8.5          # server-side limit to the model; the phone gives up after 10 s in total
    llm_max_tokens: int = 350
    # Telugu questions: small local models write poor Telugu, so by default the model is not asked and the phone shows the approved Telugu
    # text itself. Switch on (LLM_TELUGU_EXPLAIN=true) only with a model whose Telugu you have checked.
    llm_telugu_explain: bool = False

    # Server-side RAG (POST /health-qa/rag, app/services/rag): a multilingual EMBEDDING model finds the approved passages for the question
    # (works for Telugu), then the LLM writes a short answer that the guards check. Everything runs on this server; nothing is in the app.
    # An Ollama server can serve both (LLM_PROVIDER=ollama, LLM_BASE_URL=http://host:11434, RAG_EMBED_MODEL=bge-m3).
    rag_enabled: bool = True
    rag_embed_model: str = "bge-m3"
    rag_embed_base_url: Optional[str] = None  # default: llm_base_url
    rag_embed_timeout_seconds: float = 4.0
    rag_min_score: float = 0.45               # cosine similarity below which "there is no approved text for this" (measured gap: 0.39 vs 0.51)
    rag_top_k: int = 3
    rag_budget_seconds: float = 9.0           # the whole request must finish inside the phone's 10 s; a slow model falls back to the approved text
    rag_cache_path: Optional[str] = None      # JSON file where passage vectors are kept between restarts (none = memory only)
    rag_answer_max_tokens: int = 130
    rag_direct_max_words: int = 60            # a best passage this short IS the answer: returned word for word, no model call (0 = always ask the model)

    # Retrieval evidence threshold (0..1 weighted query-term coverage)
    evidence_min_score: float = 0.5
    evidence_min_matched_terms: int = 2
    retrieval_top_k: int = 3
    eligible_verification_statuses: str = "VERIFIED"
    docs_enabled: bool = True          # set DOCS_ENABLED=false in production to hide /docs and /openapi.json

    # "today" for synthetic data (the datasets are anchored at 2026-10-13); blank = real today
    reference_date: Optional[str] = None
    # Synthetic-dataset convention (NOT a clinical rule): last visit this recent => household status COMPLETED
    recent_completion_days: int = 14
    # Report freshness labels (project policy, not clinical)
    fresh_hours: int = 24
    recent_hours: int = 72

    # ---------------------------------------------------------------- supervisor website (dashboard) and accounts
    # Signs the website's session tokens (JWT, HS256). REQUIRED in production (>= 32 random characters): `openssl rand -hex 32`.
    secret_key: str = "dev-only-secret-change-me"
    session_minutes: int = 30                 # short-lived website sessions; renewed while the supervisor is active
    login_failures_before_lock: int = 5       # per account; the account is locked for login_lock_minutes
    login_lock_minutes: int = 15
    # The website's own origin (e.g. https://asha.example.org). CORS is closed unless this is set; only this origin is then allowed.
    site_origin: Optional[str] = None
    # The public https address phones should use. Normally written by scripts/start_public.sh to run/public_url.txt; this overrides it.
    public_url: Optional[str] = None
    public_url_file: str = "../run/public_url.txt"
    web_dir: str = "../health-worker-web"     # templates, static files and translations of the website
    # The hackathon pack folder (synthetic block data + protocols). Same meaning as the H5_DATA environment variable.
    h5_data: Optional[str] = None
    # "today" for the block's visit list (the pack's VIS list is made for 2026-10-26). Blank = real today.
    demo_today: Optional[str] = "2026-10-26"
    retention_days: int = 180                 # Q&A audit and admin audit rows older than this are deleted (changeable in Settings)

    @property
    def resolved_web_dir(self) -> str:
        return _abs(self.web_dir)

    @property
    def resolved_h5_data(self) -> str:
        return _abs(self.h5_data or os.environ.get("H5_DATA") or "../h5-pack-data")

    @property
    def resolved_public_url_file(self) -> str:
        return _abs(self.public_url_file)

    @property
    def resolved_dataset_dir(self) -> str:
        p = self.dataset_dir
        return p if os.path.isabs(p) else os.path.abspath(os.path.join(BACKEND_ROOT, p))

    @property
    def eligible_statuses(self):
        return tuple(s.strip() for s in self.eligible_verification_statuses.split(",") if s.strip())


def _abs(p: str) -> str:
    return p if os.path.isabs(p) else os.path.abspath(os.path.join(BACKEND_ROOT, p))


@lru_cache
def get_settings() -> Settings:
    return Settings()
