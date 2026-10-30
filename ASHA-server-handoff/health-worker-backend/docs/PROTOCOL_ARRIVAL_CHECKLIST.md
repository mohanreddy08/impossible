# When the official protocol documents arrive (Round 2)

The pipeline is built and tested **with non-medical fixtures only**. Nothing below has been run on real protocols. Do these in order; tick each.

## A. Receive and record provenance (human)
- [ ] Obtain the documents from the organisers; keep the original files unchanged and note the source/date received.
- [ ] For each document write a `meta.json`: `document_id`, `title`, `issuing_authority`, `document_version`, `publication_date`, `language` **exactly as printed on the document** (leave a key out if unknown - it stays NULL). Set `page_offset` if printed page numbers differ from PDF page numbers.
- [ ] Decide which documents are in scope for the app (a document the app should not answer from simply is not approved).

## B. Import (nothing is retrievable yet)
- [ ] `python scripts/import_protocols.py import <file> --meta <meta.json>` per document (`.pdf`, `.txt`, `.md`; `[[PAGE n]]` markers or form-feeds for text exports).
- [ ] Read the report: `pages`, `passages_imported`, `passages_skipped_duplicate`, `passages_without_section`, and every `warnings` entry (scanned pages with no text layer are **not OCR'd**).
- [ ] **Telugu / Indic PDFs:** extraction depends on how fonts were embedded and may be garbled. Spot-check, and if garbled supply a human-checked `.txt`/JSONL export instead. Do not approve unchecked extractions.
- [ ] `python scripts/import_protocols.py list` - all documents must show `UNVERIFIED`, `approved=False`.
- [ ] Spot-check passages against the source: exact text, page numbers, section titles (section detection is heuristic: numbered/`Section N`/markdown/ALL-CAPS headings). Fix by editing a text export and re-importing with `--replace` (resets approval).

## C. Review and approve (qualified reviewer)
- [ ] A qualified clinician reviews the imported passages for completeness and exactness.
- [ ] `python scripts/import_protocols.py approve <document_id> --reviewer "<name>"` (refuses without authority + version recorded; fixtures can never be approved). Approval is audited (`audit_log`, `verified_by`, `verified_at`).
- [ ] Re-importing a changed file under the same id requires `--replace` and **resets approval** - re-review.

## D. Safety rules (clinical)
- [ ] Replace the draft lexicon `app/services/safety/rules/danger_rules.json` with rules derived from the approved protocols and reviewed by a qualified professional; bump `version`, set `review_status` and only then `clinically_validated: true`.
- [ ] Replace placeholder messages (`messages.*`) with approved wording; map `expected_rule_id` in `danger_sign_tests` to real rule ids.
- [ ] Re-run `scripts/evaluate_safety.py`; build a NEW held-out evaluation set (the current FINAL split was used to fix rules and is no longer blind).

## E. Retrieval evaluation
- [ ] Label `retrieval_evaluation.jsonl` against the **real** imported `passage_id`s (do not label before import), and fill `expected_answer/document/section/page/evidence` in `health_questions` from the sources.
- [ ] `python scripts/evaluate_retrieval.py` → Recall@1/@3, citation accuracy, unsupported-answer rate, no-result behaviour, by language. Tune `EVIDENCE_MIN_SCORE` / `EVIDENCE_MIN_MATCHED_TERMS` on a dev split, then freeze.
- [ ] Telugu retrieval is exact-token only (no stemming/transliteration). Measure Telugu and code-mixed recall separately; add reviewed synonyms/transliteration only where the metrics justify it.

## F. Ship to the device
- [ ] Export the approved passages (+ FTS index built by the same normalisation) into the app's SQLite (`docs/mobile_sqlite_schema.sql`); bundle with the document version.
- [ ] Production env: `APP_ENV=production`, `AUTH_MODE=api_key`, `ELIGIBLE_VERIFICATION_STATUSES=VERIFIED` (the app refuses anything else), `DOCS_ENABLED=false`, HTTPS, strong `DEVICE_HASH_SALT` and API keys.
- [ ] Re-run the full test suite on SQLite **and** PostgreSQL (`python scripts/run_tests.py`).
