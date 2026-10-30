# Frontline Health-Worker Companion - Backend

FastAPI + SQLAlchemy 2 + Alembic backend for the offline-first ASHA/ANM app. **All household/visit/referral data is synthetic. Clinical content is unapproved.**
The Flutter app is built later and must keep working with **no server**; this API is an optional sync/reporting service.

> The repository's existing `backend/` folder is an unrelated Node storefront, so this project lives in `health-worker-backend/`.
> Datasets are read from `../health-worker-datasets/` (override with `DATASET_DIR`).

> **Supervisor website and public access (0.3.0):** accounts, per-phone keys, dashboard/admin/ask API and the website are described in
> [`../docs/SERVER_DESIGN.md`](../docs/SERVER_DESIGN.md); running it and reaching it from phones in [`../README.md`](../README.md).
> The phone endpoints below are unchanged. `API_KEYS` still works; per-phone keys made on the website are the recommended way.

## Status and honest limitations
- **Tests:** see [`docs/VALIDATION_REPORT.md`](docs/VALIDATION_REPORT.md) (generated from real runs). SQLite and PostgreSQL 16.2 are both exercised; counts are listed there.
- **No official protocol documents yet.** Retrieval and the protocol importer are tested only with clearly labelled **non-medical fixtures** (`fixtures/protocol_fixtures/`, status `TEST_FIXTURE_ONLY`, never approvable).
  Every clinical question returns `INSUFFICIENT_EVIDENCE`. Retrieval metrics (Recall@k, citation accuracy) are `NOT_EVALUABLE` until real passages exist. Checklist: [`docs/PROTOCOL_ARRIVAL_CHECKLIST.md`](docs/PROTOCOL_ARRIVAL_CHECKLIST.md).
- **The safety rules are NOT clinically validated.** `danger_rules.json` is a software-test lexicon (`clinically_validated: false`, status `DRAFT_UNREVIEWED_NOT_CLINICALLY_APPROVED`) and the message texts are placeholders.
  Perfect scores on the synthetic cases say nothing about real-world detection; the FINAL split is no longer blind (rules were adjusted after a failure).
- Other limits: no rate limiting or lockout on API keys; API keys are static env values (use OIDC/OAuth2 for real deployments); report counts can be small enough to be identifying in tiny facilities (no small-cell suppression);
  Telugu retrieval is exact-token only; PDF import does no OCR and Telugu PDF extraction is unverified; no load/concurrency testing beyond a 6-thread identical-push test; reports on the server are not signed or tamper-evident.
- The Flutter app, UI and on-device code are **not built**; `docs/mobile_sqlite_schema.sql` is verified to compile but is a specification.

## Architecture
```
app/api/v1/*        HTTP only: routing, auth dependency, response models
app/schemas/        Pydantic request/response models (the contract)
app/services/       business logic, NO FastAPI imports (enforced by tests, incl. a run with fastapi blocked):
                    safety/ (deterministic rules, isolated from DB/retrieval/HTTP)   protocol_retrieval/ (FTS5)   protocol_import/
                    health_qa/   households/   visits/   referrals/   reports/   synchronization/   dataset_import/
app/core/           config, errors, principal.py (framework-free identity), security.py (FastAPI auth dependency)
app/db/models/      SQLAlchemy models        alembic/  migrations (0001 initial, 0002 protocol provenance + report scope)
```
QA order: validate → normalise → **deterministic safety** → (escalate / clarify / refuse and stop) → retrieve → evidence threshold → verbatim approved passage + citations → final validation. No LLM anywhere.

## Setup
```bash
cd health-worker-backend
python3 -m venv .venv && .venv/bin/pip install -U pip && .venv/bin/pip install -r requirements-dev.txt   # Python 3.9+
cp .env.example .env                      # edit; never commit .env
.venv/bin/alembic upgrade head            # create/upgrade schema
.venv/bin/python scripts/dataset_manifest.py   # inspect datasets -> data/dataset_manifest.json
.venv/bin/python scripts/import_datasets.py    # idempotent; exit 1 if any row is rejected
.venv/bin/uvicorn app.main:app --reload        # http://127.0.0.1:8000/docs
```

