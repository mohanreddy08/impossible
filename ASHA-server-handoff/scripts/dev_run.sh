#!/usr/bin/env bash
# Local server for this computer only: http://127.0.0.1:8000 (website) and /docs (API). For phones on other networks: scripts/start_public.sh
set -euo pipefail
cd "$(cd "$(dirname "$0")/.." && pwd)/health-worker-backend"
exec .venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port "${PORT:-8000}" --proxy-headers --forwarded-allow-ips 127.0.0.1
