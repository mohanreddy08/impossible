# Server and supervisor website: design and results

All data is synthetic. The server assists clinicians: no diagnosis, no medicine doses.

## 0. Starting point (run before any change)

```
H5_DATA=../h5-pack-data .venv/bin/python -m pytest -q -o addopts=""        ->  552 passed, 1 skipped in 79.86s
python -m h5.run --split dev ... ; evaluate.py ...                         ->  PRIMARY SCORE 0.9581
```

## 1. The phone's sync contract in 10 lines (unchanged)

1. `POST /api/v1/sync/push {installation_id, operations[≤200]}`; each op: `op_id`, optional `idempotency_key`, `entity_type` household|visit|referral, `entity_id` (client-chosen on create), `op_type` create|update, `base_version` (updates), `payload`.
2. One result per op: `status` ACKNOWLEDGED | REJECTED | CONFLICT | FAILED_RETRYABLE, `acknowledged` true **only after the commit**, `duplicate`, `server_version`, `conflict`, `warnings`.
3. The phone keeps an op in its outbox until `acknowledged: true`; any network error means "unknown, resend".
4. Resending an `op_id`/`idempotency_key` returns the original result with `duplicate: true` and writes nothing.
5. A rejected op changed nothing and may be resent (e.g. after its parent syncs).
6. A stale `base_version` touching protected fields is not applied (`CONFLICT` with both values); stale unprotected fields merge.
7. Duplicate referrals (same household+visit+service from two phones) are kept and flagged `DUPLICATE`.
8. `GET /api/v1/sync/pull?since=&entity_types=&limit=` returns changed records plus `server_time` for the next pull.
9. `X-API-Key` authenticates; `worker` keys see only their own `worker_id` (others' ids → 404); `installation_id` never goes in a URL.
10. `GET /health` is open; errors are always `{"error": {"code", "message", "details"}}`.

What the server work changed for phones: nothing in requests or responses. A key can now also be a **per-phone key** made on the website
(same `X-API-Key` header), and the server records last-seen/last-sync for it. Tested: `test_phone_app_contract_unchanged`, the original 552 tests.

## 2. Stack (one paragraph)

**Jinja2 server-rendered pages + a few small vanilla-JS files, served by the same FastAPI process.** One origin means one HTTPS address for
phones and supervisors through a tunnel, no CORS to open, cookies that can be `SameSite=Strict`, and no build step or Node toolchain on the
laptop that runs the server. Pages render from the same service functions as the JSON API (same role scoping), so they work on slow phones'
browsers and with JavaScript limited to the interactive parts (map, Ask, status changes, admin forms), which call the documented JSON API with
`fetch`. No inline scripts or styles, so the Content-Security-Policy forbids them. htmx/Alpine were not needed for this size of interaction;
React + Vite would add a build and a second origin for little gain here.

## 3. Schema changes (Alembic `0004`, SQLite and PostgreSQL)

The sync tables (`households`, `visits`, `referrals`, `sync_operations`, `audit_log`) are **unchanged**, so nothing new can leak into pull responses.

| Table | Purpose |
|---|---|
| `users` | website accounts: role admin/supervisor/asha, ASHA's `worker_id`, **argon2id** hash, `token_version` (ends sessions), lockout counters, language |
| `phone_keys` | per-phone API keys: public `key_id`, **SHA-256 of the key** (256-bit random key, shown once), worker, revoked_at/by, last seen/sync, op counters, User-Agent |
| `admin_audit` | sign-ins, lockouts, account and key changes, settings, **every export**, **every phone-number reveal**, escalation handling. No secrets, no numbers, no health text |
| `app_settings` | retention days, pinned public URL, default language |
| `villages`, `ashas` | Chandrapuri block (6 villages with the GENERATED map, 5 ASHAs) + the phone demo set's villages/workers |
| `household_profiles` | house no., head, generated map position, **synthetic** phone number (+91 5xxxx range, not allocated to mobiles) |
| `members` | the 2,234 people; `register` = the pack's row exactly (input to the VIS rules) |
| `qa_audit` | per question: outcome ESCALATED/REFUSED/ANSWERED, cited section ids, rule ids, time, actor, channel; escalation status/handler/note code. **Never the question text** |

Seed: `scripts/seed.py` loads the block (500 households, 2,234 people) and the phone demo sync set (500 `HH-SYN-*` households, so a phone in demo
mode syncs), plus accounts. Map positions come from `h5.export_assets.village_layout`, the generator of the phone's maps (equality tested).

## 4. API added (all under `/api/v1`, documented at `/docs` in development)

| Method + path | Who | What |
|---|---|---|
| `POST /auth/login` | open (rate-limited, lockout) | sets HttpOnly SameSite=Strict session cookie (JWT HS256, 30 min, renewed while active), also returns the token |
| `POST /auth/logout`, `GET /auth/me` | signed in | logout ends all sessions of the user |
| `GET/POST /admin/users`, `PATCH /admin/users/{id}` | admin | accounts; deactivate/role/password change ends sessions; last admin protected |
| `GET/POST /admin/phones`, `POST /admin/phones/{key_id}/revoke` | admin | phone keys (shown once) |
| `GET /admin/audit` | admin | admin-action audit |
| `GET /admin/server-info`, `PATCH /admin/settings` | supervisor / admin | public URL (+ source, live check through the tunnel, QR SVG), retention, language |
| `GET /dashboard/overview` | all roles (scoped) | due today / overdue / upcoming, open referrals, priority-1 list, escalations 7 d, phones stale > 48 h |
| `GET /dashboard/households` | scoped | filters village, ASHA, status, urgency, VIS priority, search; `limit/offset` |
| `GET /dashboard/households/{id}` | scoped | members, due items, register history, synced visits, referrals, masked phone |
| `POST /dashboard/households/{id}/reveal-phone` | scoped | full (synthetic) number; audit-logged |
| `GET /dashboard/visit-list?worker_id&date` | scoped | h5 VIS rules, grouped priority 1/2/3 |
| `GET /dashboard/map/{village_id}` | scoped | generated streets, places, houses with urgency (red/orange/blue/green + shape) |
| `GET /dashboard/referrals`, `GET/PATCH /dashboard/escalations[/{id}]` | scoped / supervisor | feeds; who handled what. Referral status changes use the existing `PATCH /referrals/{id}` |
| `GET /dashboard/qa-audit`, `/sync-status`, `/ashas`, `/villages`, `/village-summaries`, `/reports/summary` | scoped | summaries and charts' numbers |
| `GET /dashboard/reports/export?kind&format` | supervisor/admin | CSV/PDF: visit-list, households, referrals, qa-audit, summary (PDF). Audit-logged, no phone numbers |
| `POST /ask` | any signed-in user or key | h5 engine: `answer_text`, `cited_section_ids`, `citations`, `escalate`, `refused`, `outcome`, disclaimer |

Roles: **admin** everything; **supervisor** (ANM / MO) the whole block, status changes, exports, reveals, Ask; **asha** only her own
`worker_id` (other ids → 404/403). Website pages always need a signed-in user, even with `AUTH_MODE=disabled`.

Security controls: argon2id passwords (min 10 chars, rehash on login), JWT with server-side `token_version`, lockout after 5 wrong passwords
(15 min), failed-sign-in and failed-key rate limits per address, general rate limit per key/address, body-size limits, CORS closed unless
`SITE_ORIGIN` is set (then only that origin), CSRF guard (cookie-authenticated writes need `X-Requested-With: fetch`; form posts check
`Origin`), CSP `script-src 'self'` with no inline code, `X-Frame-Options: DENY`, HSTS behind https, `Secure` cookies behind https,
production refuses to start with default `SECRET_KEY`/salt or auth disabled. Question text and request bodies are never logged.

## 5. Results (all run on the build machine; exact commands)

| Check | Command | Result |
|---|---|---|
| API test suite | `H5_DATA=../h5-pack-data .venv/bin/python -m pytest -q -o addopts=""` | **594 passed, 1 skipped** (552 original + 42 new) |
| `/ask` parity | part of the suite: `test_ask_parity.py` | all **240** golden questions: same answer text, citations, escalate, refused as `h5.pipeline` and `golden.json` |
| Visit list parity | `test_web_api.py::test_visit_list_equals_python_engine_golden` | all **346** golden rows (member, item, priority, status, date) |
| PostgreSQL 16 | `TEST_DB=postgres pytest app/tests/test_database.py app/tests/test_migrations.py app/tests/test_sync.py` | **80 passed** (incl. migration 0004 upgrade/downgrade, no drift) |
| Lint / types | `ruff check .` ; `mypy` | all checks passed; no issues in 37 files |
| Browser e2e | `scripts/e2e.sh` (SQLite) and the same tests against `docker compose` (PostgreSQL) | **7/7** both times: login, visit list, map tap → household, phone reveal, Ask (refer/refuse/answer), escalation feed, Telugu |
| Tunnel scripts | `scripts/test_tunnel_scripts.sh` | passed: start, address parsing, `/health` over HTTPS, phone push + duplicate retry, dashboard sees it, Secure cookie, stop |
| Docker | `docker build .` ; `docker compose up` | image builds; PostgreSQL + migrations + seed + 2 workers healthy; restart does not re-seed |
| h5 dev score | `python -m h5.run --split dev` + `evaluate.py` | **0.9581** (unchanged) |

**Load test** (`scripts/load_test.py --phones 50 --rounds 5`): 50 phones, each with its own key, all push 5 operations and pull at the same
instant, 5 times; round 2 re-sends round 1 (offline-retry case). 500 requests, 1,250 operations.

| Server | push p95 | pull p95 | all p95 | errors | stored |
|---|---|---|---|---|---|
| SQLite, 1 process (fresh DB, 2 runs) | 7.7 s / 8.4 s | 2.5 s / 3.5 s | **5.9 s / 7.0 s** | 0 | 250 households, each exactly once |
| PostgreSQL 16, 4 workers | 4.3 s | 2.5 s | **3.8 s** | 0 | 250 households, each exactly once |

Unloaded: one push ≈ 6 ms, one pull ≈ 45 ms. Under the burst the single process is CPU-bound (pulls of up to 600 records each). Found and
fixed during load testing: SQLite writers failed at once with "database is locked" (stale read snapshot); sync pushes are now serialized
in-process on SQLite after releasing their pooled connection (an earlier attempt with `BEGIN IMMEDIATE` deadlocked against FastAPI's thread pool).

## 6. Not verified

- Real Cloudflare tunnel and Render: the build machine cannot reach Cloudflare's edge or Render (DNS/egress policy). The scripts were tested
  against a local stand-in tunnel serving real HTTPS; `render.yaml` is unvalidated against Render.
- `start_public.ps1` / `stop_public.ps1`: written for Windows PowerShell, **not run** (no PowerShell on the build machine).
- macOS-specific parts of `start_public.sh` (`caffeinate`): written for bash 3.2, run on Linux bash only.
- No real phone was used. The phone side of sync was exercised with the app's exact wire format (`test_phone_app_contract_unchanged` and the load test), not the Flutter app.
- Accessibility: keyboard paths (map houses, row links, forms) are covered by the e2e tests; colour contrast was chosen for WCAG AA but not measured with an audit tool; no screen-reader session.
