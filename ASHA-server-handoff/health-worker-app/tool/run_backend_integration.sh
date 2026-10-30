#!/usr/bin/env bash
# Starts the REAL FastAPI backend on a temporary database (loaded from the project's synthetic datasets, API-key auth ON),
# runs the app's integration tests against it, then stops the server and deletes the database.
# Each test file gets its OWN fresh server and database: the files change server data (visits, referrals), and running
# them against one shared server made their results depend on each other.
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)"
BE="$APP/../health-worker-backend"
PORT="${PORT:-8791}"
export REFERENCE_DATE=2026-10-13 AUTH_MODE=api_key APP_ENV=development DEVICE_HASH_SALT=it-salt-xxxxxxxx
export API_KEYS="worker|WRK-SYN-001|it-worker-key;admin||it-admin-key;hospital||it-hosp-key"

run_one() {
  local file="$1"; shift
  local tmp; tmp="$(mktemp -d)"
  export DATABASE_URL="sqlite:///$tmp/it.db"
  ( cd "$BE" && .venv/bin/alembic upgrade head >/dev/null && .venv/bin/python scripts/import_datasets.py >/dev/null )
  ( cd "$BE" && exec .venv/bin/uvicorn app.main:app --port "$PORT" --log-level warning ) &
  local srv=$!
  for i in $(seq 1 40); do curl -sf "http://127.0.0.1:$PORT/health" >/dev/null && break; sleep 0.5; done
  local rc=0
  ( cd "$APP" && BACKEND_URL="http://127.0.0.1:$PORT" flutter test "$file" "$@" ) || rc=$?
  kill $srv 2>/dev/null || true
  wait $srv 2>/dev/null || true
  rm -rf "$tmp"
  return $rc
}

status=0
for f in "$APP"/test/integration/*_test.dart; do
  echo "=== $(basename "$f")"
  run_one "$f" "$@" || status=1
done
exit $status
