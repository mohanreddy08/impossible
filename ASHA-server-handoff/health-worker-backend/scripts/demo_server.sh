#!/usr/bin/env bash
# One-command DEMO server on this Mac: the ASHA backend + a small local LLM (Ollama) + the offline Telugu voice pack, for the phone app.
#
#   scripts/demo_server.sh start    start everything, link connected phones over USB (adb reverse), print what to type on the phone
#   scripts/demo_server.sh status   what is running
#   scripts/demo_server.sh check    end-to-end self test (health, login, sync data, Telugu pack, AI explanation)
#   scripts/demo_server.sh stop     stop what this script started
#   scripts/demo_server.sh reset    stop, delete the demo database (pristine synthetic data again), start
#
# Everything is a DEMO: synthetic data, test keys (demo/demo.env, created on first run), one laptop. It uses its OWN Ollama on a separate
# port, so an Ollama you already run (and the models it keeps loaded) is not touched. Change the model with DEMO_LLM_MODEL in demo/demo.env.
set -uo pipefail
BE="$(cd "$(dirname "$0")/.." && pwd)"
DEMO="$BE/demo"; RUN="$DEMO/run"; mkdir -p "$RUN"

if [ ! -f "$DEMO/demo.env" ]; then
  rnd() { LC_ALL=C tr -dc 'a-z0-9' </dev/urandom | head -c 24; }
  cat >"$DEMO/demo.env" <<EOF
# Demo settings (test values only; this file is not for production). Created on first run.
DEMO_PORT=8800
DEMO_OLLAMA_PORT=11500
# qwen3:8b (5 GB): the only installed model that writes correct Telugu (measured: 18/18 on the Telugu test set; gemma3:4b 2/18; qwen3:4b unusable).
# It is slow (about 7 s for one Telugu sentence), so the server answers from the approved passage itself whenever the passage is short.
DEMO_LLM_MODEL=qwen3:8b
# multilingual embedding model for finding the passages (Telugu, English, mixed): Recall@1 17/18 on the Telugu test set
DEMO_EMBED_MODEL=bge-m3
DEMO_REFERENCE_DATE=2026-10-13
# false: Telugu questions are not sent to the model (small models write poor Telugu); the phone shows the approved Telugu text instead
DEMO_LLM_TELUGU=false
DEMO_WORKER_KEY=demo-worker-$(rnd)
DEMO_ADMIN_KEY=demo-admin-$(rnd)
DEMO_HOSPITAL_KEY=demo-hospital-$(rnd)
EOF
  chmod 600 "$DEMO/demo.env"
fi
# shellcheck disable=SC1091
. "$DEMO/demo.env"

BASE="http://127.0.0.1:$DEMO_PORT"
OLLAMA_HOST_PORT="127.0.0.1:$DEMO_OLLAMA_PORT"
PY="$BE/.venv/bin/python"; UVICORN="$BE/.venv/bin/uvicorn"; ALEMBIC="$BE/.venv/bin/alembic"
say() { printf '%s\n' "$*"; }
up() { curl -fs -m 2 "$1" >/dev/null 2>&1; }
alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

phones() { command -v adb >/dev/null 2>&1 && adb devices | awk 'NR>1 && $2=="device"{print $1}'; }

link_phones() {
  local d n=0
  for d in $(phones); do adb -s "$d" reverse "tcp:$DEMO_PORT" "tcp:$DEMO_PORT" >/dev/null 2>&1 && n=$((n+1)); done
  say "phones linked over USB: $n"
}

