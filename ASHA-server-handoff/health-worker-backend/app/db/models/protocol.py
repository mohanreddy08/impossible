import datetime as dt
from typing import Optional

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base, utcnow


class ProtocolDocument(Base):
    __tablename__ = "protocol_documents"
    document_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[Optional[str]] = mapped_column(String(512))            # NULL = unknown (never invented)
    issuing_authority: Mapped[Optional[str]] = mapped_column(String(256))
    version: Mapped[Optional[str]] = mapped_column(String(64))
    publication_date: Mapped[Optional[str]] = mapped_column(String(32))
    language: Mapped[Optional[str]] = mapped_column(String(32))
    source_verification_status: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    approved_for_retrieval: Mapped[bool] = mapped_column(Boolean, default=False)
    imported_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    source_filename: Mapped[Optional[str]] = mapped_column(String(256))
    source_file_sha256: Mapped[Optional[str]] = mapped_column(String(64), index=True)   # duplicate-file prevention
    verified_by: Mapped[Optional[str]] = mapped_column(String(64))                       # set only by an explicit approval step
    verified_at: Mapped[Optional[dt.datetime]] = mapped_column(DateTime)
    passages = relationship("ProtocolPassage", back_populates="document")


class ProtocolPassage(Base):
    __tablename__ = "protocol_passages"
    passage_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    document_id: Mapped[str] = mapped_column(ForeignKey("protocol_documents.document_id"), index=True)
    section_id: Mapped[Optional[str]] = mapped_column(String(64))
    section_title: Mapped[Optional[str]] = mapped_column(String(512))
    page_number: Mapped[Optional[int]] = mapped_column(Integer)
    passage_text: Mapped[str] = mapped_column(Text)                         # exact source text
    language: Mapped[Optional[str]] = mapped_column(String(32))
    approved_for_retrieval: Mapped[bool] = mapped_column(Boolean, default=False)
    source_verification_status: Mapped[str] = mapped_column(String(32), default="UNKNOWN")
    imported_at: Mapped[dt.datetime] = mapped_column(DateTime, default=utcnow)
    content_hash: Mapped[Optional[str]] = mapped_column(String(64))                     # sha256 of whitespace-normalised text
    ordinal: Mapped[Optional[int]] = mapped_column(Integer)                              # order within the document
    page_label: Mapped[Optional[str]] = mapped_column(String(16))                        # printed page label if it differs from page_number
    document = relationship("ProtocolDocument", back_populates="passages")
    __table_args__ = (Index("ix_passages_doc_section", "document_id", "section_id"),
                      UniqueConstraint("document_id", "content_hash", name="uq_passage_doc_content"))
