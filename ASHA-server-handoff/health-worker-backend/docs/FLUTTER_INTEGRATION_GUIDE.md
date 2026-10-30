# Backend integration guide for the Flutter developer

Audience: whoever builds the Flutter app later. Nothing here requires the UI design. Machine-readable contract: [`openapi.json`](openapi.json)
(generate a Dart client from it if you like). Real captured request/response pairs: [`api_examples.json`](api_examples.json).
Local database: [`mobile_sqlite_schema.sql`](mobile_sqlite_schema.sql). Details/rules: [`API_CONTRACT.md`](API_CONTRACT.md).

> All records are SYNTHETIC. Protocol content is **not yet available** (official documents arrive only if the team qualifies for Round 2), the
> danger-sign rules are **not clinically validated**, and every protocol question currently returns `INSUFFICIENT_EVIDENCE`. Build the UI so that
> state is normal and clearly explained.

## 1. The golden rule: the phone must work with no server
| Feature | Where it runs | Why |
|---|---|---|
| Danger-sign check / escalation | **On device** (port `app/services/safety/engine.py` + `rules/danger_rules.json`) | must never wait for a network call |
| Protocol Q&A | **On device** (bundled passages + SQLite FTS5, same algorithm as `protocol_retrieval/service.py`) | rural connectivity |
| Households, visits, follow-up list, visit outcomes | **On device** (SQLite; recompute rules from `visits/service.py::recompute_household`) | daily work |
| Referral recording | **On device** (RECOMMENDED/PLANNED) | hospital confirmation arrives later from the server |
| Hospital summary + CSV/PDF | **On device** (aggregation rules in `reports/service.py`) | must not depend on server |
| Sync, cross-device conflict detection, stored reports | Server (optional) | convenience / system of record |

The API is for *sync and backup*. Never block a screen on an API call.

## 2. Authentication and identity
- Send `X-API-Key: <key>` on every call when the server runs with `AUTH_MODE=api_key` (401 `UNAUTHORIZED` otherwise). Keys are provisioned by the server operator; store on device in the platform secure storage.
- A *worker* key sees only that worker's households/visits/referrals/reports (cross-worker ids return `404`, explicit foreign `worker_id` filters return `403`).
  Only `admin`/`hospital` keys can confirm hospital attendance.
- `installation_id`: generate a random UUID once per app install and keep it. Send it in the body of `POST /sync/push` and in the **`X-Installation-Id` header** for
  `GET /sync/status`. **Never put it in a URL.** The server stores only a salted SHA-256 of it.

## 3. Conventions
Dates `YYYY-MM-DD`; timestamps ISO-8601 (server returns UTC `...Z`, accepts offsets such as `+05:30`). Lists: `?limit=` (1-200) `&offset=` → `{"items":[...],"total":N,"limit":L,"offset":O}`.
Every error: `{"error":{"code":"...","message":"...","details":null|[...]}}`. Unknown request fields are rejected (422) - send exactly the documented fields.

## 4. Health Q&A (online-or-offline logic; this shows the server's shape so the on-device result can match)
`POST /api/v1/health-qa/query` `{"question":"..."}` →
```json
{"query_id":"3653af5ebb504422","outcome":"ESCALATION_REQUIRED","original_question":"...","message":"Possible danger sign detected. Follow your approved escalation protocol ... [PLACEHOLDER TEXT - pending clinical approval]",
 "answer_text":null,"citations":[],"retrieval_status":null,
 "safety":{"status":"ESCALATION_REQUIRED","rule_ids":["DSR-BLEEDING-SEVERE"],"reasons":["Heavy bleeding phrase matched (current)"],
           "ruleset_version":"0.1.0-draft","ruleset_review_status":"DRAFT_UNREVIEWED_NOT_CLINICALLY_APPROVED","clinically_validated":false,"needs_human_review":false}}
```
`outcome` ∈ `ANSWERED_WITH_EVIDENCE | ESCALATION_REQUIRED | CLARIFICATION_REQUIRED | OUT_OF_SCOPE | INSUFFICIENT_EVIDENCE`.
UI rules: render ESCALATION first and prominently; only show `answer_text` when `outcome == ANSWERED_WITH_EVIDENCE`, always with every `citations[]` entry
(document title, section heading, page, version) and a visible "source verification: `<status>`"; show `message` for all other outcomes; always surface `clinically_validated:false`
while it is false. Never generate your own medical text.

