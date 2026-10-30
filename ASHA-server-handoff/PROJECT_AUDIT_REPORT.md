# Project Audit Report — Frontline Health-Worker Companion ("ASHA")

Audit date: 2026-10-14. Audited by reading the actual code and by running the test suites, analyzer and builds during this audit.
**This audit changed no source files.** Only this report was created. (Builds write to `build/`, test runs wrote logs to `/tmp`.)

Legend used throughout:
- **VERIFIED-RUN** = I ran it during this audit and observed the result.
- **VERIFIED-DEVICE** = I saw it work on a real device/emulator during this project (earlier in this session; not re-run for the audit).
- **CODE-ONLY** = exists in code, covered by no run I can cite.
- **NOT MEASURED / NOT TESTED / NOT VERIFIED** = exactly that. No numbers were invented.

---

## 0. Findings that matter most (read this first)

1. **None of the health-worker work is committed to git.** `git status` shows `health-worker-app/`, `health-worker-backend/`, `health-worker-datasets/` and `.env.example` as **untracked** (`??`). The only commits in this repository belong to a different project (the chicken-delivery website). One disk failure or `git clean` loses everything. *(P0)*
2. **There are no approved medical protocols anywhere in the project**, so the "answer a health question with citations" feature has never produced a real answer. `health-worker-datasets/protocol_passages.jsonl` and `retrieval_evaluation.jsonl` are **0 bytes**; all 200 questions in `health_questions_200.jsonl` have `expected_answer = null`. The citation UI and retrieval engine are tested only with fixture text.
3. **The danger-sign rules and all alert wording are drafts** (`DRAFT_UNREVIEWED_NOT_CLINICALLY_APPROVED`, messages end in `[PLACEHOLDER TEXT - pending clinical approval]`). The 100 % match I measured (section D) is against labels written for the same synthetic vocabulary, so it proves consistency, **not clinical safety**.
4. **There is no login.** The backend authenticates with a static `X-API-Key`; the app has a Settings field for the key. Anyone holding an admin key on a phone sees every worker's households (I did exactly this during testing).
5. **iOS has never been built, and there is a likely iOS crash path** (notification plugin initialised with Android settings only — section 6).
6. **The release APK is signed with the debug key**, and the Android application ID is still `in.healthcompanion.health_companion` while the app is now named ASHA.
7. The **reference UI image is not in the repository**, so I could not compare the UI against it. `lib/core/theme/tokens.dart` says the design tokens were taken from it; that cannot be checked.

---

## A. Project structure (actual)

The repository root (`protein-cuts---fresh-raw-chicken-delivery/`) is **another project** (a chicken-delivery website: `src/`, `frontend/`, `backend/`, `server.ts`, `package.json`, `render.yaml`, `supabase-schema.sql`, …). It is unrelated to the health app. The health-worker project is three untracked sibling folders:

