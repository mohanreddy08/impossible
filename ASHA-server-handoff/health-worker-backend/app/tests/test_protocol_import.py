import json
import os
import subprocess
import sys

import pytest
from fpdf import FPDF
from sqlalchemy import select

from app.core.config import BACKEND_ROOT
from app.db.models import AuditLog, ProtocolDocument, ProtocolPassage
from app.services.protocol_import.approval import ApprovalRefused, approve_document, revoke_approval
from app.services.protocol_import.extract import extract_pages
from app.services.protocol_import.importer import DocumentConflict, DocumentMeta, ProtocolImportError, import_protocol_file
from app.services.protocol_import.sections import split_pages

FIX = os.path.join(BACKEND_ROOT, "fixtures", "protocol_fixtures")
EN, TE = os.path.join(FIX, "fixture_guide_en.txt"), os.path.join(FIX, "fixture_guide_te.txt")


def meta(path):
    return DocumentMeta.from_dict(json.load(open(path.replace(".txt", ".meta.json"), encoding="utf-8")))


def approvable(doc_id="TEST-APPROVAL-FLOW"):
    """TEST-ONLY: exercises the approval mechanism with invented, non-medical text. Never use real-looking authorities here."""
    return DocumentMeta(doc_id, title="Approval-flow test doc", issuing_authority="TEST ONLY - invented authority", document_version="test-0", language="en")


# ---------------------------------------------------------------- extraction / sections / exactness
def test_page_markers_and_formfeeds_give_page_numbers():
    assert [p.number for p in extract_pages(EN).pages] == [1, 2]
    assert [p.number for p in extract_pages(TE).pages] == [1, 2]


def test_no_page_info_means_unknown_not_guessed(tmp_path):
    f = tmp_path / "x.txt"; f.write_text("1 Intro\n\nSome text here.\n", encoding="utf-8")
    e = extract_pages(str(f))
    assert e.pages[0].number is None and "no page markers" in e.warnings[0]


def test_sections_detected_with_ids_and_titles():
    d = split_pages(extract_pages(EN).pages)
    secs = [(x.section_id, x.section_title) for x in d]
    assert ("1", "Register upkeep") in secs and ("1.1", "Signature rules") in secs and ("2", "Storage of cards") in secs
    assert any(t == "TRANSPORT DESK" for _, t in secs)
    assert d[0].section_id is None                                  # text before any heading has no section (not invented)
    td = split_pages(extract_pages(TE).pages)
    assert td[0].section_title == "రిజిస్టర్ నిర్వహణ" and td[1].section_title == "వాహన విభాగం"


def test_passage_text_is_exact_slice_of_source_page():
    for path in (EN, TE):
        pages = {p.number: p.text for p in extract_pages(path).pages}
        for d in split_pages(extract_pages(path).pages):
            assert d.text in pages[d.page_number]                      # byte-for-byte substring, incl. ZWNJ in Telugu
    assert "‌" in "".join(d.text for d in split_pages(extract_pages(TE).pages))


def test_passages_never_cross_pages_and_respect_size():
    d = split_pages(extract_pages(EN).pages, max_chars=60)
    assert all(len(x.text) <= 60 or "\n\n" not in x.text for x in d)
    assert {x.page_number for x in d} == {1, 2}


def test_pdf_import_pages_and_text(db, tmp_path):
    pdf = FPDF() 
    for body in ("1 Alpha heading\n\nFirst page sentence about the register.", "2 Beta heading\n\nSecond page sentence about the cabinet."):
        pdf.add_page(); pdf.set_font("Helvetica", size=12); pdf.multi_cell(0, 8, body)
    f = tmp_path / "t.pdf"; f.write_bytes(bytes(pdf.output()))
    rep = import_protocol_file(db, str(f), DocumentMeta("TEST-PDF", source_verification_status="TEST_FIXTURE_ONLY"))
    assert rep.pages == 2 and rep.passages_imported >= 2
    ps = db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == "TEST-PDF").order_by(ProtocolPassage.ordinal)).all()
    assert [p.page_number for p in ps] == [1, 2] and "register" in ps[0].passage_text and ps[1].section_title == "Beta heading"


