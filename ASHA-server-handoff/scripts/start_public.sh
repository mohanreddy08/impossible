#!/usr/bin/env bash
# Make this computer's ASHA server reachable from phones on ANY network (mobile data included) over HTTPS, via a Cloudflare Tunnel.
#
#   scripts/start_public.sh            quick tunnel: free, no account, NEW random https://<words>.trycloudflare.com address every start
#   TUNNEL_NAME=asha TUNNEL_HOSTNAME=asha.example.org scripts/start_public.sh
#                                      named tunnel on your own domain: the address never changes (one-time setup: docs/PUBLIC_ACCESS.md)
#   scripts/stop_public.sh             stops the tunnel, the server and the keep-awake helper
#
# What it does: starts the backend on 127.0.0.1:${PORT:-8000} (never on the LAN), starts cloudflared, waits until /health answers
# THROUGH the public address, writes that address to run/public_url.txt (the website's Settings page and QR code read it) and prints it.
# Works on macOS (bash 3.2) and Linux; Windows: scripts/start_public.ps1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BE="$ROOT/health-worker-backend"
RUN="$ROOT/run"
PORT="${PORT:-8000}"
WAIT="${PUBLIC_WAIT_SECONDS:-120}"
mkdir -p "$RUN"
say() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

PY="${PY:-}"
if [ -z "$PY" ]; then
  if [ -x "$BE/.venv/bin/python" ]; then PY="$BE/.venv/bin/python"; else PY="$(command -v python3 || true)"; fi
fi
[ -n "$PY" ] || die "Python not found. Run scripts/dev_setup.sh first."
CLOUDFLARED="${CLOUDFLARED:-$(command -v cloudflared || true)}"
if [ -z "$CLOUDFLARED" ]; then
  die "cloudflared is not installed.
  macOS:   brew install cloudflared
  Linux:   https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/  (e.g. the .deb or the single binary)
  Windows: use scripts/start_public.ps1 (winget install --id Cloudflare.cloudflared)"
fi
[ -f "$BE/.env" ] || die "No $BE/.env yet. Run scripts/dev_setup.sh (it creates one with random secrets)."

# A public server must have authentication on.
cd "$BE"
MODE="$("$PY" -c 'from app.core.config import get_settings as g; print(g().auth_mode)')"
[ "$MODE" = "api_key" ] || die "AUTH_MODE is '$MODE' in health-worker-backend/.env. Set AUTH_MODE=api_key before exposing the server to the internet."

# ---------------------------------------------------------------- 1. backend (only on 127.0.0.1; the tunnel is the way in)
if curl -fsS --max-time 3 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
  say "Backend already answering on 127.0.0.1:$PORT (reusing it)."
else
  say "Starting the backend on 127.0.0.1:$PORT ..."
  # --proxy-headers: trust X-Forwarded-For/-Proto from cloudflared (on this machine only) so rate limits see each phone's address
  # and session cookies are marked Secure behind https. One worker: SQLite has a single writer (use PostgreSQL to scale out).
  nohup "$PY" -m uvicorn app.main:app --host 127.0.0.1 --port "$PORT" --proxy-headers --forwarded-allow-ips 127.0.0.1 \
    >"$RUN/backend.log" 2>&1 &
  echo $! >"$RUN/backend.pid"
  ok=""
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then ok=1; break; fi
    kill -0 "$(cat "$RUN/backend.pid")" 2>/dev/null || break
    sleep 0.5
  done
  [ -n "$ok" ] || { tail -20 "$RUN/backend.log" >&2; die "the backend did not start (log: run/backend.log)"; }
fi

# ---------------------------------------------------------------- 2. tunnel
if [ -f "$RUN/tunnel.pid" ] && kill -0 "$(cat "$RUN/tunnel.pid")" 2>/dev/null; then
  say "Stopping the previous tunnel first."
  kill "$(cat "$RUN/tunnel.pid")" 2>/dev/null || true
  sleep 1
