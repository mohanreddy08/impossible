ROLE
You are a senior full-stack engineer. Build the complete SERVER-SIDE WEB APPLICATION (a supervisor dashboard in the browser plus the API) for an offline-first ASHA health-worker phone app. This is NOT a phone app: it is a website and API that the existing Flutter phone app syncs with, and that supervisors (ANM / Medical Officer) use in a browser.

HOW YOU RECEIVE THE CODE
The repo is private, so it arrives as a folder (ASHA-server-handoff). Read START_HERE.md first. Folders: health-worker-backend (FastAPI + the "h5" protocol engine), health-worker-app (Flutter phone app, do not change its sync contract), health-worker-datasets, h5-pack-data (hackathon data, synthetic; set H5_DATA to it), golden (Python-engine outputs for parity tests). Run the existing tests first and record the result (expected: 552 passed, 1 skipped; dev score 0.9581 with evaluate.py). Do not start building until they pass on this computer.

WHAT ALREADY EXISTS (extend it, do not rewrite it)
- Backend: API-key login, /health, /api/v1/sync/push and /api/v1/sync/pull (households, visits, referrals, outbox, versions), /api/v1/reports/summary, protocol Q&A (/health-qa/rag). Contract: docs/API_CONTRACT.md and docs/FLUTTER_INTEGRATION_GUIDE.md. Keep every existing endpoint working: the phone app must keep syncing unchanged.
- h5 package (health-worker-backend/h5): stdlib Python engine with danger-sign escalation, refusal rules, BM25 answers with section citations, and the VIS visit-list rules. Entry points: h5.pipeline.Assistant.answer(qid, text), h5.visit_list.build_visit_list.
- Data: Chandrapuri block, 500 households, 2,234 people, 5 ASHAs, 6 villages. ALL DATA IS SYNTHETIC. The pack has no coordinates; the village maps in health-worker-app/assets/h5/maps/*.json are a generated, made-up street layout.
- The phone app allows plain http only to 127.0.0.1, so a remote server MUST be reachable over HTTPS with a valid certificate.

THE MAIN REQUIREMENT: WORKS ACROSS DIFFERENT NETWORKS
The phone and the server computer will often be on DIFFERENT networks (phone on mobile data, server on home Wi-Fi). Do not rely on same Wi-Fi, local IPs or adb reverse. Deliver two ways to be reachable, with exact commands, tested:
1. Primary (free, runs on the server computer): a Cloudflare Tunnel (cloudflared) exposing the local server at a public https URL (a named tunnel on the user's domain if they have one, otherwise a quick tunnel). scripts/start_public.sh starts the backend, starts the tunnel, waits until /health answers through the public URL, and prints the URL to put in the phone app's Settings; scripts/stop_public.sh stops both. It must work on both macOS and Windows (give a .ps1 too).
2. Alternative (always on, not tied to a computer): Dockerfile, docker-compose.yml, render.yaml (or Fly.io), Postgres instead of SQLite, env-var secrets, health check, migrations. Document how to switch the phone app between the two.
Also handle: the phone going offline and returning (idempotent sync, retries, no duplicate households or visits), the computer sleeping (keep-awake instructions), the tunnel URL changing (show it in the dashboard Settings page and as a QR code that encodes the server address for typing into the phone app).

WHAT TO BUILD
A. API (FastAPI, Python 3.11, typed, OpenAPI at /docs)
- Keep existing endpoints. Add documented, versioned endpoints for the dashboard: households (filter by village / ASHA / status / priority, pagination); household detail with members, visits, due items; visit list per ASHA and date from the h5 VIS rules (priority 1/2/3); referrals and escalations feed; ASHA and village summaries; map data (house points per village with status colour); Q&A audit log (do NOT store question text; store outcome, cited section ids, timestamp); reports (CSV and PDF export); per-phone sync status (last seen, pending changes, app version).
- POST /api/v1/ask runs the h5 engine server-side and returns answer, citations, escalate, refused: identical to the phone.
- Auth: user accounts with roles (admin, supervisor, ASHA), argon2 password hashes, short-lived JWT sessions for the website, long per-phone API keys (shown once, stored hashed, revocable). Rate limiting, CORS locked to the site origin, security headers, request-size limits, audit log of admin actions. No secrets in git; .env.example only.
- Database: SQLAlchemy 2 + Alembic, SQLite locally, Postgres on deploy, one codebase. Seed script loading the synthetic block data.

B. WEBSITE (supervisor dashboard, mobile-friendly, English and Telugu)
Pick a simple, robust stack (Jinja2 + HTMX + Alpine.js, or React + Vite + TypeScript) and justify it in one paragraph. Pages:
1. Login. 2. Overview (due today / overdue / upcoming / open referrals, today's priority-1 list, escalations in the last 7 days, phones not synced in 48 h). 3. Visit list by ASHA and date, grouped by priority, rows open the household. 4. Houses map: all 500 houses by village, coloured by urgency (red urgent, orange due, blue this week, green nothing due), village switcher, tap a house for its people and due items; draw the generated street layout on canvas/SVG, no paid map API, no external tiles, with a visible banner "Made-up map, house positions are not real". 5. Household page (members, due-item chips, visit history, phone numbers masked with an audit-logged reveal, mini map). 6. Referrals and escalations (list, status changes, who handled it). 7. Ask the protocol (calls /api/v1/ask; answer with section citation; red REFER IMMEDIATELY card for danger signs; refusal card for out-of-scope; line "Clinician-assisting only, not a diagnosis"). 8. Reports (charts, CSV/PDF export). 9. Phones and users (admin): create accounts, generate/revoke phone API keys, QR code with the server address, sync status per phone. 10. Settings (public URL status, language, retention).
Accessibility: keyboard navigable, AA contrast, labelled inputs, status never by colour alone (icon + word).

C. SAFETY AND ETHICS (non-negotiable)
- All data is synthetic; show a "Synthetic data" banner on every page.
- The system assists clinicians; no diagnosis, no medicine doses. Danger signs always escalate and are never "answered". Keep the refusal rules (sex determination, medicines/doses not in the protocols, scan/report reading, admin, family planning).
- Privacy: never log question text, mask phone numbers, log every export and every reveal.

D. QUALITY
- pytest for the API (auth, roles, sync idempotency, duplicate-push safety, and h5 parity: /ask must equal h5.pipeline for the 240 questions in golden/golden.json). Playwright end-to-end tests for login, visit list, map tap-to-open-house, Ask page. All green; report exact counts.
- Load test: 50 concurrent phones syncing; report p95 latency.
- CI (GitHub Actions): ruff, mypy, tests.
- README: ASCII architecture diagram, local run in 3 commands, public access (tunnel and Render), how to point the phone app at the server, reset demo data, known limits.
- docs/DEMO.md: a 3-minute judge demo (phone on mobile data, server on a laptop through the tunnel: add a family on the phone, see it on the dashboard within seconds; ask a danger-sign question and see it in the escalations feed).

E. DELIVERABLES
Code in health-worker-backend/ (API) and a new health-worker-web/ (site); docker-compose.yml for one-command local start; scripts/ for the tunnel; Dockerfile; render.yaml; .env.example; seed script; tests; CI file; docs. Run the tests and the app yourself before saying it works; show exact commands and real output; say plainly what could not be verified. Do not push to git, deploy, or create cloud resources: stop and ask first. Do not touch the phone app's sync contract.

WORK ORDER
1) Run the existing tests and summarise the sync contract in 10 lines. 2) Propose schema changes and the API list, then build. 3) API, then website, then tunnel scripts, then Render files. 4) Test end to end through the public URL (curl is enough if no phone is available). 5) Write the docs.