def test_heading_directly_above_body_and_false_positives(tmp_path):
    from app.services.protocol_import.extract import Page
    d = split_pages([Page(1, "2.3 Visit rules\nThe supervisor signs the register.\nA second line of body.\n\n2 apples are kept in a box\nand a second body line.")])
    assert (d[0].section_id, d[0].section_title) == ("2.3", "Visit rules") and d[0].text.startswith("The supervisor signs")
    assert "Visit rules" not in d[0].text
    assert any("2 apples are kept in a box" in x.text for x in d) and all(x.section_id == "2.3" for x in d)       # not mistaken for a heading


def test_blank_pdf_page_is_reported_not_invented(db, tmp_path):
    pdf = FPDF(); pdf.add_page(); pdf.add_page(); pdf.set_font("Helvetica", size=12); pdf.multi_cell(0, 8, "Only page two has text.")
    f = tmp_path / "b.pdf"; f.write_bytes(bytes(pdf.output()))
    rep = import_protocol_file(db, str(f), DocumentMeta("TEST-BLANK", source_verification_status="TEST_FIXTURE_ONLY"))
    assert any("page 1 has no extractable text" in w for w in rep.warnings)
    assert [p.page_number for p in db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == "TEST-BLANK"))] == [2]


# ---------------------------------------------------------------- import behaviour
def test_import_stores_metadata_and_never_approves(db):
    rep = import_protocol_file(db, EN, meta(EN))
    db.commit()
    assert rep.outcome == "IMPORTED" and rep.passages_imported >= 4
    doc = db.get(ProtocolDocument, "FIXTURE-GUIDE-EN")
    assert doc.source_verification_status == "TEST_FIXTURE_ONLY" and doc.approved_for_retrieval is False
    assert doc.issuing_authority is None and doc.version is None and doc.publication_date is None        # unknown stays NULL
    ps = db.scalars(select(ProtocolPassage).where(ProtocolPassage.document_id == "FIXTURE-GUIDE-EN")).all()
    assert all(not p.approved_for_retrieval and p.source_verification_status == "TEST_FIXTURE_ONLY" and p.content_hash for p in ps)
    sig = [p for p in ps if p.section_id == "1.1"][0]
    assert (sig.page_number, sig.section_title) == (1, "Signature rules") and sig.passage_text.startswith("Only the supervisor signs.")


def test_cannot_import_as_verified_or_with_unknown_fields(db):
    with pytest.raises(ProtocolImportError):
        import_protocol_file(db, EN, DocumentMeta("X-DOC", source_verification_status="VERIFIED"))
    with pytest.raises(ProtocolImportError):
        DocumentMeta.from_dict({"document_id": "X-DOC", "approved": True})
    with pytest.raises(ProtocolImportError):
        import_protocol_file(db, EN, DocumentMeta("bad id!", source_verification_status="UNVERIFIED"))


def test_same_file_never_imported_twice(db):
    import_protocol_file(db, EN, meta(EN)); db.commit()
    again = import_protocol_file(db, EN, meta(EN))
    assert again.outcome == "SKIPPED_UNCHANGED" and again.passages_imported == 0
    other_id = import_protocol_file(db, EN, DocumentMeta("FIXTURE-COPY", source_verification_status="TEST_FIXTURE_ONLY"))
    assert other_id.outcome == "SKIPPED_DUPLICATE_FILE" and db.get(ProtocolDocument, "FIXTURE-COPY") is None
    assert db.query(ProtocolPassage).filter_by(document_id="FIXTURE-GUIDE-EN").count() == len({p.content_hash for p in db.query(ProtocolPassage).filter_by(document_id="FIXTURE-GUIDE-EN")})


