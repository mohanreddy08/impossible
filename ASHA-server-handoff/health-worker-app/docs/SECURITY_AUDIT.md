# ASHA security audit and remediation

Scope: the Flutter app (`health-worker-app`), the FastAPI backend (`health-worker-backend`) and the offline data pack (`asha-data`).
All testing used synthetic data. Statements below are limited to what I read in the code or ran.

## A. Summary

The existing design was sounder than most prototypes: per-worker scoping on every route, idempotent sync with per-operation acknowledgement,
protected-field conflict handling, no DELETE routes, no CORS (so browsers are denied by default), API key in the platform keystore, no
cleartext traffic except the emulator/localhost, `allowBackup=false`, no request bodies or questions in logs, and a deterministic safety
engine ahead of any model.

The audit found **one High, three Medium and several Low/Informational** issues. The High one and the Medium ones that could be fixed
without changing the architecture are fixed and covered by tests. Four larger items need a decision or deployment work (section F).

## B. Findings

| ID | Severity | Finding | Status |
|---|---|---|---|
| S-01 | **High** | **Sync operation ids were not owned by the worker who sent them.** `synchronization/service.py` looked prior operations up by `op_id` / idempotency key only. If worker B sent an `op_id` that worker A had already used, B was answered with A's stored result (including A's conflict details: server and client field values) and **B's own data was discarded while B was told it was acknowledged**, so B's phone would drop the visit from its queue. A rejected-record from A could also be deleted by B. | **Fixed + tested** |
| S-02 | Medium | No request-size limit, no rate limit, no brute-force protection on API keys. | **Fixed + tested** |
| S-03 | Medium | The optional AI answer was relied on a prompt alone to avoid medicine names and doses. A model (or a rogue server) could return a dose and the phone would show it. | **Fixed on server and in the app + tested** |
| S-04 | Medium | Production could start with the public default `DEVICE_HASH_SALT`, with short API keys, and with `/docs` + `/openapi.json` published; `/health` advertised the auth mode. | **Fixed + tested** |
| S-05 | Medium | Release APK is signed with the **debug key** (`build.gradle.kts`). | **Fixed (needs your keystore)** |
| S-06 | Low | Failed authentication was not logged. | **Fixed + tested** (logs a short fingerprint, never the key) |
| S-07 | Low | No security response headers. | **Fixed + tested** |
| S-08 | Low | Dependencies with known advisories: `pypdf 5.1.0` (60), `starlette 0.41.3` (7), `fastapi 0.115.4`. | **Upgraded** to `pypdf 6.21.2`, `starlette 0.49.3`, `fastapi 0.128.8`; full suites re-run |
| S-09 | Low | Creating a visit/household with a client-chosen id that exists answers 409 `DUPLICATE_ID`, which tells a worker that the id exists. Ids are UUID-like, so guessing is impractical. | Not changed (documented) |
| S-10 | Info | `GET /health` and the demo Settings text mention the auth mode in development. | Production hides it |

### Details of the fixes

