# Health Companion (Flutter) - frontline health-worker app

Offline-first Android/iOS app for ASHA/ANM workers, built on the existing FastAPI backend in `../health-worker-backend`.
**All demo records are synthetic. Protocol content is not yet available and the danger-sign rules are NOT clinically validated.**

## Status in one paragraph
Nine screens (home, visit planner + visit form, household register + detail, ask-a-question with safety escalation, referrals, reports,
sync centre, settings, more) work against local SQLite first and sync through the backend's documented protocol. Verified: 344 automated tests
pass (details in `docs/TEST_REPORT.md`), 20 more run against the **real** backend via `tool/run_backend_integration.sh` (all passed), `flutter analyze` is clean,
and a release APK builds. **Not verified:** any real device (size/RAM/latency are pending), any iOS build (no Xcode on the build machine),
TalkBack/VoiceOver with a real screen reader (only Flutter's automated accessibility guidelines were run), official protocol content.

## Design
Taken from the reference image: teal gradient header, white 24-px cards, teal primary buttons, pill chips, capsule bottom navigation
(`lib/core/theme/tokens.dart`). Two deliberate departures, both found by automated contrast tests: the header gradient stays dark (the mint of the reference
sits below the text), and the primary teal is slightly darker (>= 5:1 with white text). Status is never colour-only: every status has an icon and words.
Telugu/English UI (410 strings, `tool/gen_arb.py`); **the Telugu text is a developer draft and needs review by a native-speaking health worker.**
Telugu is rendered with the platform font (no bundled font, to keep the APK small).

## Architecture (small dependency set)
```
lib/core/            theme tokens, clock          lib/data/api/     typed ApiClient, exceptions, models
lib/data/local/      SQLite + versioned migrations lib/data/models/  Household, Visit, Referral, OutboxOp
lib/domain/          safety engine (Dart port), local retrieval, visit + report rules (pure Dart)
lib/services/        FieldWorkService (offline writes), SyncEngine, QaService, ProtocolLibrary, ReportService, settings
lib/state/           composition root (AppServices), connectivity + sync controllers (provider)
lib/presentation/    screens, reusable widgets          lib/l10n/        generated localisations
```
Packages: provider, sqflite, http, intl, shared_preferences, flutter_secure_storage, connectivity_plus, share_plus, url_launcher, path_provider, uuid.
No ML model, no vector store, no heavy UI kit, no background service.

### Offline rules (what is guaranteed and tested)
- Every local change is saved **and** queued in the outbox in ONE SQLite transaction (rollback test); it survives app restart (test).
- An operation is "synced" only when the server returns `acknowledged: true`. Network failure/timeout = unknown -> resend with the same `op_id` (lost-response test shows no duplicate on the server).
- CONFLICT/REJECTED changes stay visible with the reason; nothing is overwritten. Pull never overwrites a record that has an unsynced local change.
- Pull re-requests with a 1-second overlap (a real bug found by the real-backend test: same-second server changes were skipped).
- Safety checks run on the device first, with the same `danger_rules.json` file as the backend (byte-identical test; all 142 danger-sign cases and 200 questions agree). An escalation never calls the server and never shows an answer.
- Offline protocol answers need locally stored VERIFIED + approved passages; otherwise the screen says "cannot be verified offline". Today the library is empty.
- A referral reads as "attendance confirmed" ONLY with an attendance record; planned/recommended always say "attendance NOT confirmed".

## Setup / run / test
```bash
# toolchain used here: Flutter 3.47.7 (Dart 3.13.5), JDK 17, Android SDK 36   (see docs/BUILD.md)
cd health-worker-app && flutter pub get
python3 tool/make_demo_seed.py     # regenerate demo seed + copy the backend's danger_rules.json asset
python3 tool/gen_arb.py && flutter gen-l10n
flutter run                         # then Settings: server address, access key, or "Load synthetic demo data"
flutter analyze && flutter test     # 344 pass, 20 skipped (need the backend)
tool/run_backend_integration.sh     # starts the real backend on a temp DB, runs the 20 integration tests
flutter build apk --release --split-per-abi
```
Emulator -> host backend: `http://10.0.2.2:8000` (plain http is allowed ONLY for 10.0.2.2/localhost by `network_security_config.xml`; real servers need https).
Authentication = the backend's `X-API-Key` (stored in Keystore/Keychain; Settings never shows it back). There is no login screen because the backend has none.

## Known limitations (honest list)
- Voice input: not implemented (no on-device speech model; the brief allowed it only if real).
- Visit notes: the backend has no notes field, so none exist. Facilities: no facility-list endpoint; the picker uses facilities seen in local referral records.
- Release APK is signed with the debug key; create a release keystore before distribution. iOS: code is shared and platform files are configured (tel: query scheme) but **never built or run**.
- No push notifications exist, so nothing can leak household data in notification previews. No background sync: uploads happen in the foreground (after save, on reconnect, on resume).
- Pull pagination assumes <= 500 changed records per second per type (backend limitation: timestamp cursor, no tie-breaker).
- Local protocol search is exact-token only (no Telugu stemming/transliteration) and loads approved passages into memory; fine for a handful of documents, revisit for large corpora.
- Safety wording shown on escalation is placeholder text from the backend ruleset until clinicians approve it.


## Voice input and danger signs (what is and is not verified)
- The Ask screen has a microphone (English / తెలుగు). It uses the phone's own speech recogniser (Google Speech Services on Android); nothing is bundled and the app does not store audio. The text only fills the box; the worker reviews it and presses Check.
- Tested on an Android emulator (arm64, API 35) with the host microphone: English dictation worked; Telugu was recognised (Telugu script, plus a duplicate romanised copy). Telugu needs internet (no offline Telugu pack in the Google app tested). Accuracy on real phones, accents and noise is **not** tested. Not tested on iOS.
- A danger sign is never answered or reassured. Beside the urgent steps the card shows APPROVED protocol passages from the phone's library when one is loaded (VERIFIED + approved only). **No approved protocol is included in this project**, so today the card says none is loaded. The escalation wording is still a draft placeholder and the safety rules are not clinically validated; a qualified reviewer must supply and approve both (see the backend's `PROTOCOL_ARRIVAL_CHECKLIST.md`).
- Offline check (emulator in airplane mode): status shows Offline; Home data loads; a danger sign still escalates; a routine question says it cannot be verified offline. Syncing resumes when the network returns.
- Offline voice: Google offers offline speech packs for many languages but **not Telugu**, so Telugu dictation always needs internet. English can work offline only if the phone has the offline English pack actually downloaded (on the test emulator it was not usable, so offline dictation was NOT confirmed). When offline and no pack exists, the app says so and asks the worker to type; typing and the danger-sign check always work offline.

