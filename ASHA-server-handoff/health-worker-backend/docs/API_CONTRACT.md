# API contract (v1) - for the Flutter client

Machine-readable spec: [`openapi.json`](openapi.json) (also live at `/openapi.json`, `/docs`). Real request/response pairs: [`api_examples.json`](api_examples.json).
Local SQLite schema: [`mobile_sqlite_schema.sql`](mobile_sqlite_schema.sql). Base path `/api/v1`. JSON, UTF-8.

## Conventions
- **Dates** `YYYY-MM-DD`; **timestamps** ISO-8601, server emits UTC (`...Z`); inputs with offsets (e.g. `+05:30`) are accepted.
- **Pagination** (all list endpoints): `?limit=` (1-200, default 50) and `?offset=`; response `{items, total, limit, offset}`.
- **Errors** (every failure, incl. 401/404/422/500): `{"error": {"code": "STRING_CODE", "message": "...", "details": null|any}}`.
  Codes you should handle: `VALIDATION_ERROR` (422, `details` = per-field list), `NOT_FOUND`, `UNAUTHORIZED`, `FORBIDDEN`, `VERSION_CONFLICT` (409),
  `DUPLICATE_ID`, `DUPLICATE_REFERRAL`, `INVALID_TRANSITION`, `VISIT_FINAL`, `INTEGRITY_ERROR`, `INTERNAL_ERROR` (generic, no internals).
- **Device id**: `installation_id` goes in the push body and the `X-Installation-Id` header of `GET /sync/status` - never in a URL.
- **Versioning / optimistic concurrency**: households, visits and referrals carry `version`. PATCH accepts optional `version`; a mismatch is `409 VERSION_CONFLICT`.
- Unknown request fields are rejected (`extra=forbid`): the API never accepts names, phone numbers or other personal fields.
- Unrequested entity groups in `GET /sync/pull` come back as `null`.

## Authentication
Header `X-API-Key: <key>` when the server runs with `AUTH_MODE=api_key`. Roles: `worker` (own worker_id only; cross-worker lookups return 404, explicit
other `worker_id` filters return 403), `admin`, `hospital` (the latter two may confirm attendance). `AUTH_MODE=disabled` (dev) needs no header.
`GET /health` is open and returns only `{status, auth_mode}`.

## Endpoints
| Area | Endpoint | Notes |
|---|---|---|
| Health QA | `POST /health-qa/query` | outcome ∈ ANSWERED_WITH_EVIDENCE, ESCALATION_REQUIRED, CLARIFICATION_REQUIRED, OUT_OF_SCOPE, INSUFFICIENT_EVIDENCE. Always includes `safety{status, rule_ids, reasons, ruleset_version, ruleset_review_status, needs_human_review}`. `answer_text` only with citations. |
| | `POST /health-qa/retrieve` | raw retrieval (status MATCH_FOUND / NO_RESULT / BELOW_THRESHOLD), exact passage + citation metadata |
| Protocols | `GET /protocols`, `/protocols/{id}`, `/protocols/{id}/passages` | read-only |
| Households | `GET/POST /households`, `GET/PATCH /households/{id}` | filters: `q, village_id, worker_id, status, category, due_before` |
| Visits | `GET/POST /visits`, `PATCH /visits/{id}` | filters: `worker_id, household_id, status, category, date_from, date_to`. Completing a visit recomputes the household's last/next dates and status |
| Follow-ups | `GET /follow-ups` | = PLANNED visits. `bucket=OVERDUE|DUE_TODAY|UPCOMING`, `as_of`, `on_date`, `worker_id`, `household_id`, `category`. Each item has `explanation` |
| Referrals | `GET/POST /referrals`, `PATCH /referrals/{id}` | RECOMMENDED -> PLANNED -> ATTENDANCE_CONFIRMED only; confirmation needs `attendance_record_id` + date + admin/hospital role |
| Reports | `POST /reports/summary`, `GET /reports/{id}?format=json|csv|pdf` | idempotent by content hash; later changes create a new report and mark the old one `superseded_by` |
| Sync | `POST /sync/push`, `GET /sync/pull`, `GET /sync/status` (header `X-Installation-Id`) | see below |

