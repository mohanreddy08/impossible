"""Database-level guarantees. Runs on whichever backend TEST_DB selects (sqlite default, postgres) and proves which one it was."""
import datetime as dt
import os

import pytest
from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.config import Config
from alembic.migration import MigrationContext
from sqlalchemy import create_engine, inspect, select, text
from sqlalchemy.exc import IntegrityError

from app.core.config import BACKEND_ROOT
from app.db.base import Base
from app.db.models import Household, ProtocolDocument, ProtocolPassage, Referral, Visit
from app.tests.conftest import PG, _pg_admin, _pg_url


def test_backend_under_test_is_what_was_requested(engine):
    assert engine.dialect.name == ("postgresql" if PG else "sqlite")
    with engine.connect() as c:
        ver = c.execute(text("select version()" if PG else "select sqlite_version()")).scalar()
    print("DB under test:", engine.dialect.name, ver)
    if PG:
        assert "PostgreSQL" in ver


def _violates(db, obj):
    db.add(obj)
    with pytest.raises(IntegrityError):
        db.flush()
    db.rollback()


def test_foreign_keys_enforced(db):
    _violates(db, Visit(visit_id="V-FK-1", household_id="NO-SUCH-HH", worker_id="W", scheduled_date=dt.date(2026, 1, 1), visit_status="PLANNED", visit_reason="ROUTINE"))
    ref = db.scalar(select(Referral))
    _violates(db, Referral(referral_id="R-FK-1", household_id="NO-SUCH", visit_id=ref.visit_id, facility_id=ref.facility_id, service_category="GENERAL",
                           referral_created_date=dt.date(2026, 1, 1), referral_status="RECOMMENDED", attendance_confirmed=False))


@pytest.mark.parametrize("bad", ["status", "members", "visit_ref", "attendance_flag", "referral_state"])
def test_check_constraints_enforced(db, bad):
    h = db.scalar(select(Household))
    if bad == "status":
        _violates(db, Visit(visit_id="V-CK-1", household_id=h.household_id, worker_id="W", scheduled_date=dt.date(2026, 1, 1), visit_status="NONSENSE", visit_reason="ROUTINE"))
    elif bad == "members":
        _violates(db, Household(household_id="HH-CK-1", village_id="V", assigned_worker_id="W", household_member_count=0, record_status="OVERDUE"))
    elif bad == "visit_ref":
        _violates(db, Visit(visit_id="V-CK-2", household_id=h.household_id, worker_id="W", scheduled_date=dt.date(2026, 1, 1), visit_status="PLANNED", visit_reason="ROUTINE", referral_status="ATTENDED"))
    else:
        r = db.scalar(select(Referral).where(Referral.referral_status == "PLANNED"))
        if bad == "attendance_flag":
            r.attendance_confirmed = True            # confirmed flag without ATTENDANCE_CONFIRMED status
        else:
            r.record_state = "WEIRD"
        with pytest.raises(IntegrityError):
            db.flush()
        db.rollback()


def test_passage_duplicate_text_per_document_rejected(db):
    db.add(ProtocolDocument(document_id="DB-DOC", source_verification_status="UNVERIFIED"))
    db.add(ProtocolPassage(passage_id="DB-1", document_id="DB-DOC", passage_text="a", content_hash="h1"))
    db.commit()
    _violates(db, ProtocolPassage(passage_id="DB-2", document_id="DB-DOC", passage_text="a", content_hash="h1"))
    db.add(ProtocolPassage(passage_id="DB-3", document_id="DB-DOC", passage_text="a", content_hash=None))     # NULL hashes are not constrained
    db.add(ProtocolPassage(passage_id="DB-4", document_id="DB-DOC", passage_text="a", content_hash=None))
    db.commit()
    assert db.query(ProtocolPassage).filter_by(document_id="DB-DOC").count() == 3


def test_json_and_datetime_roundtrip(db):
    from app.db.models import BenchmarkCase, SyncOperation
    db.add(BenchmarkCase(dataset="rt", case_id="1", payload={"te": "గర్భిణీ", "n": [1, 2], "nested": {"k": None}}))
    db.add(SyncOperation(op_id="op-rt-0001", idempotency_key="idem-rt-0001", installation_hash="h", entity_type="visit", entity_id="V", op_type="create",
                         status="CONFLICT", conflict={"server_values": {"x": "2026-01-01"}}))
    db.commit()
    got = db.scalar(select(BenchmarkCase).where(BenchmarkCase.dataset == "rt"))
    assert got.payload == {"te": "గర్భిణీ", "n": [1, 2], "nested": {"k": None}}
    assert db.get(SyncOperation, "op-rt-0001").conflict["server_values"]["x"] == "2026-01-01"


def test_savepoint_rollback_keeps_earlier_work(db):
    db.add(Household(household_id="HH-SP-1", village_id="V", assigned_worker_id="W", household_member_count=2, record_status="NO_VISIT_DUE")); db.commit()
    with pytest.raises(IntegrityError):
        with db.begin_nested():
            db.add(Household(household_id="HH-SP-2", village_id="V", assigned_worker_id="W", household_member_count=2, record_status="NO_VISIT_DUE"))
            db.add(Household(household_id="HH-SP-3", village_id="V", assigned_worker_id="W", household_member_count=0, record_status="NO_VISIT_DUE"))
    db.commit()
    ids = {h for (h,) in db.execute(select(Household.household_id).where(Household.household_id.like("HH-SP-%")))}
    assert ids == {"HH-SP-1"}


def test_like_filters_and_ordering_match_across_backends(db):
    from app.core.principal import Principal
    from app.services.households import service
    rows, total = service.list_households(db, Principal("admin", None, "t"), category="ANC", limit=500)
    assert total == len(rows) > 0 and all("|ANC|" in h.eligible_followup_categories for h in rows)
    assert [h.household_id for h in rows] == sorted(h.household_id for h in rows)


# ---------------- PostgreSQL migrations (only meaningful when TEST_DB=postgres) ----------------
@pytest.mark.skipif(not PG, reason="PostgreSQL not selected (run with TEST_DB=postgres)")
def test_postgres_migrations_upgrade_downgrade_and_no_drift(pg_server):
    _pg_admin(pg_server, "CREATE DATABASE mig_check")
    url = _pg_url(pg_server, "mig_check").render_as_string(hide_password=False)
    os.environ["ALEMBIC_DATABASE_URL"] = url
    try:
        cfg = Config(os.path.join(BACKEND_ROOT, "alembic.ini"))
        cfg.set_main_option("script_location", os.path.join(BACKEND_ROOT, "alembic"))
        command.upgrade(cfg, "head")
        eng = create_engine(url)
        assert set(Base.metadata.tables) <= set(inspect(eng).get_table_names())
        with eng.connect() as conn:
            assert compare_metadata(MigrationContext.configure(conn), Base.metadata) == []
        command.downgrade(cfg, "0001")
        cols = {c["name"] for c in inspect(create_engine(url)).get_columns("reports")}
        assert "scope" not in cols
        command.downgrade(cfg, "base")
        assert set(Base.metadata.tables).isdisjoint(set(inspect(create_engine(url)).get_table_names()))
        command.upgrade(cfg, "head")                           # and back up again
        eng.dispose()
    finally:
        os.environ.pop("ALEMBIC_DATABASE_URL", None)
        _pg_admin(pg_server, "DROP DATABASE IF EXISTS mig_check WITH (FORCE)")
