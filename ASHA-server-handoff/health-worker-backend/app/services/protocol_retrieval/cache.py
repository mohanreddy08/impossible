"""Rebuilds the in-memory index only when the passage table changes (count + newest import time)."""
import threading

from sqlalchemy import case, func

from app.db.models import ProtocolPassage
from app.services.protocol_retrieval.service import ProtocolIndex, passages_from_db

_lock = threading.Lock()
_cache = {}


def get_index(db, eligible_statuses):
    elig = (ProtocolPassage.approved_for_retrieval.is_(True)) & ProtocolPassage.source_verification_status.in_(list(eligible_statuses))
    sig = (id(db.get_bind()), tuple(eligible_statuses),
           tuple(db.query(func.count(ProtocolPassage.passage_id), func.max(ProtocolPassage.imported_at), func.sum(func.length(ProtocolPassage.passage_text)),
                          func.sum(case((elig, 1), else_=0))).one()))
    with _lock:
        hit = _cache.get("idx")
        if hit and hit[0] == sig:
            return hit[1]
        idx = ProtocolIndex(passages_from_db(db), eligible_statuses)
        _cache["idx"] = (sig, idx)
        return idx
