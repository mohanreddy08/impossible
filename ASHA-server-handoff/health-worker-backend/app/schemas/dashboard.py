"""Request/response models of the website API (/api/v1/auth, /admin, /dashboard, /ask). Unknown fields are rejected everywhere."""
import datetime as dt
from typing import Any, Dict, List, Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid")


# ---------------------------------------------------------------- auth
class LoginIn(Strict):
    username: str = Field(..., min_length=1, max_length=64)
    password: str = Field(..., min_length=1, max_length=256)


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    username: str
    display_name: str
    role: str
    worker_id: Optional[str] = None
    is_active: bool
    language: str
    created_at: dt.datetime
    last_login_at: Optional[dt.datetime] = None
    locked_until: Optional[dt.datetime] = None


class LoginOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut


class EmptyIn(Strict):
    """No fields. (Present so that unknown fields are still rejected with 422.)"""


# ---------------------------------------------------------------- admin
class UserCreateIn(Strict):
    username: str = Field(..., min_length=3, max_length=64)
    display_name: str = Field(..., min_length=1, max_length=128)
    role: Literal["admin", "supervisor", "asha"]
    password: str = Field(..., min_length=10, max_length=256)
    worker_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{2,32}$")
    language: Literal["en", "te"] = "en"


class UserPatchIn(Strict):
    display_name: Optional[str] = Field(None, min_length=1, max_length=128)
    role: Optional[Literal["admin", "supervisor", "asha"]] = None
    is_active: Optional[bool] = None
    password: Optional[str] = Field(None, min_length=10, max_length=256)
    language: Optional[Literal["en", "te"]] = None


class PhoneKeyIn(Strict):
    worker_id: str = Field(..., pattern=r"^[A-Za-z0-9_-]{2,32}$", description="The ASHA (worker id) this phone belongs to")
    label: str = Field("phone", min_length=1, max_length=64, description="e.g. 'Sunaina's Redmi'")


class PhoneKeyOut(BaseModel):
    key_id: str
    label: str
    worker_id: str
    created_at: dt.datetime
    created_by: str
    revoked_at: Optional[dt.datetime] = None
    last_seen_at: Optional[dt.datetime] = None
    last_sync_at: Optional[dt.datetime] = None


class PhoneKeyCreatedOut(PhoneKeyOut):
    api_key: str = Field(..., description="Shown ONCE. Type it into the phone's Settings > API key. Only a hash is kept on the server.")
    server_url: Optional[str] = None


class SettingsPatchIn(Strict):
    retention_days: Optional[int] = Field(None, ge=7, le=3650)
    public_url: Optional[str] = Field(None, max_length=200, pattern=r"^(https://[A-Za-z0-9.-]+(:[0-9]{2,5})?/?)?$")
    default_language: Optional[Literal["en", "te"]] = None


class ServerInfoOut(BaseModel):
    public_url: Optional[str]
    source: str
    reachable: Optional[bool]
    checked_url: Optional[str]
    detail: Optional[str]
    qr_svg: Optional[str] = Field(None, description="QR code (SVG) that encodes the server address for the phone's Settings")
    retention_days: int
    default_language: str
    demo_today: Optional[str]


# ---------------------------------------------------------------- dashboard
class RevealIn(Strict):
    reason: Literal["CALL_FAMILY", "REFERRAL_FOLLOWUP", "ESCALATION", "OTHER"] = "CALL_FAMILY"


class EscalationPatchIn(Strict):
    status: Literal["ACKNOWLEDGED", "CLOSED"]
    note_code: Optional[Literal["REFERRED_108", "FAMILY_INFORMED", "ANM_VISITED", "MO_INFORMED", "FALSE_ALARM", "OTHER"]] = None


class AskIn(Strict):
    question: str = Field(..., min_length=1, max_length=2000)
    household_id: Optional[str] = Field(None, pattern=r"^[A-Za-z0-9_-]{3,32}$", description="Optional: links an escalation to a household")


class CitationOut(BaseModel):
    section_id: str
    title: Optional[str] = None


class AskOut(BaseModel):
    answer_text: str = Field(..., description="Exact h5 engine output (protocol sentences, tagged with their section ids)")
    cited_section_ids: List[str]
    citations: List[CitationOut]
    escalate: bool = Field(..., description="Danger sign: REFER IMMEDIATELY. Never an 'answer'.")
    refused: bool = Field(..., description="Out of scope (refusal rules); ask the Medical Officer")
    outcome: Literal["ESCALATED", "REFUSED", "ANSWERED"]
    rule_ids: List[str]
    latency_ms: float
    audit_id: int
    disclaimer: str


class PageOut(BaseModel):
    items: List[Dict[str, Any]]
    total: int
    limit: int
    offset: int
