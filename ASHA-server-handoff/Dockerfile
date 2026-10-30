# ASHA server: API + supervisor website + h5 engine in one image. Data: PostgreSQL (DATABASE_URL), or SQLite for a single box.
FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 \
    H5_DATA=/app/h5-pack-data DATASET_DIR=/app/health-worker-datasets WEB_DIR=/app/health-worker-web PUBLIC_URL_FILE=/app/run/public_url.txt \
    APP_ENV=production AUTH_MODE=api_key DOCS_ENABLED=false PORT=8000

WORKDIR /app/health-worker-backend
COPY health-worker-backend/requirements.txt health-worker-backend/requirements-postgres.txt ./
# Behind a TLS-inspecting proxy (some office/university networks): docker build --secret id=extra_ca,src=/path/to/proxy-ca.pem .
RUN --mount=type=secret,id=extra_ca,required=false \
    if [ -f /run/secrets/extra_ca ]; then export PIP_CERT=/run/secrets/extra_ca; fi; pip install -r requirements-postgres.txt

# only what the server needs: no phone app, no tests' golden files, no local databases or .env
COPY health-worker-backend/ ./
COPY health-worker-web/ /app/health-worker-web/
COPY h5-pack-data/ /app/h5-pack-data/
COPY health-worker-datasets/ /app/health-worker-datasets/
COPY scripts/docker-entrypoint.sh /app/docker-entrypoint.sh

RUN rm -rf .env .venv *.db app/tests && useradd --system --uid 10001 asha && mkdir -p /app/run && chown -R asha /app/run && chmod +x /app/docker-entrypoint.sh
USER asha
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD python -c "import os,urllib.request,json; r=urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT','8000'), timeout=4); assert json.load(r)['status']=='ok'"
ENTRYPOINT ["/app/docker-entrypoint.sh"]