fi
rm -f "$RUN/public_url.txt"
: >"$RUN/tunnel.log"
if [ -n "${TUNNEL_NAME:-}" ]; then
  [ -n "${TUNNEL_HOSTNAME:-}" ] || die "TUNNEL_NAME is set: also set TUNNEL_HOSTNAME (e.g. asha.example.org)"
  say "Starting named tunnel '$TUNNEL_NAME' for https://$TUNNEL_HOSTNAME ..."
  nohup "$CLOUDFLARED" tunnel --no-autoupdate run --url "http://127.0.0.1:$PORT" "$TUNNEL_NAME" >"$RUN/tunnel.log" 2>&1 &
  echo $! >"$RUN/tunnel.pid"
  URL="https://$TUNNEL_HOSTNAME"
else
  say "Starting a quick tunnel (free, no account; the address changes every time) ..."
  nohup "$CLOUDFLARED" tunnel --no-autoupdate --url "http://127.0.0.1:$PORT" >"$RUN/tunnel.log" 2>&1 &
  echo $! >"$RUN/tunnel.pid"
  URL=""
  for _ in $(seq 1 60); do
    # the log also mentions https://api.trycloudflare.com (the service it asks for an address): skip that one
    URL="$(grep -Eo 'https://[a-z0-9-]+\.trycloudflare\.com' "$RUN/tunnel.log" 2>/dev/null | grep -v '^https://api\.' | head -n 1 || true)"
    [ -n "$URL" ] && break
    kill -0 "$(cat "$RUN/tunnel.pid")" 2>/dev/null || break
    sleep 1
  done
  [ -n "$URL" ] || { tail -20 "$RUN/tunnel.log" >&2; die "cloudflared did not report an address (log: run/tunnel.log). Is outbound internet allowed?"; }
fi

# ---------------------------------------------------------------- 3. wait until it answers from the internet
say "Waiting for $URL/health to answer through the tunnel (new quick-tunnel names can take ~10-30 s to resolve) ..."
# TUNNEL_CURL_OPTS: extra curl options, for testing the script without the internet (see scripts/test_tunnel_scripts.sh)
# shellcheck disable=SC2086
ok=""
t0=$(date +%s)
while [ $(( $(date +%s) - t0 )) -lt "$WAIT" ]; do
  body="$(curl -fsS --max-time 6 ${TUNNEL_CURL_OPTS:-} "$URL/health" 2>/dev/null || true)"
  case "$body" in *'"status":"ok"'*) ok=1; break ;; esac
  kill -0 "$(cat "$RUN/tunnel.pid")" 2>/dev/null || { tail -20 "$RUN/tunnel.log" >&2; die "cloudflared exited (log: run/tunnel.log)"; }
  sleep 2
done
[ -n "$ok" ] || die "$URL/health did not answer within ${WAIT}s. The tunnel is still running; check run/tunnel.log, then retry."
printf '%s\n' "$URL" >"$RUN/public_url.txt"

# ---------------------------------------------------------------- 4. keep the computer awake while serving
if [ "$(uname)" = "Darwin" ] && command -v caffeinate >/dev/null 2>&1; then
  nohup caffeinate -dimsu -w "$(cat "$RUN/tunnel.pid")" >/dev/null 2>&1 &
  echo $! >"$RUN/awake.pid"
  AWAKE="caffeinate is keeping this Mac awake while the tunnel runs (lid open, on power)."
elif command -v systemd-inhibit >/dev/null 2>&1; then
  nohup systemd-inhibit --what=sleep:idle --why="ASHA server tunnel" --mode=block tail --pid="$(cat "$RUN/tunnel.pid")" -f /dev/null >/dev/null 2>&1 &
  echo $! >"$RUN/awake.pid"
  AWAKE="systemd-inhibit is blocking sleep while the tunnel runs."
else
  AWAKE="Keep this computer awake and plugged in (see docs/PUBLIC_ACCESS.md, 'Sleep')."
fi

say ""
say "================================================================"
say " Server address for the phone app (Settings > Server address):"
say ""
say "     $URL"
say ""
say " Then paste the phone's API key (website > Phones & users > Generate key)."
say " Website for supervisors: $URL   (also http://127.0.0.1:$PORT on this computer)"
[ -z "${TUNNEL_NAME:-}" ] && say " NOTE: a quick tunnel gets a NEW address every start: update the phones (or use a named tunnel / Render)."
say " $AWAKE"
say " Stop: scripts/stop_public.sh"
say "================================================================"
"$PY" -c 'import sys, segno; segno.make(sys.argv[1], error="m").terminal(compact=True)' "$URL" 2>/dev/null || true
