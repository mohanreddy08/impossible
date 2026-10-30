#!/usr/bin/env python3
"""Loads the SAMPLE protocol passages (English + Telugu) into the server's protocol tables, for the demo and for testing the RAG.

  python scripts/load_sample_protocol.py [--replace] [--file PATH]

They are fictional demonstration text marked TEST_FIXTURE_ONLY: they are retrievable only when the server is started with
ELIGIBLE_VERIFICATION_STATUSES that includes TEST_FIXTURE_ONLY (the demo script does this), and every answer built from them carries that status.
REAL documents (the hackathon dataset) do NOT go through this script: use scripts/import_protocols.py (import, then reviewer approval)."""
import argparse, json, os, sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app.db.models import ProtocolDocument, ProtocolPassage
from app.db.session import get_engine, session_factory

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "..", "..", "health-worker-app", "assets", "data", "passages.json")      # built by asha-data/build_data.py

ap = argparse.ArgumentParser()
ap.add_argument("--replace", action="store_true", help="delete and re-load documents that already exist")
ap.add_argument("--file", default=DEFAULT)
args = ap.parse_args()
data = json.load(open(args.file, encoding="utf-8"))
with session_factory(get_engine())() as db:
    added = skipped = 0
    for doc in data["documents"]:
        if doc["status"] != "TEST_FIXTURE_ONLY":
            sys.exit("refusing %s: status %s. This loader is for the sample fixtures only; use scripts/import_protocols.py for real documents." % (doc["document_id"], doc["status"]))
        existing = db.get(ProtocolDocument, doc["document_id"])
        if existing and not args.replace:
            skipped += 1
            continue
        if existing:
            db.query(ProtocolPassage).filter_by(document_id=doc["document_id"]).delete()
            db.delete(existing)
            db.flush()
        db.add(ProtocolDocument(document_id=doc["document_id"], title=doc["titles"].get("en"), issuing_authority=doc.get("issuing_authority"),
                                version=doc.get("version"), language=None, source_verification_status="TEST_FIXTURE_ONLY", approved_for_retrieval=True,
                                source_filename="asha-data/protocols (sample)"))
        db.flush()
        for i, p in enumerate(x for x in data["passages"] if x["document_id"] == doc["document_id"]):
            db.add(ProtocolPassage(passage_id=p["passage_id"], document_id=p["document_id"], section_id=p["section_id"], section_title=p["section_title"],
                                   page_number=p["page_number"], passage_text=p["passage_text"], language=p["language"], approved_for_retrieval=True,
                                   source_verification_status="TEST_FIXTURE_ONLY", content_hash=p["content_hash"], ordinal=i))
        added += 1
    db.commit()
    print("sample protocol: %d documents loaded, %d already there; passages in the table: %d" % (added, skipped, db.query(ProtocolPassage).count()))
