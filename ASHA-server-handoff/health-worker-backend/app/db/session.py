import threading
from contextlib import contextmanager
from typing import Any, Dict, Iterator, Optional

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.config import get_settings


def make_engine(url: str):
    kwargs: Dict[str, Any] = {}
    if url.startswith("sqlite"):
        # wait up to 30 s for the write lock instead of failing at once (several phones syncing at the same moment)
        kwargs["connect_args"] = {"check_same_thread": False, "timeout": 30}
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
                # WAL + NORMAL: still consistent; a power cut can lose the last commits, which the phone resends (it keeps every op that
                # was not acknowledged). About 10x faster commits than FULL; each sync op is its own commit.
                dbapi_conn.execute("PRAGMA synchronous=NORMAL")

        @event.listens_for(eng, "begin")
        def _begin(conn):
            conn.exec_driver_sql("BEGIN")

    return eng


_engine = None
_SessionLocal: Optional[sessionmaker] = None


def get_engine():
    global _engine, _SessionLocal
    if _engine is None:
        _engine = make_engine(get_settings().database_url)
        _SessionLocal = sessionmaker(bind=_engine, autoflush=False, expire_on_commit=False, future=True)
    return _engine


_sqlite_writes = threading.Lock()


@contextmanager
def serialized_writes(db: Session):
    """SQLite has a single writer. Under concurrent sync pushes, transactions that read first and write later fail at once with
    "database is locked" (stale snapshot) instead of waiting, so pushes queue on this in-process lock instead (one server process with
    SQLite; with PostgreSQL this is a no-op and the database's own row locking applies)."""
    if db.get_bind().dialect.name != "sqlite":
        yield
        return
    db.rollback()                     # end the read snapshot of authentication AND give the connection back to the pool before waiting:
    with _sqlite_writes:              # waiters must not hold pooled connections, or the lock holder cannot get one (pool deadlock)
        yield


def get_db() -> Iterator[Session]:
    get_engine()
    assert _SessionLocal is not None
    db = _SessionLocal()
    try:
        yield db
    finally:
        db.close()


def session_factory(engine):
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)