## 5. Households, visits, follow-ups
- `GET /households` (filters `q, village_id, worker_id, status, category, due_before`), `GET/PATCH /households/{id}`, `POST /households`.
- `GET /follow-ups?bucket=OVERDUE|DUE_TODAY|UPCOMING&as_of=` returns planned visits with an `explanation` string you can show as "why is this on my list". Example item:
```json
{"visit_id":"VIS-SYN-000123","household_id":"HH-SYN-00042","worker_id":"WRK-SYN-003","category":"ROUTINE","scheduled_date":"2026-10-13","bucket":"DUE_TODAY","days_overdue":0,
 "explanation":"Planned ROUTINE visit scheduled for 2026-10-13 is due today as of 2026-10-13. Last completed visit: 2026-09-12."}
```
- Record an outcome: `PATCH /visits/{id}` `{"visit_status":"COMPLETED","actual_visit_date":"2026-10-13","followup_required":true,"next_followup_date":"2026-11-12"}` - the server
  creates the next PLANNED visit and recomputes the household (`last_visit_date`, `next_visit_due_date`, `record_status`). Do the same locally; the rules are in section 8.

## 6. Referrals - three different states, never conflate them
| `referral_status` | Meaning | `attendance_confirmed` | Show to the user as (`status_label`) |
|---|---|---|---|
| `RECOMMENDED` | worker advised a hospital visit | false | "Referral recommended - not yet planned, attendance NOT confirmed" |
| `PLANNED` | a visit date is set | false | "Referral planned - attendance NOT confirmed" |
| `ATTENDANCE_CONFIRMED` | a **hospital attendance record** exists | true (+ `attendance_record_id`, date) | "Hospital attendance confirmed by hospital record" |

Household visits are never hospital attendance. Workers cannot set `ATTENDANCE_CONFIRMED` (server returns 403/REJECTED); it arrives via sync pull. Other `record_state` values:
`CANCELLED`, `INVALID`, `DUPLICATE` - hide or grey them out; they are excluded from report counts. Use the server-provided `status_label` verbatim (or replicate `referral_label`).

## 7. Offline sync - the algorithm to implement
Local table `sync_outbox` (see schema). **Every local write = update the local row + insert an outbox op in ONE SQLite transaction.**
```
op = { op_id: uuid, idempotency_key?: uuid, entity_type: household|visit|referral, entity_id,
       op_type: create|update, base_version: <server version you last saw; REQUIRED for update>,
       client_created_at, client_updated_at, payload: {only the changed fields} }
```
Loop whenever online (and on a timer / app resume):
1. `POST /sync/push` `{installation_id, operations:[<=200 oldest pending ops, in creation order, parents before children>]}`.
2. For each result:
   | `status` / `acknowledged` | Meaning | You must |
   |---|---|---|
   | `ACKNOWLEDGED` / true | committed on server (`server_version` returned) | delete the op; set the local row's `version = server_version`, `dirty=0` |
   | `ACKNOWLEDGED` / true + `duplicate:true` | you resent an op the server already had | same as above (it is safe) |
   | `ACKNOWLEDGED` + `warnings:["DUPLICATE_FLAGGED:duplicate_of=REF-..."]` | referral stored but flagged as duplicate | keep it, show as duplicate |
   | `CONFLICT` / false | stale update touched protected fields; **server did NOT apply it** | keep the op + local edit; show `conflict.server_values` vs `conflict.client_values`; after the user decides, send a **new op** with `base_version = conflict.server_version` |
   | `REJECTED` / false | invalid (`error_code`, `error_message`) or parent missing | keep local data; fix and resend (same `op_id` may be resent after the cause is fixed, e.g. parent record now synced) |
   | `FAILED_RETRYABLE` / false | server could not store it (DB/commit problem) | keep the op; retry with backoff (resend same `op_id`) |
   | request failed / timeout / no response | **unknown** | treat every op in the batch as still pending; resend the same batch (idempotent) |
