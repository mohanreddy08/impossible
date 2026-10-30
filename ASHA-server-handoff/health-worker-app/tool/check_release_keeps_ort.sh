#!/usr/bin/env bash
# After `flutter build apk --release`: fails if the code shrinker renamed ONNX Runtime classes (that crashes offline Telugu voice on a phone).
set -euo pipefail
APP="$(cd "$(dirname "$0")/.." && pwd)"
M="$APP/build/app/outputs/mapping/release/mapping.txt"
[ -f "$M" ] || { echo "no mapping file: build with 'flutter build apk --release' first"; exit 2; }
bad=$(grep -E '^ai\.onnxruntime\.[A-Za-z$]+ -> ' "$M" | awk '{n=$1; sub(/:$/,"",$3); if (n != $3) print n " -> " $3}')
if [ -n "$bad" ]; then echo "FAIL: ONNX Runtime classes were renamed by the shrinker:"; echo "$bad" | head; exit 1; fi
echo "OK: $(grep -cE '^ai\.onnxruntime\.[A-Za-z$]+ -> ' "$M") ONNX Runtime classes keep their names"
