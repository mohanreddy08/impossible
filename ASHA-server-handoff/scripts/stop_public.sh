#!/usr/bin/env bash
# Stops what scripts/start_public.sh started: the tunnel, the keep-awake helper and the backend (only if the script started it).
set -u
RUN="$(cd "$(dirname "$0")/.." && pwd)/run"
for name in tunnel awake backend; do
  f="$RUN/$name.pid"
  if [ -f "$f" ]; then
    pid="$(cat "$f")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null
      for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
      kill -9 "$pid" 2>/dev/null || true
      echo "stopped $name (pid $pid)"
    fi
    rm -f "$f"
  fi
done
rm -f "$RUN/public_url.txt"
echo "Public access is off. Phones keep working offline and will sync when the server is back."