3. **Only `acknowledged == true` means synced. Never show "synced" for anything else, and never delete a local record or outbox op before that.**
4. `GET /sync/pull?since=<last server_time>&entity_types=household,visit,referral&limit=` → apply records newer than yours; skip any record that has a pending local op (resolve via conflict flow);
   store the returned `server_time` as the next `since`. Unrequested entity groups come back `null`.
5. Backoff: 2s, 4s, 8s ... max 5 min, jitter. Batch ≤ 200 ops.

Stale-write rules (so your UI can predict conflicts). Protected fields - referral: `referral_status, planned_visit_date, attendance_*, record_state, facility_id`; visit:
`visit_status, actual_visit_date, followup_required, next_followup_date, referral_*`; household: `assigned_worker_id, next_visit_due_date, last_visit_date, scheduled_followup_category, record_status`.
An update with `base_version` older than the server's that touches any of them → `CONFLICT`. Updates touching only other fields are merged and returned with
`conflict.resolution == "MERGED_UNPROTECTED_FIELDS"` and `conflict.superseded` (the values you overwrote) - show them if useful.
Real conflict example (captured): see "Sync push: stale update of a protected field" in `api_examples.json`.

## 8. Rules to replicate on the device
- **Household recompute** (`visits/service.py`): `last_visit_date` = max actual date of COMPLETED visits; `next_visit_due_date` = earliest scheduled date of PLANNED visits (its `visit_reason` becomes
  `scheduled_followup_category`); `record_status` = OVERDUE (<today) / DUE_TODAY / UPCOMING (>today) if a planned visit exists, else COMPLETED if last visit ≤ 14 days ago (a *synthetic-dataset convention, not clinical*) else NO_VISIT_DUE.
- **Follow-up list** = PLANNED visits bucketed against today. No clinical timing rules are applied (none are supplied).
- **Report** (`reports/service.py::aggregate`): include a referral only if facility matches, `referral_created_date` is within the period, `record_state == ACTIVE`, and its id has not been counted already; count by *current* status;
  categories sum equals the status sum. Freshness: ≤24h FRESH, ≤72h RECENT, else STALE_OFFLINE since `last_sync_at` (project policy). Show `generated_at`, `data_as_of`, `last_sync_at`, the privacy notice,
  and that these are recorded referrals - **not** predicted arrivals.
- Report endpoints for parity/backup: `POST /reports/summary` (idempotent), `GET /reports/{id}?format=json|csv|pdf`.

## 9. Error handling cheat-sheet
`401 UNAUTHORIZED` → re-provision key; `403 FORBIDDEN`; `404 NOT_FOUND` (also for other workers' records); `409 VERSION_CONFLICT | DUPLICATE_ID | DUPLICATE_REFERRAL | INVALID_TRANSITION | VISIT_FINAL`;
`422 VALIDATION_ERROR` (`details[]` = `{loc,message,type}`) or a domain code (`ACTUAL_DATE_REQUIRED`, `PLANNED_DATE_REQUIRED`, `ATTENDANCE_RECORD_REQUIRED`, ...); `500 INTERNAL_ERROR` (retry later).
Network errors on writes mean "unknown" - use the outbox, never assume failure or success.

## 10. What is intentionally NOT in the backend
No Flutter code, no UI. No file-upload endpoints (protocol documents are imported by an operator CLI). No hospital-arrival prediction. No clinical rules beyond the unvalidated draft lexicon.
