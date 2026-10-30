import os

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from app.core.config import BACKEND_ROOT
from app.db.base import Base
import app.db.models  # noqa: F401


def _cfg():
    c = Config(os.path.join(BACKEND_ROOT, "alembic.ini"))
    c.set_main_option("script_location", os.path.join(BACKEND_ROOT, "alembic"))
    return c


def test_upgrade_creates_all_model_tables_and_downgrade_removes(tmp_path, monkeypatch):
    url = "sqlite:///%s" % (tmp_path / "m.db")
    monkeypatch.setenv("ALEMBIC_DATABASE_URL", url)
    command.upgrade(_cfg(), "head")
    insp = inspect(create_engine(url))
    assert set(Base.metadata.tables) <= set(insp.get_table_names())
    cols = {c["name"] for c in insp.get_columns("referrals")}
    assert {"attendance_confirmed", "attendance_record_id", "version", "record_state"} <= cols
    command.downgrade(_cfg(), "base")
    assert set(Base.metadata.tables).isdisjoint(set(inspect(create_engine(url)).get_table_names()))


def test_models_match_migration_no_drift(tmp_path, monkeypatch):
    from alembic.autogenerate import compare_metadata
    from alembic.migration import MigrationContext
    url = "sqlite:///%s" % (tmp_path / "d.db")
    monkeypatch.setenv("ALEMBIC_DATABASE_URL", url)
    command.upgrade(_cfg(), "head")
    with create_engine(url).connect() as conn:
        diff = compare_metadata(MigrationContext.configure(conn), Base.metadata)
    assert diff == [], diff
