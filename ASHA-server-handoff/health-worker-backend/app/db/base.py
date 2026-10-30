import datetime as dt

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    pass


def utcnow() -> dt.datetime:
    """Naive UTC timestamps are stored everywhere (portable across SQLite/PostgreSQL)."""
    return dt.datetime.utcnow().replace(microsecond=0)