def test_duplicate_passages_within_document_stored_once(db, tmp_path):
    f = tmp_path / "d.txt"; f.write_text("[[PAGE 1]]\n1 Head\n\nSame sentence.\n\n[[PAGE 2]]\n1 Head\n\nSame   sentence.\n\nDifferent one.\n", encoding="utf-8")
    rep = import_protocol_file(db, str(f), DocumentMeta("TEST-DUP", source_verification_status="TEST_FIXTURE_ONLY"), max_chars=20)
    assert rep.passages_skipped_duplicate == 1 and rep.passages_imported == 2        # whitespace-normalised comparison


def test_changed_file_same_id_refused_then_replace_resets_approval(db, tmp_path):
    f = tmp_path / "v.txt"; f.write_text("[[PAGE 1]]\n1 Intro\n\nOriginal invented sentence.\n", encoding="utf-8")
    import_protocol_file(db, str(f), approvable()); approve_document(db, "TEST-APPROVAL-FLOW", "Test Reviewer"); db.commit()
    f.write_text("[[PAGE 1]]\n1 Intro\n\nEdited invented sentence.\n", encoding="utf-8")
    with pytest.raises(DocumentConflict):
        import_protocol_file(db, str(f), approvable())
    rep = import_protocol_file(db, str(f), approvable(), replace=True)
    d = db.get(ProtocolDocument, "TEST-APPROVAL-FLOW")
    assert rep.outcome == "REPLACED" and d.source_verification_status == "UNVERIFIED" and d.approved_for_retrieval is False and d.verified_by is None
    assert all(not p.approved_for_retrieval for p in db.query(ProtocolPassage).filter_by(document_id="TEST-APPROVAL-FLOW"))
    assert db.query(ProtocolPassage).filter_by(document_id="TEST-APPROVAL-FLOW").count() == 1


def test_page_offset_records_printed_label(db, tmp_path):
    f = tmp_path / "o.txt"; f.write_text("[[PAGE 1]]\n1 Head\n\nBody text.\n", encoding="utf-8")
    import_protocol_file(db, str(f), DocumentMeta("TEST-OFF", page_offset=4, source_verification_status="TEST_FIXTURE_ONLY"))
    p = db.query(ProtocolPassage).filter_by(document_id="TEST-OFF").one()
    assert p.page_number == 1 and p.page_label == "5"


# ---------------------------------------------------------------- approval gate
def test_fixtures_can_never_be_approved(db):
    import_protocol_file(db, EN, meta(EN))
    with pytest.raises(ApprovalRefused):
        approve_document(db, "FIXTURE-GUIDE-EN", "Dr Reviewer")


def test_approval_needs_reviewer_authority_and_version(db, tmp_path):
    f = tmp_path / "a.txt"; f.write_text("[[PAGE 1]]\n1 Head\n\nBody text.\n", encoding="utf-8")
    import_protocol_file(db, str(f), DocumentMeta("TEST-NOAUTH"))
    with pytest.raises(ApprovalRefused): approve_document(db, "TEST-NOAUTH", "Dr Reviewer")        # no authority/version recorded
    import_protocol_file(db, str(f), DocumentMeta("TEST-NOAUTH", issuing_authority="TEST ONLY authority", document_version="t1"), replace=True)
    with pytest.raises(ApprovalRefused): approve_document(db, "TEST-NOAUTH", "  ")
    with pytest.raises(ApprovalRefused): approve_document(db, "NOPE", "Dr Reviewer")


