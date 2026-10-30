#!/usr/bin/env bash
# Browser end-to-end tests: a fresh seeded server on a throw-away SQLite file, then the Playwright tests in health-worker-web/e2e.
#   scripts/e2e.sh                     (needs: backend venv, node, `npm i` in health-worker-web or a global playwright)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BE="$ROOT/health-worker-backend"
PY="${PY:-$BE/.venv/bin/python}"
PORT="${E2E_PORT:-8765}"
TMP="$(mktemp -d)"
export DATABASE_URL="sqlite:///$TMP/e2e.db" H5_DATA="$ROOT/h5-pack-data" AUTH_MODE=api_key \
       SECRET_KEY="e2e-only-$(date +%s)-0123456789abcdef0123456789" DEMO_PASSWORD="e2e-demo-password-1" ADMIN_PASSWORD="e2e-admin-password-1" \
       PUBLIC_URL_FILE="$TMP/public_url.txt"
cd "$BE"
"$PY" -m alembic upgrade head >/dev/null
"$PY" scripts/seed.py --credentials-file "$TMP/creds.txt" >/dev/null
"$PY" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" --log-level warning &
PID=$!
trap 'kill $PID 2>/dev/null; rm -rf "$TMP"' EXIT
for _ in $(seq 1 40); do curl -fs "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 0.5; done
cd "$ROOT/health-worker-web"
BASE_URL="http://127.0.0.1:$PORT" E2E_USER=anm.supervisor E2E_PASSWORD="$DEMO_PASSWORD" node --test --test-concurrency=1 e2e/site.test.js