## Priority list and answers from the register
- **Attend first** (Home, and the "See full list" screen) ranks households that are waiting for something. The score uses only register fields: days overdue, open referrals not yet attended (and how long they have waited), missed visits in the last 90 days, and the visit type as a tie-breaker. Each household shows the reasons behind its position, with an icon and a word (never colour alone). **The weights are placeholders in `lib/domain/rules/priority_rules.dart` (`UrgencyWeights`); this is not a clinical risk score and needs clinical review.**
- **Ask** answers questions about the worker's own list from the phone's database, offline: "who should I attend first", "which households are overdue", "visits due today", "open referrals", "how many households", or a household ID. It states facts about records only, never medical advice, and recognises English and Telugu wording. Medical-knowledge questions are not answered until approved protocols are loaded (no medical text is invented).
- When the safety check needs more detail, the card offers tap-to-add chips (right now / severe / pregnant woman / baby) that add the words and re-check.

## Urgent alerts and weak networks
- **Urgent alerts.** When a household becomes *urgent* in the Attend first list, the phone raises a notification. It is worked out on the phone from its own data, so it works offline and on 2G. Each household alerts once (more than three at once are grouped into one summary), a household that stops being urgent can alert again later, and a morning reminder is registered with Android for 08:00 India time, which fires even with the app closed and no network. Settings has an on/off switch; Android 13+ asks for the notification permission when the app starts. The lock screen shows only the app name (notifications are marked private), so household IDs are not shown to anyone holding a locked phone. **Limits:** the alert is raised when the app runs (start, resume, after a sync or a saved visit); between app runs only the 08:00 reminder fires, and its count is the one from the last time the app ran. There is no always-running background check. Tested on the Android emulator (online and in airplane mode) and unit-tested; the vivo phone's own notification display was not checked. "Urgent" uses the prototype weights in `lib/domain/rules/priority_rules.dart`; it is not a clinical risk score.
- **Weak networks.** The backend compresses responses over 1 KB (a full first sync is about 190 KB raw and about 13 KB compressed). The app limits how long a download may take once it has started (60 s) as well as how long it waits for the server to answer (15 s). On a simulated slow link (about 20 KB/s) a full first sync took about 29 s uncompressed and about 2 s compressed. Everything the worker does reads and writes the phone's own database, so a weak link only affects syncing and voice input. Not tested on a real 2G/4G network.

