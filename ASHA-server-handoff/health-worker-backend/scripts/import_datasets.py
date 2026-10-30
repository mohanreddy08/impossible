#!/usr/bin/env python3
"""Import the supplied datasets into the configured database. Usage: python scripts/import_datasets.py [--no-benchmarks]"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.core.config import get_settings
from app.db.session import get_engine, session_factory
from app.services.dataset_import.importer import import_datasets

s = get_settings()
eng = get_engine()
with session_factory(eng)() as db:
    rep = import_datasets(db, s.resolved_dataset_dir, include_benchmarks="--no-benchmarks" not in sys.argv)
print(json.dumps(rep, indent=2)[:4000])
sys.exit(1 if rep["rejected"] else 0)
