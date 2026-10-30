import datetime as dt
import uuid
from typing import Optional

from app.core.config import Settings


def today(settings: Settings) -> dt.date:
    return dt.date.fromisoformat(settings.reference_date) if settings.reference_date else dt.date.today()


def new_id(prefix: str) -> str:
    return "%s-%s" % (prefix, uuid.uuid4().hex[:10].upper())


def check_version(current: int, expected: Optional[int], what: str):
    from app.core.errors import Conflict
    if expected is not None and expected != current:
        raise Conflict("%s was modified (current version %d, you sent %d)" % (what, current, expected), code="VERSION_CONFLICT",
                       details=dict(current_version=current, supplied_version=expected))
