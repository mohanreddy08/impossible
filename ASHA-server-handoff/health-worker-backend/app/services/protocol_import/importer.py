"""Reusable importer for official protocol documents (to be run when the real sources arrive).

Guarantees:
  * Imported content is NEVER approved: status is UNVERIFIED (or TEST_FIXTURE_ONLY for fixtures) and approved_for_retrieval=False.
    Approval is a separate, explicit, audited step (approval.py).
  * Metadata that is not supplied stays NULL - nothing is inferred from file names or content.
  * passage_text is the exact source text (slice of the extracted page text); page numbers are never guessed.
  * Duplicates: the same file (sha256) is never imported twice; identical passages in one document are stored once.
  * Re-importing a CHANGED file under an existing document_id is refused unless replace=True, which resets approval."""
import hashlib
import os
import re
from dataclasses import asdict, dataclass, field
from typing import List, Optional

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db.base import utcnow
from app.db.models import ProtocolDocument, ProtocolPassage
from app.repositories import audit
from app.services.protocol_import.extract import extract_pages
from app.services.protocol_import.sections import split_pages

IMPORT_STATUSES = ("UNVERIFIED", "TEST_FIXTURE_ONLY")
_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{1,62}$")


class ProtocolImportError(Exception):
    pass


class DocumentConflict(ProtocolImportError):
    pass


@dataclass
class DocumentMeta:
    document_id: str
    title: Optional[str] = None
    issuing_authority: Optional[str] = None
    document_version: Optional[str] = None
    publication_date: Optional[str] = None
    language: Optional[str] = None
    source_verification_status: str = "UNVERIFIED"
    page_offset: int = 0

    @classmethod
    def from_dict(cls, d: dict) -> "DocumentMeta":
        allowed = set(cls.__dataclass_fields__)
        extra = set(d) - allowed
        if extra:
            raise ProtocolImportError("unknown metadata fields: %s" % sorted(extra))
        return cls(**d)


@dataclass
class ImportReport:
    document_id: str
    outcome: str                      # IMPORTED | REPLACED | SKIPPED_DUPLICATE_FILE | SKIPPED_UNCHANGED
    pages: int = 0
    passages_imported: int = 0
    passages_skipped_duplicate: int = 0
    passages_without_section: int = 0
    warnings: List[str] = field(default_factory=list)

    def as_dict(self):
        return asdict(self)


def content_hash(text: str) -> str:
    return hashlib.sha256(" ".join(text.split()).encode("utf-8")).hexdigest()


def import_protocol_file(db: Session, path: str, meta: DocumentMeta, *, replace: bool = False, max_chars: int = 900, actor: str = "importer") -> ImportReport:
    if not _ID.match(meta.document_id or ""):
        raise ProtocolImportError("document_id must be 2-63 chars of letters, digits, _ . -")
    if meta.source_verification_status not in IMPORT_STATUSES:
        raise ProtocolImportError("documents can only be imported as %s; use the approval step to verify" % " or ".join(IMPORT_STATUSES))
    sha = hashlib.sha256(open(path, "rb").read()).hexdigest()
    dup = db.scalar(select(ProtocolDocument).where(ProtocolDocument.source_file_sha256 == sha))
    if dup and not (replace and dup.document_id == meta.document_id):
        return ImportReport(dup.document_id, "SKIPPED_UNCHANGED" if dup.document_id == meta.document_id else "SKIPPED_DUPLICATE_FILE",
                            warnings=["identical file already imported as %s" % dup.document_id])
    existing = db.get(ProtocolDocument, meta.document_id)
    if existing and not replace:
        raise DocumentConflict("document_id %s already exists with different content; pass replace=True (this resets approval)" % meta.document_id)
    ext = extract_pages(path)
    drafts = split_pages(ext.pages, max_chars=max_chars)
    if not drafts:
        raise ProtocolImportError("no text passages could be extracted from %s" % os.path.basename(path))
    status = meta.source_verification_status
    if existing:
        for p in db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == existing.document_id)):
            db.delete(p)
        db.flush()
        doc, outcome = existing, "REPLACED"
    else:
        doc, outcome = ProtocolDocument(document_id=meta.document_id), "IMPORTED"
        db.add(doc)
    doc.title, doc.issuing_authority, doc.version = meta.title, meta.issuing_authority, meta.document_version
    doc.publication_date, doc.language = meta.publication_date, meta.language
    doc.source_verification_status, doc.approved_for_retrieval = status, False
    doc.verified_by = doc.verified_at = None
    doc.source_filename, doc.source_file_sha256, doc.imported_at = os.path.basename(path), sha, utcnow()
    db.flush()
    rep = ImportReport(meta.document_id, outcome, pages=len(ext.pages), warnings=list(ext.warnings))
    seen = set()
    for d in drafts:
        h = content_hash(d.text)
        if h in seen:
            rep.passages_skipped_duplicate += 1
            continue
        seen.add(h)
        if d.section_id is None and d.section_title is None:
            rep.passages_without_section += 1
        label = str(d.page_number + meta.page_offset) if (d.page_number is not None and meta.page_offset) else None
        db.add(ProtocolPassage(
            passage_id="%s-%04d" % (meta.document_id, d.ordinal), document_id=meta.document_id, section_id=d.section_id,
            section_title=d.section_title, page_number=d.page_number, page_label=label, passage_text=d.text, language=meta.language,
            approved_for_retrieval=False, source_verification_status=status, content_hash=h, ordinal=d.ordinal))
        rep.passages_imported += 1
    audit.record(db, actor, "IMPORT_PROTOCOL", "protocol_document", meta.document_id, ["passages", "source_file_sha256"], None, "import")
    db.flush()
    return rep