```
health-worker-backend/            FastAPI server (optional, for sync/reports/protocols)
  app/
    main.py, domain.py
    api/deps.py, api/v1/{households,visits,referrals,reports,sync,protocols,health_qa,router}.py
    core/{config,security,principal,errors}.py
    db/{base,session}.py, db/models/{household,visit,referral,report,sync,protocol,benchmark}.py
    schemas/{api,common,domain}.py
    services/
      households/  visits/  referrals/  reports/ (service, export CSV/PDF)
      safety/ (engine.py, evaluation.py, rules/danger_rules.json)
      health_qa/orchestrator.py
      protocol_import/ (extract, sections, importer, approval)
      protocol_retrieval/ (service, cache, evaluation)
      synchronization/service.py
      dataset_import/
    tests/ 13 test files (2,113 lines)
  alembic/versions/0001_initial_schema.py, 0002_protocol_provenance_passage_dedupe_.py
  scripts/ import_datasets, import_protocols, evaluate_{safety,qa,retrieval}, run_tests, export_openapi, ...
  docs/ API_CONTRACT, FLUTTER_INTEGRATION_GUIDE, PROTOCOL_ARRIVAL_CHECKLIST, VALIDATION_REPORT, openapi.json, mobile_sqlite_schema.sql, junit*.xml, test_report.json
  3,130 lines of application Python (excluding tests)

health-worker-app/                Flutter app (package name health_companion, shown as "ASHA")
  lib/main.dart, app.dart
  lib/core/{clock, theme/{tokens,app_theme}}.dart
  lib/data/{api/{api_client,api_models,api_exceptions}, local/{database,local_store}, models/*}.dart
  lib/domain/{rules/{visit,priority,report}_rules, safety/safety_engine, retrieval/local_retrieval}.dart
  lib/services/{sync_engine, field_work_service, qa_service, record_answers, protocol_library, report_service,
                voice_input, alert_notifier, urgent_alerts, priority_service, settings, demo_data, data_bus}.dart
  lib/state/{app_services, sync_controller, connectivity_controller}.dart
  lib/presentation/{app_shell, format, error_text}.dart
  lib/presentation/screens/ ask, home, households(+detail), more, planner, priority, referrals, reports, settings, sync, visit
  lib/presentation/widgets/ choice_tile, common, header_scaffold, paged_list, pill_nav, priority_card, reveal, status_chip
  lib/l10n/ app_en.arb, app_te.arb (+ generated)         lib/sync/ and lib/data/repositories/ are EMPTY directories
  assets/safety/danger_rules.json, assets/demo/demo_seed.json
  android/ (custom launcher icon + teal launch screen), ios/ (never built)
  test/ 15 files + test/integration/real_backend_test.dart + integration_test/perf_test.dart (6,733 test lines)
  tool/ gen_arb.py, make_demo_seed.py, run_backend_integration.sh
  docs/ BUILD, PERFORMANCE, TEST_REPORT, BACKEND_GAPS         11,316 lines of app Dart (excluding generated l10n)

health-worker-datasets/           SYNTHETIC data only
  household_register_500.csv, visit_history.csv (2,032 rows), referral_records.csv (268 rows)
  danger_sign_tests.jsonl (142), health_questions_200.jsonl (200: 70 Telugu, 60 English, 50 code-mixed, 20 transliterated)
  hospital_report_tests.jsonl, offline_sync_tests.jsonl
  protocol_passages.jsonl  = 0 BYTES      retrieval_evaluation.jsonl = 0 BYTES
  generate.py, validate.py, dataset_validation_report.json
```

Environment: Flutter 3.47.7 (stable), macOS with **Command Line Tools only (no Xcode)**, backend venv present, `pgserver` installed (real PostgreSQL 16 for tests).

---

## B. What exists and what I verified (this audit)

| Check | Command | Observed result |
|---|---|---|
| Backend tests, SQLite | `pytest` (no DB env) | **426 passed, 1 skipped, 11.13 s** (skipped = the PostgreSQL-only migration test) — VERIFIED-RUN |
| Backend tests, real PostgreSQL 16 (pgserver) | `TEST_DB=postgres pytest` | **427 passed, 23.92 s** — VERIFIED-RUN |
| Flutter static analysis | `flutter analyze` | **No issues found** — VERIFIED-RUN |
| Flutter tests | `flutter test` | **252 passed, 20 skipped, 0 failed** (the 20 skipped need a live backend) — VERIFIED-RUN |
| Flutter ↔ real backend | `tool/run_backend_integration.sh` (temp SQLite DB, API-key auth, loaded with the synthetic datasets) | **20 passed** — VERIFIED-RUN |
| Android debug build | `flutter build apk --debug` | Succeeded; `app-debug.apk` = 197,427,848 bytes (incremental build, 10 s) — VERIFIED-RUN |
| Android release build | `flutter build apk --release` | Succeeded; `app-release.apk` = **59,542,868 bytes** (universal / all CPU types, ~56.8 MiB) — VERIFIED-RUN |
| Per-CPU release APKs (earlier build, 13 Oct) | files in `build/` | arm64 20,144,505 · armv7 17,782,597 · x86_64 21,628,277 bytes — file sizes read, not rebuilt |
| iOS build | `xcodebuild -version` | **Fails: "requires Xcode, active developer directory is Command Line Tools"** → iOS **NOT BUILT, NOT TESTED** |
| Safety rules vs synthetic labels | evaluated in-process (script not run because it writes into the repo) | 142/142 exact status match; 48/48 escalations detected; 0 false negatives, 0 false positives — **synthetic, self-written labels; not clinical evidence** |

