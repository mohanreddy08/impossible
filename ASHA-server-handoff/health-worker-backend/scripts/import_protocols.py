#!/usr/bin/env python3
"""Protocol source workflow (run when the official documents arrive).

  import   <file.txt|.md|.pdf> --meta meta.json [--replace]    -> UNVERIFIED, not retrievable
  approve  <document_id> --reviewer "Dr Name" [--note "..."]   -> VERIFIED + retrievable (explicit, audited)
  revoke   <document_id> --reviewer "Dr Name"
  list
meta.json keys: document_id (required), title, issuing_authority, document_version, publication_date, language,
source_verification_status (UNVERIFIED|TEST_FIXTURE_ONLY), page_offset. Missing keys stay NULL (never inferred)."""
import argparse, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from sqlalchemy import select
from app.db.models import ProtocolDocument, ProtocolPassage
from app.db.session import get_engine, session_factory
from app.services.protocol_import.approval import approve_document, revoke_approval
from app.services.protocol_import.importer import DocumentMeta, import_protocol_file

ap = argparse.ArgumentParser()
sub = ap.add_subparsers(dest="cmd", required=True)
i = sub.add_parser("import"); i.add_argument("file"); i.add_argument("--meta", required=True); i.add_argument("--replace", action="store_true"); i.add_argument("--max-chars", type=int, default=900)
a = sub.add_parser("approve"); a.add_argument("document_id"); a.add_argument("--reviewer", required=True); a.add_argument("--note", default="")
r = sub.add_parser("revoke"); r.add_argument("document_id"); r.add_argument("--reviewer", required=True)
sub.add_parser("list")
args = ap.parse_args()
with session_factory(get_engine())() as db:
    if args.cmd == "import":
        rep = import_protocol_file(db, args.file, DocumentMeta.from_dict(json.load(open(args.meta, encoding="utf-8"))), replace=args.replace, max_chars=args.max_chars)
        db.commit(); print(json.dumps(rep.as_dict(), indent=2))
    elif args.cmd == "approve":
        n = approve_document(db, args.document_id, args.reviewer, args.note); db.commit(); print("approved %d passages" % n)
    elif args.cmd == "revoke":
        n = revoke_approval(db, args.document_id, args.reviewer); db.commit(); print("revoked %d passages" % n)
    else:
        for d in db.scalars(select(ProtocolDocument)):
            n = db.query(ProtocolPassage).filter_by(document_id=d.document_id).count()
            print("%-24s %-18s approved=%-5s passages=%d authority=%s version=%s" % (d.document_id, d.source_verification_status, d.approved_for_retrieval, n, d.issuing_authority, d.version))
