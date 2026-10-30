from fastapi import APIRouter, Depends
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.api.deps import LIMIT, OFFSET
from app.core.errors import NotFound
from app.core.security import Principal, get_principal
from app.db.models import ProtocolDocument, ProtocolPassage
from app.db.session import get_db
from app.schemas.api import DocumentOut, PassageOut
from app.schemas.common import Page

router = APIRouter(prefix="/protocols", tags=["protocols"])


@router.get("", response_model=Page[DocumentOut])
def list_documents(limit: int = LIMIT, offset: int = OFFSET, db: Session = Depends(get_db), _: Principal = Depends(get_principal)):
    total = db.scalar(select(func.count()).select_from(ProtocolDocument))
    rows = db.scalars(select(ProtocolDocument).order_by(ProtocolDocument.document_id).limit(limit).offset(offset)).all()
    return Page(items=rows, total=total, limit=limit, offset=offset)


@router.get("/{document_id}", response_model=DocumentOut)
def get_document(document_id: str, db: Session = Depends(get_db), _: Principal = Depends(get_principal)):
    d = db.get(ProtocolDocument, document_id)
    if not d: raise NotFound("document not found")
    return d


@router.get("/{document_id}/passages", response_model=Page[PassageOut])
def list_passages(document_id: str, limit: int = LIMIT, offset: int = OFFSET, db: Session = Depends(get_db), _: Principal = Depends(get_principal)):
    if not db.get(ProtocolDocument, document_id): raise NotFound("document not found")
    q = select(ProtocolPassage).where(ProtocolPassage.document_id == document_id)
    total = db.scalar(select(func.count()).select_from(q.subquery()))
    return Page(items=db.scalars(q.order_by(ProtocolPassage.passage_id).limit(limit).offset(offset)).all(), total=total, limit=limit, offset=offset)
