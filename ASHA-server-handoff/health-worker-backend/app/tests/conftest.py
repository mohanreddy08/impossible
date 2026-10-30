import itertools
import os
import sqlite3
import tempfile
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.core.config import BACKEND_ROOT, Settings, get_settings
from app.db.base import Base
import app.db.models  # noqa: F401
from app.db.session import get_db, make_engine, session_factory
from app.main import create_app
from app.services.dataset_import.importer import import_datasets
from app.services.protocol_retrieval import cache

PG = os.environ.get("TEST_DB", "sqlite").lower() == "postgres"      # TEST_DB=postgres runs the whole suite on real PostgreSQL
DATASETS = os.path.abspath(os.path.join(BACKEND_ROOT, "..", "health-worker-datasets"))
REF = "2026-10-13"


def _settings(**kw):
    base = dict(auth_mode="disabled", reference_date=REF, database_url="sqlite://", dataset_dir=DATASETS, device_hash_salt="test-salt")
    base.update(kw)
    return Settings(**base)


_counter = itertools.count(1)


@pytest.fixture(scope="session")
def pg_server():
    if not PG:
        yield None
        return
    import pgserver
    d = tempfile.mkdtemp(prefix="pgtest_")
    srv = pgserver.get_server(d)
    yield srv
    srv.cleanup()


def _pg_url(srv, dbname):
    from sqlalchemy.engine import make_url
    return make_url(srv.get_uri()).set(drivername="postgresql+psycopg2", database=dbname)


def _pg_admin(srv, sql):
    import sqlalchemy as sa
    e = sa.create_engine(_pg_url(srv, "postgres"), isolation_level="AUTOCOMMIT")
    with e.connect() as c:
        c.execute(sa.text(sql))
    e.dispose()


@pytest.fixture(scope="session")
def master_conn(pg_server, tmp_path_factory):
    """Datasets imported once; each test gets a private copy (fast, isolated)."""
    if PG:
        # template database built through the real Alembic migrations (so migrations are exercised on PostgreSQL too)
        from alembic import command
        from alembic.config import Config
        _pg_admin(pg_server, "CREATE DATABASE tpl")
        url = _pg_url(pg_server, "tpl").render_as_string(hide_password=False)
        os.environ["ALEMBIC_DATABASE_URL"] = url
        cfg = Config(os.path.join(BACKEND_ROOT, "alembic.ini"))
        cfg.set_main_option("script_location", os.path.join(BACKEND_ROOT, "alembic"))
        command.upgrade(cfg, "head")
        os.environ.pop("ALEMBIC_DATABASE_URL")
        eng = make_engine(url)
        with session_factory(eng)() as db:
            report = import_datasets(db, DATASETS)
        eng.dispose()
        _pg_admin(pg_server, "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'tpl' AND pid <> pg_backend_pid()")
        return SimpleNamespace(report=report)
    eng = make_engine("sqlite://")
    Base.metadata.create_all(eng)
    with session_factory(eng)() as db:
        eng.report = import_datasets(db, DATASETS)
    return eng


@pytest.fixture
def engine(master_conn, pg_server, tmp_path):
    """Private copy of the imported datasets (separate connections per session, like production)."""
    cache._cache.clear()
    if PG:
        name = "t_%d" % next(_counter)
        _pg_admin(pg_server, "CREATE DATABASE %s TEMPLATE tpl" % name)
        eng = make_engine(_pg_url(pg_server, name).render_as_string(hide_password=False))
        yield eng
        eng.dispose()
        _pg_admin(pg_server, "DROP DATABASE %s WITH (FORCE)" % name)
        return
    path = str(tmp_path / "t.db")
    dst = sqlite3.connect(path)
    master_conn.raw_connection().driver_connection.backup(dst)
    dst.close()
    eng = make_engine("sqlite:///" + path)
    yield eng
    eng.dispose()


@pytest.fixture
def db(engine):
    with session_factory(engine)() as s:
        yield s


@pytest.fixture
def empty_engine(pg_server):
    cache._cache.clear()
    if PG:
        name = "e_%d" % next(_counter)
        _pg_admin(pg_server, "CREATE DATABASE %s" % name)
        eng = make_engine(_pg_url(pg_server, name).render_as_string(hide_password=False))
        Base.metadata.create_all(eng)
        yield eng
        eng.dispose()
        _pg_admin(pg_server, "DROP DATABASE %s WITH (FORCE)" % name)
        return
    eng = make_engine("sqlite://")
    Base.metadata.create_all(eng)
    yield eng