## Language: English and Telugu (Settings -> Language)
- The whole interface switches, immediately and without restarting: every screen, button, message, dialog, filter menu, error, voice-problem message, notification, the danger-sign card (message and "why this was shown") and the Settings diagnostics. The choice is remembered.
- **Checked automatically.** `test/telugu_complete_test.dart` opens every screen and each Ask outcome (danger sign, needs more detail, medicine request, cannot verify, answers from records), plus dialogs, filter menus, the visit form, sync errors and every voice-problem message, in Telugu, and fails if any visible text, tooltip or screen-reader label still contains English words. Only the product name ASHA, the language name "English", record IDs (HH-SYN-00001), version numbers and the server web address stay in Latin letters.
- **Telugu wording is a developer draft** (including the danger-sign placeholder text) and must be reviewed by a native-speaking health worker, and the clinical wording by a clinician, before field use.
- **Not translated (outside the app's control):** text taken from approved protocol documents is shown in the language of the document; PDF/CSV reports produced by the server use the server's English headings; the Android notification channel name ("Urgent households") appears only in the phone's own settings; the phone's keyboard and Google speech service use their own languages.

## Opening the app: splash, language choice and onboarding
- **Every launch** starts with the ASHA splash (logo, name, tagline; about 1.9 s, in the saved language). Android 12+ also shows its own system splash with the launcher icon for a moment before the app draws.
- **A brand-new install** then shows the first-run flow: (1) choose language (Telugu or English; the page names both languages so it can be read by either), (2) your day in one place, (3) works without internet, (4) safety comes first (states the rules are a draft and not clinically validated), (5) the two permissions explained (microphone, notifications) and where to add the server. Pages 2-4 can be skipped; the language choice cannot. The choice switches the app immediately and is saved. The notification permission is requested at the end of this flow, not over the splash.
- **Installs that already have settings saved** (language, server address or demo mode) are treated as done and go straight in after the splash, so an update never sends a working phone back through the welcome screens. Android's back button steps back through the pages. "Remove animations" shows the splash finished at once.
- Code: `lib/presentation/launch/` (`launch_gate`, `splash_screen`, `onboarding_screen`, `asha_logo`). Tests: `test/onboarding_test.dart` (13: flow, language carry-through, permission timing, existing-install skip, back button, reduced motion, tiny-screen layouts, no English left in Telugu).
- **Verified on:** Android emulator (clean data: splash, language, all pages in Telugu, notification prompt, Home) and the vivo phone (existing install: splash, straight to Home). **Not verified:** iOS; a brand-new install on the real phone (its data was kept so as not to wipe your work); TalkBack reading of the new pages. The Telugu wording is a draft pending native-speaker review.

## Visit date and time (when the worker went)
- **Detected, not typed.** Opening a visit reads the phone's clock: the date and time of day appear on the visit form as one read-only, locked row ("Recorded automatically when you opened this visit. It cannot be changed."). There is no date picker, time picker or edit control, so the worker cannot change either. Saving records the date and time that were shown when the form opened. Nothing else on the form changed (the next follow-up date is still chosen by the worker: it is a future appointment, not when the visit happened).
- **Sent to the server.** For a COMPLETED visit the app sends `actual_visit_date` and now also `actual_visit_time` (`HH:mm`, local time as entered, no time zone). The backend stores it in `visits.actual_visit_time` (migration `0003`), returns it from the visit endpoints and sync pull, accepts it only on COMPLETED visits (`ACTUAL_TIME_NOT_ALLOWED` otherwise) and treats it as a protected field in conflicts. It is optional, so older app versions keep working. A could-not-visit time is kept on the phone only (the server stores a time only on completed visits).
- The phone keeps its own copy (`visit_times`, schema v3) so older visits and could-not-visit times still show; a pulled visit that carries a time updates it. Shown on the finished visit and in the household's visit history.
- **Limits.** The phone's clock is trusted: a worker who changes the phone's own date/time settings would change what is recorded (the app cannot detect that; the server does not check the time against its own clock). "Opening the form" is not always "arriving". Visits recorded before this change have no time on the server. The time zone is not stored (local time as entered). For a could-not-visit record the date shown is the day it was recorded, and the server does not store it.
- **Verified:** backend 432 passed on SQLite and 433 on real PostgreSQL 16 (6 new tests incl. sync round trip and conflict); the app's 20 real-backend integration tests pass; on the emulator a visit recorded at 11:40:59 reached the server as `2026-10-13` / `11:40:00`. Not verified: iOS; a visit recorded on the real phone after this change; the Telugu wording of the new strings (draft).

## Optional AI answer on the Ask screen
- **What happens on Check.** (1) The existing flow runs exactly as before, at once and on the phone, so a danger-sign card is never delayed. (2) If the phone is online and a server address is set, the question is also sent, at the same moment, to the app's backend (`POST /api/v1/health-qa/llm`), which asks Anthropic Claude. If an answer arrives within **4 seconds** it is shown in an "AI-generated answer" box **below** the normal result, labelled "AI-generated. Not clinically verified. Not a diagnosis. Follow your approved protocols." If the 4 seconds pass, or anything fails, nothing is added and no error is shown; the normal result stays. A newer Check replaces an older one. A medicine/dose question is not sent to the AI (the app refuses those on purpose). Offline, the AI is never called.
- **Danger signs still go to the AI** (your decision): the red card shows first and the AI answer is added beneath it. Note this puts unreviewed AI text near an emergency warning; the box is labelled and sits below the card.
- **Privacy.** The question text leaves the phone for the backend and the AI provider when online. The Ask screen says so ("When you are online, your question is also sent to an AI service…"). The backend never logs or stores the question or the answer and does not copy the provider's error text into its replies. Anthropic's own data handling applies; check their terms before using real patient information. Only the question and the phone's safety status are sent (no household IDs).
- **Setup (server).** Set `ANTHROPIC_API_KEY` in the backend's environment (never commit it). Optional: `LLM_MODEL` (default `claude-haiku-5-5`), `LLM_TIMEOUT_SECONDS` (default 3.5), `LLM_BASE_URL` (default the Anthropic API; for a proxy). Without a key the endpoint answers 503 `LLM_NOT_CONFIGURED` and the app silently shows only the normal result.
- **What was and was not verified.** Backend: 8 tests with a mocked provider (success, danger-sign context, timeout, errors, no logging of the question, validation); full backend suite 440 passed on SQLite and 441 on real PostgreSQL. App: 15 tests (answer shown below the result, 4 s timeout, offline, server errors, danger sign order, no call for dose requests). On the emulator the whole path (app -> backend -> HTTP -> provider) was run against a LOCAL STAND-IN server that mimics the Anthropic API format, for both a quick answer and a slow one that hit the time limit. **No real Claude call was made** (no API key was available), so the real model's answers, latency and the system prompt's effect are untested, and 4 s may often be too short for a real model over a weak connection.

## Offline answers: sample protocol text and saved AI answers (DEMO ONLY)
- **Sample protocol text (`assets/demo/demo_protocol.json`).** There is still **no approved protocol** in this project. For demonstrations, "Load synthetic demo data" (Settings) also loads one **fictional** handbook, "DEMO SAMPLE - fictional field handbook (not a real document)": 13 short English + Telugu passage pairs about the app's own workflow (recording visits, nobody at home, referrals, privacy, working offline, danger signs the app looks for, medicines not given by the app). **They contain no medical facts, doses or thresholds**, every passage starts with "[DEMO SAMPLE]" / "[డెమో నమూనా]", and the document is stored as `TEST_FIXTURE_ONLY`, never `VERIFIED`. The library only offers them while **demo mode is on**; they are always shown as "Unverified text - not medical guidance", never as approved; the danger-sign card calls them "Sample text (not approved guidance)"; "approved passages" counts stay 0; a server protocol refresh never deletes them. With demo mode off they are not searchable. This is the same offline retrieval path real approved protocols will use: when real documents are imported and approved on the backend, the phone downloads them and quotes them offline with citations, no code change.
- **Saved AI answers.** When the AI (previous section) answers, the answer is kept on the phone (the last 20). Offline, or when the AI does not answer within 4 seconds, a saved answer to the *same question* (ignoring case and punctuation) is shown in a box titled "Saved AI answer (from earlier)" with the date it was saved and why it is shown. Only a one-way hash of the question is stored, never the question text; "Clear data" removes them. A saved answer is only as good as when it was written (it is AI text, not clinically verified) and is never invented for a new question.
- **Verified:** 16 new tests (sample labelling, demo-mode gating, refresh safety, Telugu, danger-sign heading, dose requests still refused first, saved answers: storage without question text, offline reuse, 20-answer limit, clearing). On the emulator with the network off: the database upgraded to schema v4 over existing data, "Load demo" took protocol passages from 0 to 26, and an English question about nobody being at home was answered offline from the sample with its labels. **Not verified:** a saved answer on a real device after a real AI call; iOS; the Telugu wording (draft).

## Adding a new family
- **Households page -> "Add a new family".** The form asks for the village ID (prefilled with the village you work in most; other villages on the phone are one tap away), the number of members (1-60, with + and - buttons) and which follow-up types may apply (Routine is ticked by default; at least one is required). Saving writes the family to the phone and queues a household create in the same transaction, so it works with no network, then opens the family's page so a first visit can be scheduled ("Schedule a visit").
- **Sync.** The id is created on the phone (like visits), so a retry cannot add the family twice; the backend's existing household-create via sync accepts it (no backend change). A family the server rejects can be discarded in the Sync centre, which removes it from the phone again. The family is assigned to the worker this phone belongs to (the worker most households on the phone are assigned to); a phone that has no data yet and does not know its worker says to sync or load the demo first.
- **Verified:** 16 tests (storage + queue, validation saves nothing, unknown worker, sync to the fake server, discard, the form, Telugu, tiny screens). On the emulator: a family was added while offline (6 members, Antenatal care + Routine), the chip showed "1 waiting to sync", then after the network returned it synced on its own and the real backend's database held the household with the same fields.
- **Limits.** The village ID is typed (there is no village list on the server to pick from, so a typo creates a new village), there is no duplicate-family detection (two families with identical details are two families), and a family's details can't be edited from the app afterwards (the server supports household updates; the app does not use them). The new family has no visit until one is scheduled, so it does not appear in the planner or the "Attend first" list until then. Not tested on iOS or on the vivo phone.

## iOS (simulator only)
- **Built and run on an iOS 27 simulator (iPhone 18 Pro Max, Xcode 27) on 15 Oct 2026**, using Swift Package Manager (CocoaPods is not installed and was not needed). `flutter build ios --simulator --debug` succeeds; the app opens, shows the ASHA splash and onboarding, and asks for notification permission with the real iOS system dialog.
- **A real iOS bug was found and fixed:** the notification setup only had Android settings, so iOS logged `iOS settings must be set when targeting iOS platform` and notifications could not work. It now has iOS settings, asks permission at the end of onboarding (not at start-up for new installs), and checks permission before saving an alert as delivered.
- **Automated page test on the simulator:** `integration_test/perf_test.dart` loads the demo data and scrolls Home, Visits, Ask, Households, More, Referrals, Reports, Sync centre and Settings: all nine ran with no failed steps. That checks the pages open and scroll; it does not check every button, voice input, or the look of every screen.
- **Not verified on iOS:** a real iPhone, a release/App Store build and signing, speech recognition (microphone and speech permissions are declared but not tried), the tel: call button, the share sheet, notification delivery (permission dialog seen, but no notification observed), Telugu rendering, and syncing with the backend (the simulator can reach `localhost` but this was not tried). Frame timings from the simulator are not meaningful and are not recorded.

## Data pack, vector search and offline/online parity

Sample protocols, questions, aliases and safety rules live in `../asha-data/` (see its README). `python asha-data/build_data.py` copies them into `assets/data/` and `assets/safety/`. Search is a 512-dim hashing-embedding + keyword hybrid stored in SQLite; **Settings → Online AI help is OFF by default**, so the Ask page gives the same result with or without internet (`test/parity_test.dart`). No neural embedder or language model is bundled yet.
