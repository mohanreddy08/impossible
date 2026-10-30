# Validation report (generated from actual runs)

## Test matrix - what was tested on which database
| Backend | Total | Passed | Failed | Skipped | Time |
|---|---|---|---|---|---|
| sqlite | 427 | 426 | 0 | 1 | 11.372s |
| postgresql | 427 | 427 | 0 | 0 | 23.327s |

Skipped on SQLite: test_database::test_postgres_migrations_upgrade_downgrade_and_no_drift - PostgreSQL not selected (run with TEST_DB=postgres). PostgreSQL = real PostgreSQL 16.2 (via `pgserver`), template database built by running Alembic migrations 0001-0002, each test on a fresh copy.
Not tested: any other PostgreSQL version/host, managed-database features (pooling, SSL), load/performance, Flutter client, real protocol documents.

| Test file | SQLite | PostgreSQL |
|---|---|---|
| test_architecture_hardening | 29 | 29 |
| test_database | 11 | 12 |
| test_dataset_import | 8 | 8 |
| test_health_qa | 13 | 13 |
| test_households_visits | 12 | 12 |
| test_migrations | 2 | 2 |
| test_protocol_import | 24 | 24 |
| test_referrals | 10 | 10 |
| test_reports | 65 | 65 |
| test_retrieval | 15 | 15 |
| test_safety | 151 | 151 |
| test_security_api | 20 | 20 |
| test_sync | 66 | 66 |

## Audit findings and fixes (this phase)
| # | Finding | Fix | Verified by |
|---|---|---|---|
| 1 | 5 services imported FastAPI indirectly (via `core.security`) | `core/principal.py` is framework-free; services import only that | AST test + subprocess run with `fastapi` import blocked |
| 2 | **Any authenticated worker could read any stored report by id** | reports stored with creator scope; workers read only their own; privileged roles read all | `test_reports_are_scoped_to_their_creator` |
| 3 | Device installation id was a URL query parameter on `GET /sync/status` (ends up in access logs) | moved to `X-Installation-Id` header | OpenAPI + behaviour test |
| 4 | **Sync race (found on PostgreSQL, hidden by SQLite locking):** two identical pushes made the loser's REJECTED record collide with the winner's and surface as HTTP 409 | every outcome path now tolerates the collision and answers with the winner's result | 6-thread concurrency test, 3 repeat PostgreSQL runs |
| 5 | DB commit failure during sync would have crashed the whole push and lost per-op results | per-op `FAILED_RETRYABLE` (not acknowledged, nothing stored) | commit-failure injection test |
| 6 | A rejected op was permanently "duplicate" on resend even when the cause (e.g. missing parent) was later fixed | rejected ops are re-evaluated on resend | `test_partial_failure_*` |
| 7 | Protocol cache could serve stale index after approve/revoke | cache signature includes eligible count + text length | `test_approved_document_answers..._revocation_takes_effect` |
| 8 | Importer heading detection missed headings on the line above their body (typical PDF text) | first-line numbered-heading detection, with lower-case false-positive guard | importer tests |
| 9 | `report` and `sync push` had untyped responses; error responses undocumented | typed `ReportOut`, `SyncPushOut`, `SyncStatusOut`; 401/403/404/409/422/500 documented on every operation | OpenAPI completeness test (21 operations) |
| 10 | Referral wording could be misread as attendance | server-side `status_label`; only a hospital attendance record yields "confirmed by hospital record" | label tests over all 268 referrals |
| 11 | Safety output did not say plainly it is unvalidated | `clinically_validated:false` in every QA response and in the ruleset | API + engine tests |
| 12 | Production could be configured to retrieve fixtures/unverified content | startup refuses any eligible status other than `VERIFIED` | config guard test |

## Safety engine (`data/safety_evaluation.json`), ruleset 0.1.0-draft - NOT CLINICALLY VALIDATED
- FINAL_EVALUATION: 107 synthetic cases, exact-status accuracy 1.0, escalation recall 32/32, false negatives 0, false positives 0
- ALL: 142 synthetic cases, exact-status accuracy 1.0, escalation recall 48/48, false negatives 0, false positives 0
- RULE_DEVELOPMENT: 35 synthetic cases, exact-status accuracy 1.0, escalation recall 16/16, false negatives 0, false positives 0

These figures describe agreement with labels written by the same author as the rule vocabulary. They do **not** demonstrate clinical accuracy. Two rules were adjusted after a FINAL-split failure,
so that split is no longer blind. Rules and messages require clinical review against approved protocols.

## Datasets and blockers (`data/dataset_manifest.json`)
- health_questions: 200
- danger_sign_tests: 142
- protocol_passages: 0
- households: 500
- visits: 2032
- referrals: 268
- hospital_report_tests: 55
- offline_sync_tests: 52
- retrieval_evaluation: 0

Blockers (need official documents, cannot be fixed in code): `protocol_passages.jsonl` and `retrieval_evaluation.jsonl` are empty; expected answers/citations in `health_questions` are unverified/null.
Consequently retrieval accuracy, citation accuracy and answer correctness are **not measured**. Protocol import/indexing/dedupe/approval mechanics are tested with non-medical fixtures only.

## Unfinished work
See `docs/PROTOCOL_ARRIVAL_CHECKLIST.md` (documents, clinical review of rules, retrieval evaluation, production hardening) and the limitations list in `README.md`.
