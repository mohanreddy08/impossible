# ASHA — Frontline Health-Worker Companion

Offline-first companion for ASHA/ANM frontline health workers (Telugu and English), plus a **server and supervisor website** that the
phone app syncs with. **Prototype on SYNTHETIC data. Not clinically validated, not medical advice, not ready for real patients.**

| Folder | What it is |
|---|---|
| `health-worker-app/` | Flutter phone app (Android). Its sync contract is unchanged by the server work. |
| `health-worker-backend/` | FastAPI server: phone sync API, website API, the `h5` protocol engine. See its `README.md`. |
| `health-worker-web/` | Supervisor website: templates, CSS, JS, English/Telugu strings, Playwright e2e tests. Served by the backend. |
| `health-worker-datasets/` | Synthetic sync datasets (the phone app's demo set: `HH-SYN-*`). |
| `h5-pack-data/` | Synthetic hackathon pack: Chandrapuri block (6 villages, 5 ASHAs, 500 households, 2,234 people) + protocols. |
| `golden/` | Python engine outputs used by the parity tests (240 answers, 346 visit-list rows). |
| `scripts/` | `dev_setup.sh`, `dev_run.sh`, `start_public.sh/.ps1`, `stop_public.sh/.ps1`, `reset_demo.sh`, `e2e.sh`. |
| `docs/` | [`DEMO.md`](docs/DEMO.md) (3-minute judge demo), [`PUBLIC_ACCESS.md`](docs/PUBLIC_ACCESS.md), [`SERVER_DESIGN.md`](docs/SERVER_DESIGN.md) (contract summary, schema, API list, stack, test results). |

No secrets are stored in this repository: `.env.example` files only. Create `.env` locally (the setup script does it with random values).

## Architecture

```
  ASHA phone (Flutter, offline-first)                  Supervisor (ANM / Medical Officer), any browser
  local SQLite + outbox, own h5 engine                 https://<server>/  (login, overview, visit list, map, Ask ...)
        |  X-API-Key (per-phone key)                          |  session cookie (JWT, 30 min, HttpOnly, SameSite=Strict)
        |  POST /api/v1/sync/push  GET /sync/pull             |  pages + fetch() to /api/v1/dashboard, /admin, /ask
        v                                                     v
  +--------------------------- HTTPS (valid certificate) ---------------------------+
  |  Option 1: Cloudflare Tunnel  (cloudflared on the laptop; no open ports, works   |
  |            from mobile data; quick tunnel = free, address changes each start)    |
  |  Option 2: Render (Docker web service + managed PostgreSQL; always on)           |
  +--------------------------------------+-------------------------------------------+
                                         v
  +----------------------------------- FastAPI (one process / image) ---------------+
  | Hardening: body-size limits, rate limits, security headers, CSP, CORS closed     |
  | Auth: phone keys (sha256-hashed, revocable) | users (argon2id) + JWT | roles      |
  |  /api/v1/sync, households, visits, referrals, reports, health-qa  (phone, as-is) |
  |  /api/v1/auth, dashboard, admin, ask   (website)        /  /visits /map ... HTML  |
  |  services: sync (idempotent ops) | dashboard (VIS visit list) | ask (h5 engine)  |
  |  h5 engine: danger signs -> refusal rules -> BM25 quotes with section ids        |
  +--------------------------------------+-------------------------------------------+
                                         v
            SQLAlchemy 2 + Alembic:  SQLite (one laptop)  |  PostgreSQL (Docker / Render)
```

## Run it locally (3 commands)

Needs Python 3.11+ (macOS/Linux; Windows: see below).

```bash
scripts/dev_setup.sh
```

```bash
scripts/dev_run.sh
```

```bash
open http://127.0.0.1:8000        # Linux: xdg-open; sign in with a password printed by dev_setup.sh (also in run/demo_credentials.txt)
```

`dev_setup.sh` creates the venv, a `.env` with random secrets and `AUTH_MODE=api_key`, runs the migrations and loads the synthetic data
with accounts `admin`, `anm.supervisor`, `mo.chandrapuri` and one `asha.<name>` per ASHA. The API is documented at `/docs` (development only).

With Docker instead (PostgreSQL, production settings): `cp .env.example .env`, replace the three `change-me` values, then `docker compose up --build`.

**Windows (PowerShell)**: `py -3.11 -m venv health-worker-backend\.venv`, then `health-worker-backend\.venv\Scripts\pip install -r health-worker-backend\requirements.txt`;
copy `health-worker-backend\.env.example` to `.env` and set `SECRET_KEY`, `DEVICE_HASH_SALT` (any 64 random hex characters), `AUTH_MODE=api_key`;
in `health-worker-backend`: `.venv\Scripts\alembic upgrade head` and `.venv\Scripts\python scripts\seed.py`.

## Reach it from phones on other networks

The phone allows plain http only to 127.0.0.1, so a remote server must be **https with a valid certificate**. Two ways, both tested
(details, named tunnels, sleep and troubleshooting: [`docs/PUBLIC_ACCESS.md`](docs/PUBLIC_ACCESS.md)):

1. **Cloudflare Tunnel from this computer (free).** Install `cloudflared` (`brew install cloudflared` / `winget install --id Cloudflare.cloudflared`), then

   ```bash
   scripts/start_public.sh
   ```

   It starts the server on 127.0.0.1, starts the tunnel, waits until `/health` answers **through the public address**, saves the address to
   `run/public_url.txt` and prints it (with a QR code). Stop with `scripts/stop_public.sh`. Windows: `scripts\start_public.ps1` / `stop_public.ps1`.
2. **Render (always on).** Push the repository, then in Render: *New → Blueprint* and pick it; `render.yaml` creates the Docker web service and
   PostgreSQL, generates `SECRET_KEY` and `DEVICE_HASH_SALT`, and asks for `ADMIN_PASSWORD`. Address: `https://asha-server.onrender.com` (or the name you chose).

## Point the phone app at the server

1. Website → **Phones & users** → *Generate a phone API key* for the ASHA who uses that phone (the phone demo mode uses worker `WRK-SYN-001`).
   The key is shown **once**; the server keeps only a hash. The page also shows the server address and its QR code.
2. Phone → **Settings** → *Server address*: the https address (tunnel or Render), exactly as shown; *API key*: the key. Tap **Sync**.
3. Switching between tunnel and Render = changing *Server address* (and a key created on that server). Unsynced changes stay in the phone's
   outbox and go to whichever server is set when the phone next syncs. A quick tunnel gets a **new** address on every start: update the phones,
   or use a named tunnel / Render for a fixed one. The website's **Settings** page always shows the current address and whether it answers.

## Reset the demo data

```bash
scripts/reset_demo.sh
```

Deletes everything (synced phone records, accounts, keys, audit) and reloads the synthetic data with new passwords. Docker: `docker compose down -v` then `up`.

## Tests

```bash
cd health-worker-backend && H5_DATA=../h5-pack-data .venv/bin/python -m pytest -q -o addopts=""    # 594 passed, 1 skipped
```

```bash
scripts/e2e.sh                     # browser tests: 7 passed (needs node and `npm install` in health-worker-web)
```

```bash
scripts/test_tunnel_scripts.sh     # start_public.sh/stop_public.sh against a local fake tunnel (no internet needed)
```

Load test (50 phones syncing at once): `health-worker-backend/scripts/load_test.py`. Results and everything else measured: [`docs/SERVER_DESIGN.md`](docs/SERVER_DESIGN.md).

## Known limits

- **Synthetic data only**; clinical content is unapproved. The map is a generated, made-up street layout (the pack has no coordinates); phone numbers are synthetic.
- The Cloudflare tunnel and Render were **not** exercised against the real internet from the build machine (its network blocks them). The scripts were
  tested against a local stand-in tunnel serving real HTTPS, and the Docker image/compose stack was built and run. `start_public.ps1` was not run (no PowerShell available).
- Questions asked **on the phone** run on the phone's own engine and never reach the server; only questions asked on the website, `POST /api/v1/ask`,
  or the older `/health-qa/query` and `/health-qa/rag` routes (outcomes only) appear in the escalations feed.
- The current app does not send how many changes are waiting on the phone or its version (it sends Dart's default User-Agent). The Phones page shows
  last seen, last sync, operations received/stored and unresolved conflicts/rejections instead.
- SQLite = one server process (writes are serialized). Worst-case burst, 50 phones syncing at the same instant 5 times: p95 5.9-7.0 s on SQLite
  (2 runs) and 3.8 s on PostgreSQL with 4 workers (4-CPU machine, database on the same machine); no errors, nothing stored twice. A single
  push takes ~6 ms when the server is not saturated. Rate limits are per process (in memory).
- PDF exports are English only (built-in font). Telugu covers the website's own labels; data values (names, items) stay as recorded.
- Website sessions are JWTs with a server-side version number (logout/deactivation ends them); there is no 2-factor sign-in and no password reset by email.