def test_approve_and_revoke_are_audited(db, tmp_path):
    f = tmp_path / "a.txt"; f.write_text("[[PAGE 1]]\n1 Head\n\nBody text.\n", encoding="utf-8")
    import_protocol_file(db, str(f), approvable())
    n = approve_document(db, "TEST-APPROVAL-FLOW", "Test Reviewer", "unit test"); db.commit()
    d = db.get(ProtocolDocument, "TEST-APPROVAL-FLOW")
    assert n == 1 and d.source_verification_status == "VERIFIED" and d.approved_for_retrieval and d.verified_by == "Test Reviewer" and d.verified_at
    revoke_approval(db, "TEST-APPROVAL-FLOW", "Test Reviewer"); db.commit()
    assert db.get(ProtocolDocument, "TEST-APPROVAL-FLOW").approved_for_retrieval is False
    acts = [a.action for a in db.scalars(select(AuditLog).where(AuditLog.entity_id == "TEST-APPROVAL-FLOW"))]
    assert {"IMPORT_PROTOCOL", "APPROVE_PROTOCOL", "REVOKE_PROTOCOL"} <= set(acts)


# ---------------------------------------------------------------- retrieval gating end-to-end
Q = "Who signs the visit register after the monthly review?"


def _ask(client, q=Q):
    return client.post("/api/v1/health-qa/query", json={"question": q}).json()


def test_unverified_and_fixture_content_is_never_an_answer_source(client, db):
    import_protocol_file(db, EN, meta(EN)); db.commit()
    r = _ask(client)
    assert r["outcome"] == "INSUFFICIENT_EVIDENCE" and r["answer_text"] is None and r["citations"] == []
    f2 = os.path.join(FIX, "fixture_guide_en.txt")
    import_protocol_file(db, f2, DocumentMeta("TEST-UNVERIFIED", title="x", issuing_authority="TEST", document_version="t"), replace=False); db.commit()  # same file -> skipped
    assert _ask(client)["outcome"] == "INSUFFICIENT_EVIDENCE"
    assert client.post("/api/v1/health-qa/retrieve", json={"question": Q}).json()["matches"] == []


def test_fixture_status_only_searchable_when_explicitly_enabled_in_tests(make_client, db):
    import_protocol_file(db, EN, meta(EN)); db.commit()
    for p in db.query(ProtocolPassage): p.approved_for_retrieval = True           # even "approved" flag alone is not enough...
    db.commit()
    assert _ask(make_client())["outcome"] == "INSUFFICIENT_EVIDENCE"             # ...status must be VERIFIED
    r = _ask(make_client(eligible_verification_statuses="VERIFIED,TEST_FIXTURE_ONLY"))
    assert r["outcome"] == "ANSWERED_WITH_EVIDENCE" and r["citations"][0]["source_verification_status"] == "TEST_FIXTURE_ONLY"


def test_approved_document_answers_with_exact_citation_and_revocation_takes_effect(client, db, tmp_path):
    src = open(EN, encoding="utf-8").read()
    f = tmp_path / "ok.txt"; f.write_text(src, encoding="utf-8")
    import_protocol_file(db, str(f), approvable()); db.commit()
    assert _ask(client)["outcome"] == "INSUFFICIENT_EVIDENCE"                    # imported, not yet approved
    approve_document(db, "TEST-APPROVAL-FLOW", "Test Reviewer"); db.commit()
    r = _ask(client)
    assert r["outcome"] == "ANSWERED_WITH_EVIDENCE"
    c = r["citations"][0]
    assert (c["document_id"], c["section_id"], c["page_number"], c["source_verification_status"]) == ("TEST-APPROVAL-FLOW", "1", 1, "VERIFIED")
    assert "The visit register must be signed by the supervisor after each monthly review meeting." in r["answer_text"]
    assert r["answer_text"].count("page 1") == 1 and r["safety"]["clinically_validated"] is False
    revoke_approval(db, "TEST-APPROVAL-FLOW", "Test Reviewer"); db.commit()
    assert _ask(client)["outcome"] == "INSUFFICIENT_EVIDENCE"                    # index cache refreshed


def test_clinical_questions_without_approved_evidence_get_insufficient_evidence(client, db):
    import_protocol_file(db, EN, meta(EN)); db.commit()
    for q in ("How many antenatal check-ups should a pregnant woman have?", "9 months baby కి ఏ vaccine due ఉంది?", "ORS packet entha neellalo kalapali?"):
        assert _ask(client, q)["outcome"] == "INSUFFICIENT_EVIDENCE"


