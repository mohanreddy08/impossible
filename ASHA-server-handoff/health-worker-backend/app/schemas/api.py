import datetime as dt
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.common import ORM
from app.schemas.domain import HouseholdOut, ReferralOut, VisitOut


class QueryIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(..., min_length=1, max_length=2000)


class LlmIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(..., min_length=1, max_length=2000)
    safety_status: Optional[str] = Field(None, pattern="^(NORMAL_PROTOCOL_QUERY|ESCALATION_REQUIRED|CLARIFICATION_REQUIRED|OUT_OF_SCOPE)$",
                                         description="Result of the phone's own safety check, passed to the model as context.")


class LlmOut(BaseModel):
    answer: str
    model: str
    clinically_validated: bool = False
    disclaimer: str = "AI-generated. Not clinically verified. Not a diagnosis. Follow your approved protocols."


class PassageIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    passage_id: str = Field(..., min_length=1, max_length=80)
    title: Optional[str] = Field(None, max_length=200)
    text: str = Field(..., min_length=1, max_length=1500)


class ExplainIn(BaseModel):
    """The phone searched its own vector database; these are the closest approved passages. Few and short on purpose: the whole
    request stays under the 32 KB limit of /health-qa even in Telugu (3 bytes per character)."""
    model_config = ConfigDict(extra="forbid")
    question: str = Field(..., min_length=1, max_length=2000)
    passages: list[PassageIn] = Field(..., min_length=1, max_length=4)
    safety_status: Optional[str] = Field(None, pattern="^(NORMAL_PROTOCOL_QUERY|ESCALATION_REQUIRED|CLARIFICATION_REQUIRED|OUT_OF_SCOPE)$",
                                         description="Result of the phone's own safety check, passed to the model as context.")


class ExplainOut(BaseModel):
    explanation: str
    model: str
    provider: str
    clinically_validated: bool = False
    disclaimer: str = "AI-written from the approved text sent with the question. Not clinically verified. Not a diagnosis. Follow your approved protocols."


class RagIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    question: str = Field(..., min_length=1, max_length=2000)


class RagSourceOut(BaseModel):
    passage_id: str
    document_id: str
    document_title: Optional[str] = None
    section_id: Optional[str] = None
    section_heading: Optional[str] = None
    page_number: Optional[int] = None
    source_version: Optional[str] = None
    relevance_score: float
    source_verification_status: str
    text: str


class RagOut(BaseModel):
    """outcome: ANSWERED | NO_APPROVED_TEXT | ESCALATION_REQUIRED | CLARIFICATION_REQUIRED | OUT_OF_SCOPE.
    answer_source: "llm" (written by the model from the passages, guards passed) or "extract" (the approved passage, word for word)."""
    outcome: str
    answer: Optional[str] = None
    answer_source: Optional[str] = None
    message: str = ""
    language: str
    sources: list[RagSourceOut] = []
    safety: dict
    retrieval: Optional[str] = None
    embedder: Optional[str] = None
    model: Optional[str] = None
    llm_error: Optional[str] = None
    timings_ms: dict = {}
    clinically_validated: bool = False
    disclaimer: str = "Only approved passages are used. Not clinically verified unless the source says so. Not a diagnosis. Follow your approved protocols."


class CitationOut(BaseModel):
    passage_id: str
    document_id: str
    document_title: Optional[str]
    section_id: Optional[str]
    section_heading: Optional[str]
    page_number: Optional[int]
    source_version: Optional[str]
    relevance_score: float
    source_verification_status: str


class SafetyOut(BaseModel):
    status: str
    rule_ids: List[str]
    reasons: List[str]
    ruleset_version: str
    ruleset_review_status: str
    clinically_validated: bool = Field(False, description="Always false until a qualified reviewer approves the ruleset against approved protocols.")
    needs_human_review: bool


class QAOut(BaseModel):
    query_id: str
    outcome: str
    original_question: str
    message: str
    answer_text: Optional[str]
    citations: List[CitationOut]
    safety: SafetyOut
    retrieval_status: Optional[str]


class PassageMatchOut(CitationOut):
    text: str
    matched_terms: List[str]


class RetrieveOut(BaseModel):
    query_id: str
    status: str
    original_query: str
    normalized_query: str
    matched_passage_ids: List[str]
    matches: List[PassageMatchOut]
    indexed_passages: int


class DocumentOut(ORM):
    document_id: str
    title: Optional[str]
    issuing_authority: Optional[str]
    version: Optional[str]
    publication_date: Optional[str]
    language: Optional[str]
    source_verification_status: str
    approved_for_retrieval: bool


class PassageOut(ORM):
    passage_id: str
    document_id: str
    section_id: Optional[str]
    section_title: Optional[str]
    page_number: Optional[int]
    passage_text: str
    language: Optional[str]
    source_verification_status: str


class ReportIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    facility_id: str
    period_start: dt.date
    period_end: dt.date
    referral_ids: Optional[List[str]] = Field(None, description="Restrict to these records (e.g. an offline device's local set).")
    last_sync_at: Optional[dt.datetime] = None


class SyncPullOut(BaseModel):
    server_time: str
    households: Optional[List[HouseholdOut]] = None
    visits: Optional[List[VisitOut]] = None
    referrals: Optional[List[ReferralOut]] = None


class ReportCounts(BaseModel):
    recommended: int
    planned: int
    attendance_confirmed: int = Field(..., description="Only records backed by a hospital attendance record. Recommended/planned referrals and household visits are never counted here.")
    total_included: int


class ReportFollowUps(BaseModel):
    due: int
    completed_in_period: int


class ReportOut(BaseModel):
    report_id: str
    facility_id: str
    period_start: dt.date
    period_end: dt.date
    generated_at: str
    data_as_of: Optional[str]
    last_sync_at: Optional[str]
    data_freshness_label: str = Field(..., description="FRESH | RECENT | STALE_OFFLINE | NOT_PROVIDED")
    counts: ReportCounts
    counts_by_service_category: Dict[str, int]
    excluded_counts: Dict[str, int]
    follow_ups: ReportFollowUps
    privacy_notice: str
    synthetic_data: bool
    content_hash: str
    duplicate_of_existing: bool = False
    superseded_by: Optional[str] = None


class SyncResultOut(BaseModel):
    op_id: Optional[str]
    index: Optional[int] = None
    status: str = Field(..., description="ACKNOWLEDGED | REJECTED | CONFLICT | FAILED_RETRYABLE")
    acknowledged: bool = Field(..., description="True only after the server committed the operation. Anything else: keep the change pending on the device.")
    duplicate: bool
    server_version: Optional[int]
    error_code: Optional[str]
    error_message: Optional[str]
    conflict: Optional[Dict[str, Any]]
    warnings: List[str]


class SyncPushOut(BaseModel):
    received: int
    acknowledged_count: int
    results: List[SyncResultOut]
    note: str


class SyncStatusOut(BaseModel):
    total_operations: int
    by_status: Dict[str, int]
    last_acknowledged_at: Optional[str]
    conflicts: int
    rejected: int