def build_client(engine, settings):
    app = create_app() if settings.app_env != "production" else None
    app.dependency_overrides[get_settings] = lambda: settings
    sf = session_factory(engine)

    def _db():
        s = sf()
        try:
            yield s
        finally:
            s.close()
    app.dependency_overrides[get_db] = _db
    return TestClient(app, raise_server_exceptions=False)


@pytest.fixture
def client(engine):
    return build_client(engine, _settings())


@pytest.fixture
def make_client(engine):
    return lambda **kw: build_client(engine, _settings(**kw))


@pytest.fixture
def settings():
    return _settings()


# ---------------------------------------------------------------- website / dashboard fixtures (block register + accounts)
H5_DIR = os.path.abspath(os.path.join(BACKEND_ROOT, "..", "h5-pack-data"))
DEMO_TODAY = "2026-10-26"
PASSWORDS = {"admin": "admin-password-1", "anm": "supervisor-pw-1", "asha.kalavati": "asha-password-1", "asha.sunaina": "asha-password-2"}
needs_pack = pytest.mark.skipif(not os.path.isdir(os.path.join(H5_DIR, "protocols")), reason="hackathon pack (h5-pack-data) not found")


def _web_settings(**kw):
    base = dict(auth_mode="api_key", api_keys="", reference_date=REF, database_url="sqlite://", dataset_dir=DATASETS, device_hash_salt="test-salt",
                secret_key="test-secret-key-0123456789-0123456789", h5_data=H5_DIR, demo_today=DEMO_TODAY, public_url_file="/nonexistent/public_url.txt")
    base.update(kw)
    return Settings(**base)


@pytest.fixture(scope="session")
def block_master(tmp_path_factory):
    """Phone demo datasets + the h5 block register + five accounts, built once (SQLite) and copied per test."""
    if PG or not os.path.isdir(H5_DIR):
        return None
    import datetime as _dt
    from app.core.principal import Principal
    from app.services.accounts import service as accounts
    from app.services.block import seed
    eng = make_engine("sqlite://")
    Base.metadata.create_all(eng)
    with session_factory(eng)() as db:
        import_datasets(db, DATASETS)
        seed.load_block(db, H5_DIR, _dt.date.fromisoformat(DEMO_TODAY))
        sysp = Principal("admin", None, "system:test")
        accounts.create_user(db, sysp, username="admin", display_name="Admin", role="admin", password=PASSWORDS["admin"])
        accounts.create_user(db, sysp, username="anm", display_name="ANM", role="supervisor", password=PASSWORDS["anm"])
        accounts.create_user(db, sysp, username="asha.kalavati", display_name="Kalavati Kumari", role="asha", password=PASSWORDS["asha.kalavati"], worker_id="ASHA-RRR5")
        accounts.create_user(db, sysp, username="asha.sunaina", display_name="Sunaina Devi", role="asha", password=PASSWORDS["asha.sunaina"], worker_id="ASHA-096P")
        db.commit()
    return eng


@pytest.fixture
def block_engine(block_master, tmp_path):
    if block_master is None:
        pytest.skip("needs SQLite and the hackathon pack")
    from app.services.dashboard import vis
    vis.clear_cache()
    path = str(tmp_path / "b.db")
    dst = sqlite3.connect(path)
    block_master.raw_connection().driver_connection.backup(dst)
    dst.close()
    eng = make_engine("sqlite:///" + path)
    yield eng
    eng.dispose()


@pytest.fixture
def bdb(block_engine):
    with session_factory(block_engine)() as s:
        yield s


@pytest.fixture
def web(block_engine):
    """make(**settings) -> TestClient on the block database; login(client, user) signs in and returns bearer headers."""
    return lambda **kw: build_client(block_engine, _web_settings(**kw))


def login(c, user):
    r = c.post("/api/v1/auth/login", json={"username": user, "password": PASSWORDS[user]})
    assert r.status_code == 200, r.text
    c.cookies.clear()          # use the bearer token only, so phone-key requests made with the same client are not the admin's session
    return {"Authorization": "Bearer " + r.json()["access_token"]}
