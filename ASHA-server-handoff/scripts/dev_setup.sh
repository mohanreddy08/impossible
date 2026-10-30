#!/usr/bin/env bash
# One-time local setup: Python venv + dependencies, a .env with fresh random secrets, database migrations, synthetic demo data + accounts.
#   scripts/dev_setup.sh            (again with --reset to wipe and reload the demo data: scripts/dev_setup.sh --reset)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BE="$ROOT/health-worker-backend"
PYBIN="${PYTHON:-$(command -v python3.11 || command -v python3)}"
"$PYBIN" -c 'import sys; assert sys.version_info >= (3, 11), "Python 3.11+ needed"' || exit 1
cd "$BE"
[ -d .venv ] || "$PYBIN" -m venv .venv
.venv/bin/pip install -q -U pip
.venv/bin/pip install -q -r requirements-dev.txt
if [ ! -f .env ]; then
  rnd() { .venv/bin/python -c 'import secrets; print(secrets.token_hex(32))'; }
  sed -e "s|^SECRET_KEY=.*|SECRET_KEY=$(rnd)|" -e "s|^DEVICE_HASH_SALT=.*|DEVICE_HASH_SALT=$(rnd)|" -e "s|^AUTH_MODE=.*|AUTH_MODE=api_key|" \
      -e "s|^H5_DATA=.*|H5_DATA=../h5-pack-data|" .env.example > .env
  chmod 600 .env
  echo "created health-worker-backend/.env with random SECRET_KEY and DEVICE_HASH_SALT (never commit it)"
fi
.venv/bin/alembic upgrade head
if [ "${1:-}" = "--reset" ]; then .venv/bin/python scripts/seed.py --reset; else .venv/bin/python scripts/seed.py --if-empty; fi
echo "Setup done. Start the server: scripts/dev_run.sh   (passwords above are also in run/demo_credentials.txt)"