- **S-01** `app/services/synchronization/service.py`: every outcome row now stores its `owner`; `_owned_by()` is checked before a prior
  operation is returned or removed. A foreign id gets `REJECTED / OPERATION_ID_IN_USE` with no stored data. Older rows without an owner
  fall back to the installation hash. Admin/hospital roles are unaffected. No schema change, so no migration.
  Tests: `test_another_worker_cannot_reuse_or_read_my_operation_id` (failed before the fix: *"worker two was told its data is stored when
  it was silently discarded"*), `test_worker_cannot_clear_another_workers_rejected_operation_record`,
  `test_worker_cannot_create_or_update_visits_of_another_worker_through_sync`.
- **S-02** `app/core/hardening.py` (new, pure ASGI): 2 MB body cap (32 KB under `/health-qa`), declared and streamed size checked, 413;
  sliding-window rate limit per API key (or address) with `Retry-After`, 429; AI route limited to 12/min; wrong-key lockout per address
  (20/min by default) that also blocks a correct key from that address until the minute passes. Settings: `MAX_BODY_BYTES`,
  `RATE_LIMIT_PER_MINUTE`, `LLM_RATE_LIMIT_PER_MINUTE`, `FAILED_AUTH_PER_MINUTE`.
- **S-03** `app/services/llm/client.py::unsafe_output` and `lib/services/qa_service.dart::unsafeAiText`: doses, tablet counts, named
  medicines (English and Telugu words) withhold the answer (`LLM_UNSAFE_OUTPUT`, nothing cached on the phone); answers are cut at 1500
  characters. This is a deterministic check, not a clinical rule; it only ever removes text.
- **S-04** `app/main.py`: production refuses to start with the default/short salt or API keys under 24 characters; docs are off in
  production even if `DOCS_ENABLED=true`.
- **S-05** `android/app/build.gradle.kts`: uses `android/key.properties` when present (git-ignored), otherwise falls back to the debug key
  and prints a warning at build time. I did **not** create a keystore.

## C. New and changed tests

Backend (`app/tests/test_security_hardening.py`, 21 tests): operation-id ownership (3), oversized body, security headers, rate limit
(per-key isolation), failed-auth lockout, auth failure logging without the key, production guards (salt, short keys, docs/health), AI output
guard (6 unsafe, 3 safe, route-level withhold). Two older tests were adjusted for the new guards (a production-config test now supplies a salt
and a long key; the "every endpoint needs auth" probe disables the lockout it would otherwise trigger).
App (`test/ai_guard_test.dart`, 3 tests): unsafe text detection, unsafe answer not returned or cached, over-long answer cut.

## D. Test results (run by me)

| Check | Result |
|---|---|
| Backend, SQLite | **461 passed, 1 skipped** (the skipped one is PostgreSQL-only) |
| Backend, real PostgreSQL 16 | **462 passed** |
| `flutter analyze` | No issues |
| `flutter test` | **347 passed, 20 skipped** (the 20 need a live backend and were not run in this pass) |
| Release APK build | Built; prints the "debug key" warning because there is no keystore |
| `pip-audit` | 124 advisories before, **82 after**. Remaining: `pillow 11.3.0` (54) needs Python 3.10+, this environment is 3.9; `starlette 0.49.3` (5), `anyio`, `python-dotenv`, `urllib3`, and tooling (`pip`, `setuptools`, `pytest`). |
| Flutter dependency scan | **Not run** (no scanner configured; `flutter pub outdated` only lists versions, not advisories) |
| iOS | **Not built or tested** |

## E. Offline behaviour (verified earlier in this session on a physical phone, offline)

Visit saved offline showed "Saved on this phone", "1 waiting to sync" and "Not synced yet"; Ask, Visits, Households, Referrals, Reports,
Sync centre and Settings all opened offline; danger signs escalated offline. Telugu and English switching was checked in the UI.
**Not verified end to end on a device in this pass:** sync after reconnecting (that phone had no server configured), duplicate prevention and
conflicts on a device (covered by the backend and engine tests only), and anything on iOS.

## F. Remaining risks (not fixed here)

1. **The local database is not encrypted** (plain SQLite via `sqflite`). It holds pseudonymous ids, visit dates/status, referral state and
   member counts. It does **not** hold names, addresses or phone numbers (the household schema has none), and `allowBackup=false` is set,
   but a rooted phone or a lost unlocked phone exposes it. Fix: SQLCipher (`sqflite_sqlcipher`) with a key in the keystore plus a migration
   that re-opens the existing file; this changes the database layer and the test harness, so it needs its own change and device test.
2. **No user login.** The backend uses static API keys per role/worker: no expiry, no rotation, no per-user identity, no logout/revocation.
   Replace with your identity provider (OIDC) before real use. Rate limiting and lockout reduce but do not remove the risk.
3. **The "nearby SLM server" mode described in the brief does not exist in this codebase.** The online path is the backend route
   `/health-qa/llm` (an Anthropic API call from the server). There is no discovery of nearby servers, no server-identity pinning and no
   local SLM. If a nearby server is built: pin its certificate, authenticate the phone, and keep the output guard in section B.
4. **Rate limits and lockout are per process and in memory**: with more than one server process they are per process. Put a shared limiter
   or the platform's limiter in front.
5. **Debug signing key** until you provide `android/key.properties` (S-05).
6. **Screen capture / recents screenshots** are not blocked (`FLAG_SECURE` not set). I left it off because it also blocks the screen
   recording you use for demos; enable it for production builds if your policy needs it.
7. **Conflict policy for observations**: the app has no free-text clinical observations (no notes field), so there is nothing to merge;
   visit status uses the existing rule (stale changes to protected fields are held for review, never silently overwritten; a final visit
   cannot change status).
8. **Protocol content** is only as trustworthy as the server and TLS: the phone imports whatever the authenticated server marks approved.
   The sample data pack is marked `TEST_FIXTURE_ONLY`, never VERIFIED, and every danger-sign rule is a developer draft that needs clinical
   review.
9. Dependency advisories listed in section D remain until the server runs Python 3.10 or newer.

## G. Deployment checklist

- `APP_ENV=production`, `AUTH_MODE=api_key`, `DOCS_ENABLED=false`.
- `API_KEYS` with keys of at least 24 random characters; `DEVICE_HASH_SALT` a long random secret; `ANTHROPIC_API_KEY` only in the server
  environment, never in the app.
- HTTPS only (the Android build already refuses cleartext except to the emulator/localhost). Terminate TLS in front of the API.
- A managed PostgreSQL with encryption at rest, restricted network access, backups that are themselves encrypted.
- Python 3.10+ on the server, then `pip-audit` and upgrade `pillow`, `anyio`, `python-dotenv`, `starlette`.
- Provide `android/key.properties` and build the release APK with it; do not distribute a debug-signed APK.
- Keep request bodies and health text out of logs (already the case); route the `security` logger (failed authentication) to a restricted log.
- Review and approve the clinical rules and protocol content before any real use.
