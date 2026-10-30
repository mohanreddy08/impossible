#!/bin/sh
# Container start: migrate, load the synthetic demo data once (only into an empty database), serve.
set -e
cd /app/health-worker-backend
python -m alembic upgrade head
if [ "${SEED_ON_START:-true}" = "true" ]; then
  python scripts/seed.py --if-empty --credentials-file /app/run/demo_credentials.txt
fi
# Several workers are fine with PostgreSQL. With SQLite (DATABASE_URL=sqlite:...) keep WEB_CONCURRENCY=1: one writer process.
# --proxy-headers: Render / a reverse proxy terminates HTTPS and sets X-Forwarded-For/-Proto.
exec python -m uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" --workers "${WEB_CONCURRENCY:-2}" \
     --proxy-headers --forwarded-allow-ips "${FORWARDED_ALLOW_IPS:-*}"
