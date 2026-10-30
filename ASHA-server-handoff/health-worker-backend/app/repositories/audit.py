from typing import Iterable, Optional

from sqlalchemy.orm import Session

from app.db.models import AuditLog


def record(db: Session, actor: str, action: str, entity_type: str, entity_id: str, fields: Optional[Iterable[str]] = None,
           version: Optional[int] = None, source: str = "api") -> None:
    db.add(AuditLog(actor=actor, action=action, entity_type=entity_type, entity_id=entity_id,
                    changed_fields=sorted(fields) if fields else None, new_version=version, source=source))