start_ollama() {
  command -v ollama >/dev/null 2>&1 || { say "! ollama is not installed: the server still runs, the phone explains answers itself"; return 0; }
  if ! up "http://$OLLAMA_HOST_PORT/api/tags"; then
    OLLAMA_HOST="$OLLAMA_HOST_PORT" OLLAMA_KEEP_ALIVE=30m nohup ollama serve >"$RUN/ollama.log" 2>&1 &
    echo $! >"$RUN/ollama.pid"
    for _ in $(seq 1 30); do up "http://$OLLAMA_HOST_PORT/api/tags" && break; sleep 0.5; done
  fi
  up "http://$OLLAMA_HOST_PORT/api/tags" || { say "! could not start the demo Ollama (see $RUN/ollama.log)"; return 0; }
  local m
  for m in "$DEMO_LLM_MODEL" "$DEMO_EMBED_MODEL"; do
    if ! OLLAMA_HOST="$OLLAMA_HOST_PORT" ollama list 2>/dev/null | awk '{print $1}' | grep -qE "^$m(:latest)?$"; then
      say "downloading model $m (once) ..."; OLLAMA_HOST="$OLLAMA_HOST_PORT" ollama pull "$m" || say "! model download failed: $m"
    fi
  done
  # load the embedding model now (every question needs it). The LLM is loaded on first use (set DEMO_WARM_LLM=true to load it now, 5 GB):
  # the server answers from the approved passage itself whenever the passage is short, so the sample data rarely needs it.
  curl -s -m 120 "http://$OLLAMA_HOST_PORT/api/embed" -d "{\"model\":\"$DEMO_EMBED_MODEL\",\"input\":\"hi\",\"keep_alive\":\"30m\"}" >/dev/null 2>&1 \
    && say "embedding model ready: $DEMO_EMBED_MODEL" || say "! embedding warm-up failed"
  if [ "${DEMO_WARM_LLM:-false}" = true ]; then
    curl -s -m 180 "http://$OLLAMA_HOST_PORT/api/generate" -d "{\"model\":\"$DEMO_LLM_MODEL\",\"prompt\":\"hi\",\"stream\":false,\"keep_alive\":\"30m\",\"think\":false,\"options\":{\"num_predict\":1}}" >/dev/null 2>&1 \
      && say "LLM ready: $DEMO_LLM_MODEL" || say "! LLM warm-up failed"
  fi
}

init_db() {
  if [ ! -f "$DEMO/demo.db" ]; then
    say "creating the demo database (synthetic data) ..."
    ( cd "$BE" && DATABASE_URL="sqlite:///$DEMO/demo.db" "$ALEMBIC" upgrade head >/dev/null 2>&1 && \
      DATABASE_URL="sqlite:///$DEMO/demo.db" "$PY" scripts/import_datasets.py >/dev/null 2>&1 ) || { say "! database setup failed"; return 1; }
  fi
  # the SAMPLE protocol passages (English + Telugu, marked TEST_FIXTURE_ONLY) for the server-side RAG; real documents go through import_protocols.py
  ( cd "$BE" && DATABASE_URL="sqlite:///$DEMO/demo.db" "$PY" scripts/load_sample_protocol.py 2>&1 | tail -1 ) || true
}

start_api() {
  if alive "$RUN/api.pid" && up "$BASE/health"; then say "server already running on $BASE"; return 0; fi
  # exec: the recorded pid is the server itself (not a wrapper shell), so "stop" really stops it
  ( cd "$BE" && exec nohup env \
    DATABASE_URL="sqlite:///$DEMO/demo.db" AUTH_MODE=api_key APP_ENV=development REFERENCE_DATE="$DEMO_REFERENCE_DATE" \
    DEVICE_HASH_SALT=demo-salt-not-for-production \
    API_KEYS="worker|WRK-SYN-001|$DEMO_WORKER_KEY;admin||$DEMO_ADMIN_KEY;hospital||$DEMO_HOSPITAL_KEY" \
    LLM_PROVIDER=ollama LLM_BASE_URL="http://$OLLAMA_HOST_PORT" LLM_MODEL="$DEMO_LLM_MODEL" LLM_TIMEOUT_SECONDS=8.5 \
    RAG_EMBED_MODEL="$DEMO_EMBED_MODEL" RAG_CACHE_PATH="$DEMO/rag_vectors.json" ELIGIBLE_VERIFICATION_STATUSES=VERIFIED,TEST_FIXTURE_ONLY \
    LLM_RATE_LIMIT_PER_MINUTE=60 LLM_TELUGU_EXPLAIN="${DEMO_LLM_TELUGU:-false}" SPEECH_MODEL_DIR="$BE/models/te-asr" \
    "$UVICORN" app.main:app --host 0.0.0.0 --port "$DEMO_PORT" --log-level warning ) >"$RUN/api.log" 2>&1 </dev/null &
  echo $! >"$RUN/api.pid"
  for _ in $(seq 1 40); do up "$BASE/health" && break; sleep 0.5; done
  up "$BASE/health" && say "server up: $BASE" || { say "! server did not start (see $RUN/api.log)"; return 1; }
  # first question embeds the whole passage library (then cached in demo/rag_vectors.json): do it now, not on stage
  curl -s -m 90 -X POST -H "X-API-Key: $DEMO_WORKER_KEY" -H 'content-type: application/json' "$BASE/api/v1/health-qa/rag" -d '{"question":"warm up"}' >/dev/null 2>&1 \
    && say "retrieval index ready" || say "! retrieval warm-up failed"
}