def test_jsonl_dataset_import_dedupes_passages(empty_engine, tmp_path):
    from app.db.session import session_factory
    from app.services.dataset_import.importer import import_datasets
    row = lambda pid, text: json.dumps(dict(document_id="D1", document_title=None, issuing_authority="unknown", document_version="unknown", publication_date="unknown",  # noqa: E731
                                            language="en", section_id="S1", section_title="Sec", page_number=3, passage_id=pid, passage_text=text,
                                            approved_for_retrieval=False, source_verification_status="UNVERIFIED"))
    (tmp_path / "protocol_passages.jsonl").write_text("\n".join([row("P1", "Exact text."), row("P2", "Exact   text."), row("P3", "Other.")]), encoding="utf-8")
    with session_factory(empty_engine)() as s:
        rep = import_datasets(s, str(tmp_path), include_benchmarks=False)
        assert rep["imported"]["protocol_passages"] == 2 and any("duplicate text" in x for x in rep["skipped"])
        d = s.get(ProtocolDocument, "D1")
        assert d.issuing_authority is None and d.version is None and d.title is None and not d.approved_for_retrieval     # "unknown" -> NULL
        assert s.get(ProtocolPassage, "P1").passage_text == "Exact text."


# ---------------------------------------------------------------- CLI
def test_cli_import_list_and_refusal(tmp_path):
    db_url = "sqlite:///%s" % (tmp_path / "cli.db")
    env = dict(os.environ, DATABASE_URL=db_url, ALEMBIC_DATABASE_URL=db_url)
    py = sys.executable
    run = lambda *a: subprocess.run([py, *a], cwd=BACKEND_ROOT, env=env, capture_output=True, text=True)       # noqa: E731
    assert subprocess.run([py, "-m", "alembic", "upgrade", "head"], cwd=BACKEND_ROOT, env=env, capture_output=True).returncode == 0
    r = run("scripts/import_protocols.py", "import", EN, "--meta", EN.replace(".txt", ".meta.json"))
    assert r.returncode == 0 and '"outcome": "IMPORTED"' in r.stdout
    assert '"outcome": "SKIPPED_UNCHANGED"' in run("scripts/import_protocols.py", "import", EN, "--meta", EN.replace(".txt", ".meta.json")).stdout
    out = run("scripts/import_protocols.py", "list").stdout
    assert "FIXTURE-GUIDE-EN" in out and "TEST_FIXTURE_ONLY" in out and "approved=False" in out
    bad = run("scripts/import_protocols.py", "approve", "FIXTURE-GUIDE-EN", "--reviewer", "Dr Reviewer")
    assert bad.returncode != 0 and "ApprovalRefused" in bad.stderr


# ---------------------------------------------------------------- protocol HTTP endpoints
def test_protocol_endpoints_list_get_passages(client, db):
    import_protocol_file(db, EN, meta(EN)); import_protocol_file(db, TE, meta(TE)); db.commit()
    lst = client.get("/api/v1/protocols?limit=1").json()
    assert lst["total"] >= 2 and len(lst["items"]) == 1 and lst["limit"] == 1
    d = client.get("/api/v1/protocols/FIXTURE-GUIDE-TE").json()
    assert d["source_verification_status"] == "TEST_FIXTURE_ONLY" and d["approved_for_retrieval"] is False and d["issuing_authority"] is None
    ps = client.get("/api/v1/protocols/FIXTURE-GUIDE-TE/passages").json()
    assert ps["total"] == 2 and ps["items"][0]["page_number"] == 1 and ps["items"][0]["section_title"] == "రిజిస్టర్ నిర్వహణ"
    assert client.get("/api/v1/protocols/FIXTURE-GUIDE-TE/passages?limit=1&offset=1").json()["items"][0]["page_number"] == 2
    assert client.get("/api/v1/protocols/NOPE").status_code == 404 and client.get("/api/v1/protocols/NOPE/passages").status_code == 404
