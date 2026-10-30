# Test report (actual runs)
`flutter analyze`: **no issues**. `flutter test`: **336 passed, 0 failed, 20 skipped** (the skipped are the real-backend integration tests that need a server).
`tool/run_backend_integration.sh` (real FastAPI backend, SQLite temp DB, API-key auth on): **20 passed, 0 failed**.

| File | Passed | What it covers |
|---|---|---|
| safety_parity_test | 6 | bundled ruleset == backend ruleset; all 142 danger-sign cases + 200 questions; FN=FP=0; dosage refusal; "not clinically validated" flag |
| database_test | 7 | schema, migration v1->v2 keeps data, restart persistence, FK/CHECK, paging, filters, LIKE-wildcard safety |
| field_work_test | 12 | offline visit/referral writes, op ordering/payloads, validation writes nothing, atomic rollback, restart, referral phase accuracy |
| sync_engine_test | 20 | ack-only-synced, offline, lost response, restart, stable op ids, 5xx, retryable, rejected+retry+discard, conflicts (keep server / keep mine), pull protection, 401, not configured, duplicate referral, no concurrent sync, 1-second pull overlap |
| api_client_test | 27 | request shapes, header/body placement of ids, typed parsing, every error class, invalid/missing fields, timeouts, config, log redaction |
| domain_services_test | 23 | local retrieval, QA ordering, protocol library gating, visit/report rules incl. all 55 backend hospital-report scenarios, demo data, settings/secret store |
| widget_flows_test | 12 | dashboard, empty state, navigation, planner order, visit form validation + offline save, register paging/search, settings (language, URL validation, masked key, clear data) |
| qa_ui_test | 14 | escalation (server never asked; approved local protocol text shown beside it only when loaded and VERIFIED, otherwise the card says none is loaded), Telugu/code-mixed/transliterated escalation, supervisor call, clarification, refusal, insufficient/cannot-verify/verified/unverified evidence, no question stored |
| referral_sync_reports_ui_test | 15 | referral wording per state, filters, plan/cancel, sync centre states (pending/offline/401/unconfigured/rejected/conflict), local + server reports, CSV/PDF share |
| layout_accessibility_test | 41 | 27 no-overflow cases (3 phone/text-scale/language configs x 9 screens, scrolled to bottom), Android+iOS tap targets, labels, text contrast, live-region escalation, auto-send on save/reconnect |
| integration/real_backend_test | 20 (separate run) | pull scoping, offline->sync, duplicate resend, version adoption, real conflict flow, forbidden attendance, Q&A, reports, auth |

## Defects these tests found in the app itself (all fixed)
Page body squeezed to 0 height by the nav `Column`; ripples hidden under coloured containers (settings, escalation card); stat tiles/filters/labels overflowing at large text or Telugu;
header text contrast 1.6:1 on the mint gradient and 3.8-4.3:1 on buttons; dashboard "open referrals" disagreeing with the list for a record flagged confirmed without a record;
phone numbers with spaces percent-encoded in `tel:`; green "sync finished" shown while changes were rejected; pull skipping same-second server changes (real backend).

## Not tested
Physical devices; iOS builds; TalkBack/VoiceOver with a real reader; Telugu text review by a native speaker; any real protocol content; sync at scale; iOS/Android lifecycle edge cases beyond the unit/widget level.
