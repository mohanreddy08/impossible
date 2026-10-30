from typing import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import get_settings


def make_engine(url: str):
    kwargs = {}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
        if ":memory:" in url or url in ("sqlite://", "sqlite:///"):
            kwargs["poolclass"] = StaticPool
    eng = create_engine(url, future=True, **kwargs)
    if url.startswith("sqlite"):
        @event.listens_for(eng, "connect")
        def _fk(dbapi_conn, _):  # enforce foreign keys; take over transaction control so SAVEPOINTs work (SQLAlchemy recipe)
            dbapi_conn.isolation_level = None
            dbapi_conn.execute("PRAGMA foreign_keys=ON")
            if ":memory:" not in url and url not in ("sqlite://", "sqlite:///"):
                dbapi_conn.execute("PRAGMA journal_mode=WAL")      # readers never block the writer

        @event.listens_for(eng, "begin")
        def _begin(conn):
            conn.exec_driver_sql("BEGIN")
    return eng


_engine = None
_SessionLocal = None


def get_engine():
    global _engine, _SessionLocal
    if _engine is None:
        _engine = make_engine(get_settings().database_url)
        _SessionLocal = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False, future=True)
    return _engine


def get_db() -> Iterator[Session]:
    get_engine()
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


def session_factory(engine):
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)
