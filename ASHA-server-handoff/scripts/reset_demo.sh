#!/usr/bin/env bash
# Wipe EVERYTHING (synced phone data, accounts, keys, audit) and reload the synthetic demo data with new passwords.
set -euo pipefail
read -r -p "This deletes all data on this server and creates new accounts. Type RESET to continue: " a
[ "$a" = "RESET" ] || { echo "cancelled"; exit 1; }
cd "$(cd "$(dirname "$0")/.." && pwd)/health-worker-backend"
.venv/bin/alembic upgrade head
.venv/bin/python scripts/seed.py --reset