## Environment variables (`.env.example` documents all)
| Variable | Default | Purpose |
|---|---|---|
| `APP_ENV` | development | `production` enforces: auth enabled, only `VERIFIED` retrieval |
| `DATABASE_URL` | `sqlite:///./health_companion.db` | SQLAlchemy URL (see below) |
| `DATASET_DIR` | `../health-worker-datasets` | where the importer reads datasets |
| `AUTH_MODE` | disabled | `disabled` = **no authentication, local dev only**; `api_key` = require `X-API-Key` |
| `API_KEYS` | (empty) | `role|worker_id|key;...` roles `worker`, `admin`, `hospital` |
| `DEVICE_HASH_SALT` | dev value | salt for hashing installation ids - set a long random value |
| `EVIDENCE_MIN_SCORE`, `EVIDENCE_MIN_MATCHED_TERMS` | 0.5, 2 | retrieval evidence threshold |
| `ELIGIBLE_VERIFICATION_STATUSES` | VERIFIED | statuses searchable by retrieval (tests only add `TEST_FIXTURE_ONLY`) |
| `REFERENCE_DATE` | blank | pin "today" for the synthetic data (datasets anchor at 2026-10-13) |
| `RECENT_COMPLETION_DAYS`, `FRESH_HOURS`, `RECENT_HOURS` | 14, 24, 72 | synthetic-data convention / report freshness policy (not clinical) |
| `DOCS_ENABLED` | true | `false` hides `/docs` and `/openapi.json` |

## Database configuration
- **SQLite** (default, local dev/tests): `DATABASE_URL=sqlite:///./health_companion.db` (WAL mode, foreign keys on).
- **PostgreSQL** (production-style): `pip install -r requirements-postgres.txt`, then `DATABASE_URL=postgresql+psycopg2://user:PASSWORD@host:5432/health_companion` and `alembic upgrade head`.
  Verified on PostgreSQL 16.2 (see test matrix). The schema avoids dialect-specific SQL.
- **Migrations:** `alembic upgrade head`, `alembic downgrade -1`; after changing models: `alembic revision --autogenerate -m "..."` and review. A test fails if models and migrations drift (both backends).

## Tests
```bash
.venv/bin/python -m pytest                          # SQLite (default)
.venv/bin/pip install -r requirements-pgtest.txt    # once: self-contained PostgreSQL 16 for tests
TEST_DB=postgres .venv/bin/python -m pytest         # the same suite on real PostgreSQL (+ PG migration tests)
.venv/bin/python scripts/run_tests.py               # both backends -> docs/test_report.json (actual counts)
.venv/bin/python scripts/evaluate_safety.py         # FN/FP per split
.venv/bin/python scripts/evaluate_qa.py             # supplied questions through the pipeline
.venv/bin/python scripts/evaluate_retrieval.py      # NOT_EVALUABLE until real passages + eval cases exist
.venv/bin/python scripts/export_openapi.py && .venv/bin/python scripts/export_examples.py   # refresh docs/
```
(A harmless "Logging error ... closed file" line may print when the PostgreSQL helper shuts down at interpreter exit.)

## Protocol documents (operator workflow; no upload endpoint exists)
```bash
.venv/bin/python scripts/import_protocols.py import path/doc.pdf --meta doc.meta.json   # -> UNVERIFIED, NOT retrievable
.venv/bin/python scripts/import_protocols.py list
.venv/bin/python scripts/import_protocols.py approve DOC-ID --reviewer "Dr Name"          # explicit, audited; fixtures refused
```
Exact source text is preserved, metadata not supplied stays NULL, duplicate files/passages are skipped, a changed file under the same id needs `--replace` and loses approval.

## API usage (details: `docs/API_CONTRACT.md`, `docs/FLUTTER_INTEGRATION_GUIDE.md`, `docs/openapi.json`, `docs/api_examples.json`)
```bash
curl -s localhost:8000/api/v1/health-qa/query -H 'content-type: application/json' -d '{"question":"Pregnant woman is bleeding heavily right now"}'
curl -s 'localhost:8000/api/v1/follow-ups?bucket=OVERDUE&limit=5'                       # add -H 'X-API-Key: ...' when AUTH_MODE=api_key
curl -s localhost:8000/api/v1/reports/summary -H 'content-type: application/json' -d '{"facility_id":"FAC-SYN-01","period_start":"2026-06-01","period_end":"2026-10-13"}'
```

## Security and privacy summary
Role-based access (workers confined to their own households; cross-worker ids → 404); only hospital/admin can confirm attendance; stored reports are scoped to their creator;
installation ids are hashed and kept out of URLs; health text and request payloads are never logged (tested); evaluation labels live in `benchmark_cases` and no route serves them (tested);
unknown request fields are rejected; production refuses auth-disabled and non-`VERIFIED` retrieval. Serve over HTTPS behind a reverse proxy.

## Troubleshooting
| Symptom | Fix |
|---|---|
| `no such table` | `alembic upgrade head` (SQLite path is relative to the working dir) |
| Everything is `INSUFFICIENT_EVIDENCE` | expected until approved protocol passages exist |
| 401 on every call | `AUTH_MODE=api_key`: send `X-API-Key` |
| `database is locked` (SQLite) | another process holds the file; use PostgreSQL for multi-user |
| importer exits 1 | read `rejected` in its output; rows are reported, never silently fixed |
| `psycopg2` install fails | `pip install -U pip`; use `requirements-postgres.txt` |
| `TEST_DB=postgres` fails to start | install `requirements-pgtest.txt`; the tests need no system PostgreSQL |
