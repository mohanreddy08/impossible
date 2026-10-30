import os
from alembic import context
from sqlalchemy import create_engine

from app.core.config import get_settings
from app.db.base import Base
import app.db.models  # noqa: F401

target_metadata = Base.metadata


def _url():
    return os.environ.get("ALEMBIC_DATABASE_URL") or get_settings().database_url


def run_migrations_online():
    engine = create_engine(_url())
    with engine.connect() as conn:
        context.configure(connection=conn, target_metadata=target_metadata, render_as_batch=conn.dialect.name == "sqlite", compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
    engine.dispose()


run_migrations_online()
