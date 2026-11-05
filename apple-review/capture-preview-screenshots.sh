#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/apple-review/screenshots"
SIMULATOR_ID="${1:-booted}"
FLUTTER_BIN="${FLUTTER_BIN:-$(command -v flutter || true)}"

if [[ -z "$FLUTTER_BIN" && -x "$HOME/flutter/bin/flutter" ]]; then
  FLUTTER_BIN="$HOME/flutter/bin/flutter"
fi
if [[ -z "$FLUTTER_BIN" || ! -x "$FLUTTER_BIN" ]]; then
  echo "Set FLUTTER_BIN to a Flutter executable." >&2
  exit 2
fi

mkdir -p "$OUTPUT"
LOG="$(mktemp -t tevel-preview.XXXXXX)"
cleanup() {
  xcrun simctl status_bar "$SIMULATOR_ID" override --clear >/dev/null 2>&1 || true
  rm -f "$LOG"
}
trap cleanup EXIT

xcrun simctl status_bar "$SIMULATOR_ID" override \
  --time '9:41' --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

"$FLUTTER_BIN" test -d "$SIMULATOR_ID" \
  "$ROOT/integration_test/design_preview_test.dart" --reporter expanded >"$LOG" 2>&1 &
TEST_PID=$!
LAST_SHOT=""

while kill -0 "$TEST_PID" 2>/dev/null; do
  SHOT="$(sed -n 's/.*DESIGN_SHOT:\([a-z-]*\).*/\1/p' "$LOG" | tail -n 1)"
  if [[ -n "$SHOT" && "$SHOT" != "$LAST_SHOT" ]]; then
    sleep 0.25
    xcrun simctl io "$SIMULATOR_ID" screenshot "$OUTPUT/$SHOT.png" >/dev/null
    echo "Captured $OUTPUT/$SHOT.png"
    LAST_SHOT="$SHOT"
  fi
  sleep 0.2
done

wait "$TEST_PID"
cat "$LOG"