Dataset deviations from your proposal: follow-ups are derived from PLANNED visits (no separate table); `POST /reports/summary` also accepts
`referral_ids` (the device's local set) and `last_sync_at`; referrals carry `record_state` (ACTIVE/CANCELLED/INVALID/DUPLICATE) and `attendance_record_id`,
which the supplied dataset contains and the report rules need.

## Sync protocol
Push `{installation_id, operations[≤200]}`; each op: `op_id` (client UUID-like, unique), optional `idempotency_key`, `entity_type` (household|visit|referral),
`entity_id` (client-chosen for creates), `op_type` (create|update), `base_version` (**required for updates**: the server `version` the client last saw),
`client_created_at/updated_at`, `payload`. Response has one result per op:
`status` ACKNOWLEDGED | REJECTED | CONFLICT, `acknowledged` (true **only after the server committed**), `duplicate`, `server_version`, `error_code`, `conflict`, `warnings`.
- **Client rule:** keep an op (and the local edit) in the outbox until it is `acknowledged: true`. Never mark data synced on any other signal; a network failure means "unknown - resend".
- **Idempotent:** resending an op_id (or idempotency_key) returns the original result with `duplicate: true`; no second write. A *rejected* op changed nothing and may be resent (e.g. after its parent record syncs).
- **Conflicts:** an update with `base_version` older than the server's that touches a *protected* field (referral status/dates/attendance/state/facility; visit status/dates/follow-up/referral link; household worker/schedule/status) is **not applied**: `CONFLICT` with `server_values`, `client_values`, `server_version`. Resolve on the device, then send a new op with the new `base_version`. Stale updates touching only other fields are merged and the overwritten values are returned in `conflict.superseded`.
- **Duplicate referrals** (same household+visit+service) created on two devices are both kept: the first stays ACTIVE, later ones become DUPLICATE (`warnings: DUPLICATE_FLAGGED:duplicate_of=...`) and are excluded from report counts.
- Workers cannot set ATTENDANCE_CONFIRMED (rejected); it must come from a hospital/admin principal.
- `GET /sync/pull?since=<server_time from last pull>&entity_types=household,visit,referral&limit=` returns changed records and `server_time` to use next time.

## Offline / online responsibilities
| Capability | On device (must work with no network) | Server (optional) |
|---|---|---|
| Danger-sign detection, escalation | **yes** - port `danger_rules.json` + engine; must never wait for an API call | same engine for web/admin |
| Protocol Q&A / retrieval | **yes** - bundled verified passages + FTS5 (`mobile_sqlite_schema.sql`) | same logic via API |
| Households, visits, follow-up lists, outcomes | **yes** - local SQLite, recompute rules in `app/services/visits/service.py` | system of record after sync |
| Referral recording | **yes** (RECOMMENDED/PLANNED) | attendance confirmation comes from hospital/admin |
| Reports (summary, CSV, PDF) | **yes** - same aggregation rules (`reports/service.py`) | parallel generation, stored/idempotent reports |
| Sync, cross-device conflict handling | queue + retry | authoritative conflict detection |

## Backend model -> device SQLite mapping
Same table and column names. Differences: timestamps stored as ISO text; booleans as 0/1; `eligible_followup_categories` as `"|A|B|"` in both;
device-only `dirty` flags, `sync_outbox`, `sync_state`, `local_reports`; server-only `audit_log`, `reports`, `benchmark_cases`, `sync_operations`.
`households/visits/referrals.version` on the device = last server version seen (use as `base_version`).

## Validation rules (enforced server-side; 422 with `VALIDATION_ERROR` or the domain code shown)
| Resource | Rules |
|---|---|
| Household | `household_id` optional `^[A-Za-z0-9_-]{3,32}$`; `village_id`, `assigned_worker_id` `^[A-Za-z0-9_-]{2,32}$`; `household_member_count` 1-60; categories ⊂ ANC, IMMUNISATION, NUTRITION, HYPERTENSION, DIABETES, ROUTINE; `scheduled_followup_category` must be eligible (`CATEGORY_NOT_ELIGIBLE`); duplicate id → 409 `DUPLICATE_ID`; workers cannot create/reassign for others (403) |
| Visit | status ∈ PLANNED, COMPLETED, MISSED, RESCHEDULED, CANCELLED; COMPLETED needs `actual_visit_date` (`ACTUAL_DATE_REQUIRED`); optional `actual_visit_time` (time of day the worker went, local time as entered, `HH:MM`; returned as `HH:MM:SS`; only on COMPLETED, else `ACTUAL_TIME_NOT_ALLOWED`; no time zone stored), not in the future (`FUTURE_ACTUAL_DATE`); actual date only on COMPLETED (`ACTUAL_DATE_NOT_ALLOWED`); `next_followup_date` after the visit (`NEXT_DATE_ORDER`); `followup_required=false` with a date, or true without one on a COMPLETED visit → `FOLLOWUP_INCONSISTENT`; COMPLETED/CANCELLED visits cannot change status (409 `VISIT_FINAL`) |
| Referral create | visit must exist, belong to the household and be COMPLETED; facility must exist (`UNKNOWN_FACILITY`); initial status RECOMMENDED or PLANNED only; RECOMMENDED must not have `planned_visit_date`, PLANNED needs one on/after creation (`PLANNED_DATE_*`); creation date not in the future; an active referral for the same household+visit+service → 409 `DUPLICATE_REFERRAL` |
| Referral update | RECOMMENDED→PLANNED→ATTENDANCE_CONFIRMED only (`INVALID_TRANSITION`); confirmation requires role admin/hospital (403), `attendance_record_id` + `attendance_confirmation_date` between the planned date and today (`ATTENDANCE_RECORD_REQUIRED`, `CONFIRMATION_DATE_ORDER`); confirmed records are immutable and cannot be cancelled; only ACTIVE referrals can change |
| Report | `period_end >= period_start` (`BAD_PERIOD`); unknown `referral_ids` → 422 `UNKNOWN_REFERRAL`; workers get only their own data and can read only reports they created |
| Health QA | `question` 1-2000 chars after stripping control characters |
| Sync | ≤200 operations; `op_id` 8-64 chars `[A-Za-z0-9_.:-]`; `entity_type` household\|visit\|referral; `op_type` create\|update; update needs `base_version` (≥1, ≤ server version); malformed ops are rejected individually (`MALFORMED_OPERATION`) |

## Sync conflict behaviour (summary; full algorithm in FLUTTER_INTEGRATION_GUIDE.md)
| Situation | Server result |
|---|---|
| Same `op_id`/`idempotency_key` sent again | original result returned with `duplicate:true`; no second write |
| Update with current `base_version` | applied (domain rules still enforced; invalid → `REJECTED`) |
| Stale `base_version`, touches a **protected** field | `CONFLICT`, **not applied**, both values returned |
| Stale `base_version`, only unprotected fields | applied, `conflict.resolution = MERGED_UNPROTECTED_FIELDS`, overwritten values in `conflict.superseded` |
| Second device creates a referral for the same household+visit+service | stored as `record_state=DUPLICATE`, `warnings: DUPLICATE_FLAGGED:duplicate_of=...`; nothing deleted |
| Worker tries to set `ATTENDANCE_CONFIRMED` | `REJECTED` (needs hospital/admin) |
| Commit/DB failure while storing an op | `FAILED_RETRYABLE`, `acknowledged:false`, nothing stored; resend |
| Two identical pushes race | one wins; the other gets the winner's result with `duplicate:true` |

## Authentication requirements per endpoint
All `/api/v1/*` endpoints require `X-API-Key` when `AUTH_MODE=api_key`; `GET /health` is open. Role effects: worker = own records only;
admin/hospital = all records and may confirm attendance. `AUTH_MODE=disabled` is local development only and is refused with `APP_ENV=production`.
Production additionally refuses any retrieval status other than `VERIFIED`, and `DOCS_ENABLED=false` hides `/docs` and `/openapi.json`.