Real-device measurements (vivo V2141, Android 14, 5.6 GB RAM, **release** build, measured today):

| Metric | Value |
|---|---|
| Cold start (`am start -W`, 3 runs) | 647 / 541 / 532 ms |
| Memory (PSS) a few seconds after launch, Home with 80 households | 129,195 KB (RSS 211,188 KB). Single sample. |
| Installed APK | 59,542,868 bytes (universal build) |
| Scroll smoothness | measured in **profile** build with Flutter's frame timeline: every page's worst frame ≤ 16 ms build on the first run; a second run on a fresh install had 14–19 slow-build frames per page (worst 23–40 ms). See `docs/PERFORMANCE.md`. The debug build on the phone was visibly laggy (expected). |
| Sync over a *simulated* slow link (about 20 KB/s, local proxy — not a real 2G/4G network) | full first sync ≈ 29 s uncompressed vs ≈ 2 s with the gzip I added |
| **NOT MEASURED** | installed size on disk after install, battery use, long-session memory growth, release-mode frame timing, Q&A answer latency on a real network, any measurement on a low-end (≤ 2 GB RAM) phone, any iOS metric |

Observed working on real devices during this project (not re-run for the audit): app installs and runs on the vivo phone and an arm64 emulator; sync with the real backend; offline visit saved and later synced automatically; danger-sign card works in airplane mode; urgent notification appears online and offline; Telugu UI renders correctly; English and Telugu voice dictation on the emulator (needs internet); the Village filter and list scrolling.

---

## C. Screen-by-screen status (your 20 categories)

"Local" = reads/writes the phone's SQLite. "Backend" = talks to the FastAPI server. All screens use **real data paths, not mock data** (the "demo data" is a synthetic seed loaded into the *same* local database).

