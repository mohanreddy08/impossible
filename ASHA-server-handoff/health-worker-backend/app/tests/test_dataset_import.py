import os

from sqlalchemy import func, select

from app.db.models import BenchmarkCase, Facility, Household, ProtocolPassage, Referral, Visit
from app.services.dataset_import.manifest import EXPECTED, build_manifest
from app.tests.conftest import DATASETS


def _lines(fn):
    with open(os.path.join(DATASETS, fn), encoding="utf-8") as f:
        n = sum(1 for l in f if l.strip())
    return n - 1 if fn.endswith(".csv") else n          # CSV header


def test_manifest_counts_equal_actual_files():
    m = build_manifest(DATASETS)
    for name, (fn, _) in EXPECTED.items():
        assert m["counts"][name] == _lines(fn), name        # never assume 200/500: compare with the real files


def test_manifest_reports_blockers_honestly():
    m = build_manifest(DATASETS)
    msgs = " ".join(i["message"] for i in m["issues"])
    if m["counts"]["protocol_passages"] == 0:
        assert "no protocol source passages" in msgs
    assert m["questions"]["unverified"] == m["questions"]["total"]       # no verified answers exist
    assert all(v == 0 for v in m["cross_dataset_fk_failures"].values())


def test_import_loads_everything_without_rejections(master_conn):
    rep = master_conn.report
    assert rep["rejected"] == []
    assert rep["imported"]["households"] == _lines("household_register_500.csv")
    assert rep["imported"]["visits"] == _lines("visit_history.csv")
    assert rep["imported"]["referrals"] == _lines("referral_records.csv")


def test_db_counts_and_fk_integrity(db):
    assert db.scalar(select(func.count()).select_from(Household)) == _lines("household_register_500.csv")
    assert db.scalar(select(func.count()).select_from(Visit)) == _lines("visit_history.csv")
    assert db.scalar(select(func.count()).select_from(Referral)) == _lines("referral_records.csv")
    assert db.scalar(select(func.count()).select_from(Facility)) >= 3
    assert db.scalar(select(func.count()).select_from(ProtocolPassage)) == _lines("protocol_passages.jsonl")
    orphans = db.execute(select(func.count()).select_from(Visit).outerjoin(Household, Household.household_id == Visit.household_id).where(Household.household_id.is_(None))).scalar()
    assert orphans == 0
    assert db.execute(select(func.count()).select_from(Referral).outerjoin(Visit, Visit.visit_id == Referral.visit_id).where(Visit.visit_id.is_(None))).scalar() == 0


def test_ids_preserved(db):
    ids = {h for (h,) in db.execute(select(Household.household_id))}
    with open(os.path.join(DATASETS, "household_register_500.csv"), encoding="utf-8") as f:
        src = {l.split(",")[0] for l in f.readlines()[1:]}
    assert ids == src


def test_importer_is_idempotent(engine):
    from app.db.session import session_factory
    from app.services.dataset_import.importer import import_datasets
    with session_factory(engine)() as s:
        before = s.scalar(select(func.count()).select_from(Visit))
        rep = import_datasets(s, DATASETS)
        assert s.scalar(select(func.count()).select_from(Visit)) == before
        assert rep["rejected"] == []


def test_benchmarks_stored_separately(db):
    n = db.scalar(select(func.count()).select_from(BenchmarkCase).where(BenchmarkCase.dataset == "health_questions"))
    assert n == _lines("health_questions_200.jsonl")


def test_importer_rejects_bad_rows_instead_of_hiding_them(empty_engine, tmp_path):
    from app.db.session import session_factory
    from app.services.dataset_import.importer import import_datasets
    (tmp_path / "household_register_500.csv").write_text(
        "household_id,village_id,assigned_worker_id,household_member_count,eligible_followup_categories,last_visit_date,next_visit_due_date,scheduled_followup_category,record_status,last_updated_timestamp,synthetic_record\n"
        "HH-X-1,V1,W1,3,ROUTINE,,,,BOGUS,2026-01-01T10:00:00+05:30,true\n", encoding="utf-8")
    with session_factory(empty_engine)() as s:
        rep = import_datasets(s, str(tmp_path), include_benchmarks=False)
    assert rep["rejected"] and rep["rejected"][0]["id"] == "HH-X-1" and rep["imported"]["households"] == 0
