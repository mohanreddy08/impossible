#!/usr/bin/env bash
# Samples the app's memory once a second while you run the Voice Test, using
#   adb shell dumpsys meminfo in.healthcompanion.health_companion
# Each line of the output file is: phone_epoch_ms,total_pss_kb,total_rss_kb  (the phone's own clock, the same clock the app stamps its CSV with).
# Start it BEFORE the first sentence, press Ctrl-C when you are done. Peak RAM per engine is worked out by tool/voice_test_summary.py.
#
#   tool/voice_test_ram.sh [out.csv]          (default: voice_test_ram.csv)
set -u
PKG=in.healthcompanion.health_companion
OUT=${1:-voice_test_ram.csv}
SERIAL_ARGS=()
[ -n "${ANDROID_SERIAL:-}" ] && SERIAL_ARGS=(-s "$ANDROID_SERIAL")
echo "phone_epoch_ms,total_pss_kb,total_rss_kb" > "$OUT"
peak=0
trap 'echo; echo "peak total PSS: $((peak/1024)) MB   samples: $OUT"; exit 0' INT TERM
while true; do
  line=$(adb ${SERIAL_ARGS[@]+"${SERIAL_ARGS[@]}"} shell "date +%s%3N; dumpsys meminfo $PKG | grep 'TOTAL PSS'" </dev/null 2>/dev/null | tr -d '\r' | tr '\n' ' ')
  ts=$(echo "$line" | awk '{print $1}')
  pss=$(echo "$line" | sed -n 's/.*TOTAL PSS: *\([0-9]*\).*/\1/p')
  rss=$(echo "$line" | sed -n 's/.*TOTAL RSS: *\([0-9]*\).*/\1/p')
  if [ -n "$ts" ] && [ -n "$pss" ]; then
    echo "$ts,$pss,${rss:-0}" >> "$OUT"
    [ "$pss" -gt "$peak" ] && peak=$pss
    printf '\r%s MB now, %s MB peak   ' "$((pss/1024))" "$((peak/1024))"
  fi
  sleep 1
done
