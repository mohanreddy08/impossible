"""Explicit, audited approval of an imported protocol document. This is the ONLY way content becomes retrievable
(approved_for_retrieval=True, status VERIFIED). Fixtures can never be approved. Approval is CLI/admin-only (no HTTP route)."""
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.base import utcnow
from app.db.models import ProtocolDocument, ProtocolPassage
from app.repositories import audit
from app.services.protocol_import.importer import ProtocolImportError


class ApprovalRefused(ProtocolImportError):
    pass


def approve_document(db: Session, document_id: str, reviewer: str, note: str = "") -> int:
    reviewer = (reviewer or "").strip()
    if len(reviewer) < 3:
        raise ApprovalRefused("a named reviewer is required")
    doc = db.get(ProtocolDocument, document_id)
    if not doc:
        raise ApprovalRefused("document not found")
    if doc.source_verification_status == "TEST_FIXTURE_ONLY":
        raise ApprovalRefused("test fixtures can never be approved as medical sources")
    if not (doc.issuing_authority and doc.version) :
        raise ApprovalRefused("issuing_authority and version must be recorded before approval (supply them via the metadata file and re-import)")
    n = 0
    for p in db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == document_id)):
        p.source_verification_status, p.approved_for_retrieval = "VERIFIED", True
        n += 1
    doc.source_verification_status, doc.approved_for_retrieval = "VERIFIED", True
    doc.verified_by, doc.verified_at = reviewer, utcnow()
    audit.record(db, reviewer, "APPROVE_PROTOCOL", "protocol_document", document_id, ["source_verification_status", "approved_for_retrieval"], None, "import")
    db.flush()
    return n


def revoke_approval(db: Session, document_id: str, reviewer: str) -> int:
    doc = db.get(ProtocolDocument, document_id)
    if not doc:
        raise ApprovalRefused("document not found")
    n = 0
    for p in db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == document_id)):
        p.source_verification_status, p.approved_for_retrieval = "UNVERIFIED", False
        n += 1
    doc.source_verification_status, doc.approved_for_retrieval, doc.verified_by, doc.verified_at = "UNVERIFIED", False, None, None
    audit.record(db, reviewer or "unknown", "REVOKE_PROTOCOL", "protocol_document", document_id, ["source_verification_status"], None, "import")
    db.flush()
    return n