| # | Screen / state | File(s) | Status | Local | Backend | Works offline | Tested |
|---|---|---|---|---|---|---|---|
| 1 | Splash / app initialisation | `lib/main.dart`; Android launch theme `res/drawable/launch_background.xml` | **No in-app splash screen.** A teal native launch screen shows while the engine starts; `main()` opens the DB and loads rules. | Yes | No | Yes | Not as a screen. Cold start measured (above). |
| 2 | Login / authentication | — | **MISSING.** Backend has only static API keys (`docs/BACKEND_GAPS.md` #3). The app has Server address + Access key fields in Settings; a 401 shows a banner. | — | Key sent as `X-API-Key`, stored in secure storage | n/a | Key handling tested; there is no login flow to test |
| 3 | Home dashboard | `screens/home_screen.dart` | Complete: next-visit card, 4 counts, "Attend first" list, quick actions, greeting | Yes | No | Yes | Widget + accessibility + Telugu tests; VERIFIED-DEVICE |
| 4 | Ask a health question | `screens/ask_screen.dart`, `services/qa_service.dart`, `record_answers.dart` | Complete as UI. Order: validate → on-phone safety → answers from the worker's own records → on-phone approved protocols → server → "cannot verify". Voice input. | Yes (safety, records answers); medical answers **only if approved protocols are on the phone — none are** | Optional server `/health-qa/query`,`/retrieve` | Danger-sign + records questions: yes. Medical knowledge: **no content exists** | Widget tests; VERIFIED-DEVICE for danger sign and records answers |
| 5 | Answer details with citations | `_Evidence` in `ask_screen.dart` | UI complete (document, section, page, version, status, exact passage, verified/unverified styling) | Yes | Optional | Only with approved local text | Tested **with fixture passages only**. **Never seen with a real approved protocol.** |
| 6 | Safety alert & escalation | `_Escalation`, `domain/safety/safety_engine.dart`, `assets/safety/danger_rules.json` | Complete. Danger sign is never answered/reassured; shows urgent card, call-supervisor button (needs a number), approved local text if any, else "no approved protocol loaded". Dart engine = port of the backend engine. | Yes | No (server never asked) | Yes | `safety_parity_test` (Dart vs backend rules) + UI tests; VERIFIED-DEVICE offline. **Wording is placeholder; rules unreviewed.** |
| 7 | Household register | `screens/households_screen.dart` | List, search, status/category/village filters, paging (30/page). **No add/edit household** (backend has `POST/PATCH /households`; the app never calls them). | Yes | Via sync only | Yes | Tests + VERIFIED-DEVICE (500 households on emulator) |
| 8 | Household details | `HouseholdDetailScreen` (same file) | Status, next/last visit, referrals, visit history, "schedule visit" | Yes | Via sync | Yes | Tests |
| 9 | Daily visit planner | `screens/planner_screen.dart`, `domain/rules/visit_rules.dart` | Overdue / Today / Upcoming tabs, ordered by date, reason shown | Yes | Via sync | Yes | Tests |
| 10 | Visit details & completion | `screens/visit_screen.dart`, `services/field_work_service.dart` | Done / could-not-visit / cancel, date, follow-up, optional referral recommendation, validation. **No free-text notes** (backend has no notes field). | Yes (outbox) | Via sync | Yes | Tests; VERIFIED-DEVICE (saved offline, synced later) |
| 11 | Referral list | `screens/referrals_screen.dart` | Filterable list with plain-language phase | Yes | Via sync | Yes | Tests |
| 12 | Referral details & status updates | same file | Details sheet with steps; actions limited to **plan visit** and **cancel**. "Attendance confirmed" can only come from a hospital record, by design. No other status editing. | Yes | Via sync | Yes | Tests. **Not exercised on a real device** during this project. |
| 13 | Hospital reports & export/share | `screens/reports_screen.dart`, `services/report_service.dart` | On-phone summary + CSV share; server report (JSON/CSV/PDF) needs internet | Summary: yes | `POST /reports/summary`, `GET /reports/{id}` | Summary yes; server report no | Tests with a fake server and fake share sheet. **Android share sheet never exercised on a device.** |
| 14 | Offline mode indicator | `widgets/status_chip.dart` | Online / Offline / server-unreachable + pending count. Reflects "a connection exists", not signal quality. | — | — | Yes | Tests; VERIFIED-DEVICE |
| 15 | Pending sync queue | `screens/sync_screen.dart` | Counts + list of waiting/rejected/needs-decision/confirmed items | Yes | Push/pull | Yes | Tests; VERIFIED-DEVICE |
| 16 | Sync errors & conflict resolution | `sync_screen.dart` (`keep-mine` / `keep-server`), `services/sync_engine.dart` | Implemented: retry, idempotent resend, per-op acknowledgement, conflict dialog, duplicate-referral flag, login-change reset | Yes | Yes | Queues offline | 23 engine tests + 20 real-backend tests. **A real conflict was never triggered on a device.** |
| 17 | Telugu / English | `settings_screen.dart`, `lib/l10n/*.arb` (363 strings) | Complete switch; every screen, dialog, error and the danger-sign card translated | Yes | — | Yes | `telugu_complete_test` (31 tests scan for leftover English); VERIFIED-DEVICE Home/Ask/Settings. **Telugu is a developer draft; no native review.** |
| 18 | App settings / server config | `screens/settings_screen.dart` | Language, server address, key, test connection, urgent-alerts switch, supervisor number, protocol download, demo data, clear data, diagnostics | Yes | `/health`, `/protocols` | Mostly | Tests; VERIFIED-DEVICE |
| 19 | Loading / empty / error / retry states | `widgets/common.dart` (`LoadingView`, `EmptyState`, `ErrorState`) | Present on all list screens (23 usages); retry buttons in only 3 places (some errors have no retry) | — | — | Yes | Partly tested (Telugu leak test visits several error states) |
| 20 | First-launch permissions & onboarding | — | **No onboarding.** Microphone permission is requested by the system when you first tap Speak; notification permission is requested at app start (Android 13+). No first-run language choice or explanation. | — | — | — | Permission flow VERIFIED-DEVICE on the emulator |

Extra screens that exist but were not in your list: **Attend first (priority list)**, **More** menu.

---

## D. Backend feature status

All 25 routes (from the running app): `GET/POST /api/v1/households`, `GET/PATCH /households/{id}`, `GET/POST/PATCH /visits`, `GET/POST/PATCH /referrals`, `GET /follow-ups`, `POST /health-qa/query`, `POST /health-qa/retrieve`, `GET /protocols`, `GET /protocols/{id}`, `GET /protocols/{id}/passages`, `POST /reports/summary`, `GET /reports/{id}`, `GET /sync/pull`, `POST /sync/push`, `GET /sync/status`, `GET /health`, `/docs`, `/openapi.json`.
Per-file test counts (SQLite run): architecture_hardening 29 · database 12 · dataset_import 8 · health_qa 13 · households_visits 12 · migrations 2 · protocol_import 24 · referrals 10 · reports 65 · retrieval 15 · safety 151 · security_api 20 · sync 66.

| Feature | Files / endpoints | Status | Test evidence | Outstanding |
|---|---|---|---|---|
| FastAPI app, validation, errors | `main.py`, `core/errors.py` | Implemented; refuses to start with auth disabled in production; unhandled errors logged without bodies | architecture_hardening | — |
| Authentication / authorisation | `core/security.py` | **Partial.** Static API keys with roles worker/admin/hospital, constant-time compare; a worker is restricted to own households/visits/referrals (403 otherwise) | `test_security_api` (20) | No login, no key expiry/rotation, no per-user identity, no rate limiting, no lockout |
| SQLAlchemy models + Alembic | `db/models`, `alembic/versions` (2 migrations) | Implemented | `test_migrations`, `test_database` incl. Postgres up/down/no-drift | — |
| SQLite and PostgreSQL | `db/session.py` | Both verified (426 and 427 passes) | Observed this audit | Only PostgreSQL 16.2 via pgserver; no managed-DB/SSL/pooling test; no load test |
| Households + details | `api/v1/households.py` | Implemented (list, filters, create, patch) | households_visits | The app never uses create/patch |
| Visit planning / follow-ups | `visits`, `GET /follow-ups` | Implemented | households_visits | App computes plans locally and ignores `/follow-ups` |
| Referrals + status tracking | `referrals` | Implemented incl. duplicate/invalid states, attendance only via record | referrals | — |
| Reports + CSV/PDF export | `services/reports` | Implemented | reports (65) | Needs hospital-side review of the content; freshness label depends on a client-supplied timestamp |
| Health Q&A pipeline | `services/health_qa/orchestrator.py` | Implemented: safety first, then retrieval, then answer-with-citation or refusal | health_qa (13) | **Never run on real protocols** |
| Protocol importer + metadata | `scripts/import_protocols.py`, `services/protocol_import` | Implemented: `.txt/.md/.pdf (pypdf)`, imports as UNVERIFIED, explicit audited `approve`/`revoke` | protocol_import (24) | **No real document has ever been imported**; PDF extraction quality on real documents unknown |
| Retrieval + citations | `services/protocol_retrieval` | Implemented (term-coverage scoring, min score 0.5, min 2 matched terms) | retrieval (15), with fixture corpus | Quality on real text unknown; retrieval-evaluation dataset is empty |
| Safety escalation engine | `services/safety` | Implemented; negation/history/hypothetical handling; short-message policy | safety (151); 142/142 vs synthetic labels | **Draft lexicon, unreviewed, no clinical thresholds; known "substring cue" quirk (BACKEND_GAPS #7)** |
| Insufficient-evidence / out-of-scope | orchestrator + safety | Implemented (`INSUFFICIENT_EVIDENCE`, `OUT_OF_SCOPE`, `CLARIFICATION_REQUIRED`) | health_qa, safety | — |
| Offline sync, retries, acks, conflicts | `services/synchronization` | Implemented: idempotent op ids, per-op status, `VERSION_CONFLICT`, race handling, 1-second overlap on pull | sync (66) + 20 Flutter real-backend tests | Pull cursor is a 1-second timestamp: >500 changes in the same second cannot be paged correctly (BACKEND_GAPS #4) |
| Security / privacy / validation | various | Question text never logged or stored; installation id stored as salted hash; question ≤ 2,000 chars; docs can be disabled | architecture_hardening, security_api | **Default salt `dev-only-salt-change-me` is not rejected in production**; no CORS/HTTPS/rate-limit config (expected to be provided by the host); only `eligible_statuses` and auth are guarded at startup |
| OpenAPI + docs | `docs/openapi.json`, `API_CONTRACT.md`, `FLUTTER_INTEGRATION_GUIDE.md` | Exist. I did not regenerate or diff `openapi.json` against the running app. | not checked | — |
| Response compression (added today) | `main.py` GZip | Verified: 30 KB → 1.9 KB, 136 KB → 8.5 KB | backend suite still passes | — |

---

## E. Missing and incomplete work

**Missing pages / flows**
- Login / sign-in and sign-out; any per-worker identity on the phone.
- In-app splash/branding screen, onboarding, first-run language choice, permission explanations.
- Add / edit household (and any household-level notes).
- Visit notes field (backend has none).
- Referral editing beyond plan/cancel; a facility directory (the facility picker is built from referrals already on the phone — BACKEND_GAPS #1).
- A device-level "report a problem / send logs" path.

**Exist but not functional for the real purpose**
- **Ask → medical answers with citations.** Fully built, zero content. Until approved protocols are loaded, every non-danger question ends in "cannot be verified".
- **Danger-sign card guidance.** Shows "no approved protocol loaded"; escalation wording is placeholder.
- **Call supervisor button** appears only if a number is entered in Settings.
- **Server reports (CSV/PDF)** and **protocol download** need internet and a configured server.

**Integration gaps**
- The app uses only `/sync/*`, `/health-qa/*`, `/reports/*`, `/protocols/*`. It never calls `/households`, `/visits`, `/referrals` or `/follow-ups` REST endpoints (by design; sync carries visits and referrals; **households can only be pulled**, never created/changed from the phone).
- Telugu strings are a developer draft; Telugu speech needs internet (Google offers no offline Telugu pack); offline English dictation was **not confirmed** (the emulator had no usable offline pack).

**Known bugs / risks found**
1. **iOS notification crash path (CODE-ONLY).** `lib/services/alert_notifier.dart` initialises `flutter_local_notifications` with Android settings only. The plugin source (`flutter_local_notifications_plugin.dart`) throws `ArgumentError('iOS settings must be set…')` on iOS, and `lib/app.dart` calls `requestPermission()` at start with no error handler. Never run (no iOS build).
2. **Alerts are only raised while the app runs** (start, resume, after sync/save). Between runs only an 08:00 reminder fires and its count is from the last run. No background evaluation.
3. **Performance noise on the real phone:** one profile run showed frame-build spikes up to 40 ms on several pages (the first run did not). Cause not isolated.
4. **Docs drift:** `docs/PERFORMANCE.md` still says "none connected" and "no animation beyond default route transitions"; `README.md` title still reads "Health Companion"; `lib/sync/` and `lib/data/repositories/` are empty leftover folders.
5. **Retry buttons exist in only 3 places**, so some error screens offer no retry.
6. **Release build is signed with the debug key** (`android/app/build.gradle.kts`); no release keystore, no explicit code shrinking configuration (not verified either way).
7. Application ID `in.healthcompanion.health_companion` does not match the "ASHA" name (changing it later installs as a separate app and loses data).

**Untested / unverified (honest list)**
- Any **iOS** behaviour; any **real small phone** (small-screen layout is tested at 320×568 in widget tests only); **TalkBack/VoiceOver** on a device; **Android share sheet**; **referral plan/cancel on a device**; a **sync conflict on a device**; **voice input on the real phone** (tested on the emulator only); **offline voice dictation**; app behaviour when killed mid-sync on a device (covered by a unit test that reopens the database file, not by a device test); behaviour on a genuine 2G/weak-4G network; Postgres in a managed/SSL setup; load/concurrency; screen-reader announcements for the new animations.

---

## F. Prioritised implementation plan (proposal only — awaiting your approval)

### P0 — Critical blockers
| # | Item | Files / modules | Depends on | Acceptance criteria |
|---|---|---|---|---|
| P0-1 | **Put the work under version control** | repo root; add a `.gitignore` for `build/`, `.dart_tool/`, `.venv/`, `*.db` | nothing | `git status` clean; the three folders and `.env.example` committed; no secrets or database files committed |
| P0-2 | **Obtain official protocol documents, import, review and approve** | `scripts/import_protocols.py`, `docs/PROTOCOL_ARRIVAL_CHECKLIST.md`, `health-worker-datasets/protocol_passages.jsonl` | clinician/authority supplying the source documents | `import_protocols.py list` shows approved documents with title, authority, version, pages; a sample question returns a cited answer in the app **offline**; every shown passage matches the source page exactly (spot-checked by a clinician) |
| P0-3 | **Clinician review of safety rules and all alert wording (English + Telugu)** | `danger_rules.json` (backend + app copy), `messages`, `tool/gen_arb.py` | P0-2 | `review_status` set by the reviewer; `clinically_validated: true` only on their sign-off; placeholder text removed; Dart/backend parity test still passes |
| P0-4 | **Authentication decision** | backend `core/security.py`; app `settings_screen.dart` | product decision | A worker cannot see another worker's data; admin keys cannot be typed into a worker phone by mistake; keys can be revoked/rotated |

### P1 — Required for a complete, usable app
| # | Item | Files | Depends on | Acceptance criteria |
|---|---|---|---|---|
| P1-1 | Fix the iOS notification initialisation and build/test on iOS | `alert_notifier.dart`, `app.dart`, `ios/Runner` | full Xcode installed | `flutter build ios` succeeds; app launches on a simulator; alerts init without exception |
| P1-2 | First-run onboarding: language choice, what the app does/doesn't do, permissions explained, server setup | new screen under `presentation/screens/`, `main.dart` | P0-4 | New install lands on onboarding once; can be skipped; works offline |
| P1-3 | Add / edit household (if required by the field workflow) | `households_screen.dart`, `field_work_service.dart`, outbox op type `household` (backend already accepts it) | product decision | A household created offline appears on the server after sync; conflict path tested |
| P1-4 | Device test pass for the untested flows: referral plan/cancel, share sheet, conflict resolution, voice on the real phone, kill-during-sync | `test/`, manual checklist | physical phone | Each flow demonstrated and recorded; defects fixed |
| P1-5 | Native-speaker review of Telugu UI | `tool/gen_arb.py` (then regenerate ARB) | a reviewer | Every string approved or corrected; `telugu_complete_test` still passes |
| P1-6 | Retry on every error screen | `widgets/common.dart`, screens | — | Every `ErrorState` has a working retry |
| P1-7 | Background urgent check (WorkManager or similar) so alerts don't depend on opening the app | new service + Android config | product decision | A newly urgent household notifies within the chosen interval with the app closed |

### P2 — Production hardening
| # | Item | Files | Acceptance criteria |
|---|---|---|---|
| P2-1 | Release signing + application ID decision + shrinking | `android/app/build.gradle.kts` | Release APK/AAB signed with a private keystore; ID final |
| P2-2 | Backend: reject default `device_hash_salt` in production; add rate limiting; require HTTPS via host; key expiry | `core/config.py`, `main.py` | Startup refuses weak salt in production; tests added |
| P2-3 | Encrypt the local database or document the risk (sqflite is unencrypted; backups are disabled) | `data/local/database.dart` | Decision recorded; if encrypted, migration + test from an unencrypted DB |
| P2-4 | Keyset pull cursor (timestamp + id) | `synchronization/service.py`, `sync_engine.dart` | 1,000 changes in one second sync completely (test) |
| P2-5 | Real small-phone and low-RAM testing; TalkBack pass; measure memory/battery | manual + `integration_test/` | Recorded numbers replacing every NOT MEASURED above |
| P2-6 | Tidy: delete empty `lib/sync`, `lib/data/repositories`; fix docs drift; regenerate `openapi.json` and diff | docs, folders | Docs match behaviour |
| P2-7 | Server-side `approved_only` protocol filter (BACKEND_GAPS #5) | `api/v1/protocols.py` | Phones download only approved passages |

### P3 — Optional enhancements
Facility directory endpoint; visit notes (backend + app); richer reports; dark mode; larger-text and high-contrast options; analytics-free crash reporting; per-worker home-screen widgets; tablet layout.

---

## G. Final verdict

1. **Is the backend complete?** **Functionally yes for the planned scope, not production-ready.** All 25 routes exist and 426/427 tests pass (SQLite / PostgreSQL). Missing for production: real protocols, clinical sign-off, a real authentication scheme, rate limiting, weak-salt guard. Its Q&A and safety features have never run on real clinical content.
2. **Is the Flutter frontend complete?** **Mostly, for a pilot-style prototype.** Every screen on your list exists except login, splash and onboarding; all connect to local storage and (via sync) the real backend. It is not complete for the real purpose because the medical-answer path has no content, and household add/edit does not exist.
3. **Which pages are still missing?** Login/sign-in, in-app splash, onboarding/first-run, add/edit household, visit notes, referral editing beyond plan/cancel.
4. **Which pages exist but are not functional for their purpose?** Ask → cited answers (no protocols), the danger-sign "approved guidance" section (no protocols), server CSV/PDF reports (need a server), the call-supervisor button (needs a number).
5. **Does the core workflow work offline?** **Yes, observed on a real phone:** see the household list, plan and complete visits, save referral recommendations, get danger-sign escalation, get answers from the worker's own records, receive urgent notifications — all in airplane mode — and changes sync automatically when the connection returns. **No** for cited medical answers (no content), voice dictation (needs internet), server reports and protocol download.
6. **Does Flutter actually communicate with the existing backend?** **Yes.** 20/20 integration tests pass against the real FastAPI backend, and I synced a real phone and an emulator with it. Households are pull-only.
7. **Can the Android app currently build?** **Yes.** Debug and release APKs built successfully during this audit (release 59,542,868 bytes). The release is signed with the debug key, so it is not distributable.
8. **What must be completed before a real-world field trial?** P0-1 to P0-4, plus P1-4 (device test pass), P1-5 (Telugu review) and a decision on identity. In addition: a named clinician accountable for the rules and wording, a plan for who runs the server, and a clear statement to participants that the app is a prototype and not a diagnostic or advice tool.
9. **Five most important next actions**
   1. **Commit the project to git** (P0-1).
   2. **Get the official protocol documents** and run the import → review → approve workflow (P0-2).
   3. **Have a clinician review the danger-sign rules and every alert message** in English and Telugu (P0-3).
   4. **Decide the authentication model** and stop using shared/admin keys on phones (P0-4).
   5. **Run the device test pass** (referral flow, share sheet, conflict, voice, kill-during-sync) on a low-end phone and record real numbers (P1-4, P2-5).

---

## H. What I could not inspect or verify

- The original **reference UI image** (not in the repository; only seen earlier in conversation). UI-versus-reference comparison **not possible**.
- Anything on **iOS** (no Xcode).
- The correctness of `docs/openapi.json` against the live app (not diffed).
- Clinical correctness of anything (no clinical source material exists in the project; none was invented).
- Behaviour on networks other than Wi-Fi and a local simulated slow link.
- Whether R8/shrinking is applied to the release build.
- The older `docs/*.md` numbers were not trusted; where this report states a test count or size it comes from a run or file read during this audit.