cmd_start() {
  [ -x "$PY" ] || { say "! backend virtualenv missing: $BE/.venv"; exit 1; }
  [ -f "$BE/models/te-asr/manifest.json" ] || say "! Telugu voice pack not found in models/te-asr (run scripts/build_telugu_asr_pack.py); everything else works"
  init_db || exit 1
  start_ollama
  start_api || exit 1
  link_phones
  cat <<EOF

On the phone (Settings):
   Server address   http://127.0.0.1:$DEMO_PORT        (USB cable; this script already ran adb reverse)
   Access key       the DEMO_WORKER_KEY line in $DEMO/demo.env
   Online AI help   ON  (off = the phone explains answers itself and never calls the LLM)
   Telugu voice     Settings -> "Download Telugu voice" (once per phone)
Run "$0 check" for a self test.
EOF
}

cmd_stop() {
  local f
  for f in api ollama; do
    if alive "$RUN/$f.pid"; then kill "$(cat "$RUN/$f.pid")" 2>/dev/null; say "stopped $f"; fi
    rm -f "$RUN/$f.pid"
  done
  local d; for d in $(phones); do adb -s "$d" reverse --remove "tcp:$DEMO_PORT" >/dev/null 2>&1; done
}

cmd_status() {
  up "$BASE/health" && say "server   : running ($BASE)" || say "server   : stopped"
  up "http://$OLLAMA_HOST_PORT/api/tags" && say "LLM      : running ($DEMO_LLM_MODEL on port $DEMO_OLLAMA_PORT)" || say "LLM      : stopped"
  [ -f "$DEMO/demo.db" ] && say "database : $DEMO/demo.db" || say "database : not created yet"
  say "phones   : $(phones | tr '\n' ' ')"
}

cmd_check() {
  local ok=0 bad=0
  t() { if eval "$2" >/dev/null 2>&1; then say "  ok    $1"; ok=$((ok+1)); else say "  FAIL  $1"; bad=$((bad+1)); fi; }
  say "demo self test ($BASE)"
  t "server is up"                       "curl -fs -m 3 $BASE/health"
  t "wrong key is refused (401)"         "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -m 3 -H 'X-API-Key: nope' $BASE/api/v1/households?limit=1)\" = 401 ]"
  t "worker key sees households"         "curl -fs -m 5 -H \"X-API-Key: $DEMO_WORKER_KEY\" '$BASE/api/v1/households?limit=1' | grep -q household_id"
  t "Telugu voice pack is served"        "curl -fs -m 5 -H \"X-API-Key: $DEMO_WORKER_KEY\" $BASE/api/v1/speech-models/te | grep -q model.int8.onnx"
  t "LLM is up"                          "curl -fs -m 3 http://$OLLAMA_HOST_PORT/api/tags | grep -q '$DEMO_LLM_MODEL'"
  rag() { curl -s -m 12 -X POST -H "X-API-Key: $DEMO_WORKER_KEY" -H 'content-type: application/json' $BASE/api/v1/health-qa/rag -d "{\"question\":\"$1\"}"; }
  t "embedding model is installed"       "curl -fs -m 3 http://$OLLAMA_HOST_PORT/api/tags | grep -q '$DEMO_EMBED_MODEL'"
  t "RAG finds the Telugu hand-washing text"  "rag 'చేతులు ఎలా కడుక్కోవాలి' | grep -q 'hand-washing'"
  t "RAG finds pregnancy danger signs (Telugu)" "rag 'గర్భిణీ స్త్రీలో ప్రమాద సంకేతాలు ఏమిటి' | grep -q 'SAMPLE-PREG-DANGER'"
  t "RAG says no approved text for malaria (Telugu)" "rag 'మలేరియాకు చికిత్స ఏమిటి' | grep -q NO_APPROVED_TEXT"
  t "a danger sign is escalated, not answered" "rag 'newborn baby is not feeding properly' | grep -q ESCALATION_REQUIRED"
  say "  $ok passed, $bad failed"; [ "$bad" = 0 ]
}

case "${1:-}" in
  start) cmd_start ;;
  stop) cmd_stop ;;
  status) cmd_status ;;
  check) cmd_check ;;
  reset) cmd_stop; rm -f "$DEMO/demo.db"; cmd_start ;;
  *) sed -n 2,13p "$0"; exit 2 ;;
esac
