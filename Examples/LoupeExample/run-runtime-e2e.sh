#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-}"
LAUNCH_TIMEOUT="${LOUPE_LAUNCH_TIMEOUT:-30}"

cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh

run_with_timeout() {
  local seconds="$1"
  shift
  "$@" &
  local pid=$!
  for _ in $(seq 1 "$((seconds * 10))"); do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid"
      return
    fi
    sleep 0.1
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  echo "error: command timed out after ${seconds}s: $*" >&2
  return 124
}

configure_loupe_ios_verification
DEVICE="$(loupe_ios_verification_device)"
prepare_loupe_ios_preferences

terminate_app() {
  xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 &
  local pid=$!
  for _ in {1..50}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      wait "$pid" >/dev/null 2>&1 || true
      return
    fi
    sleep 0.1
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

boot_loupe_ios_verification_device
swift build
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,id=$DEVICE"

terminate_app
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"

LAUNCH_ARGUMENTS=(
  --device "$DEVICE"
  --bundle-id dev.loupe.example
  --inject
  --timeout "$LAUNCH_TIMEOUT"
)
if [[ -n "$PORT" ]]; then
  LAUNCH_ARGUMENTS+=(--env "LOUPE_PORT=$PORT")
fi
LAUNCH_OUTPUT="$(.build/debug/loupe app launch "${LAUNCH_ARGUMENTS[@]}")"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$LAUNCH_OUTPUT" | tail -1)"
if [[ -z "$HOST" ]]; then
  echo "error: loupe app launch did not report a runtime host" >&2
  echo "$LAUNCH_OUTPUT" >&2
  exit 1
fi

sleep 2

SNAPSHOT_PATH="/tmp/loupe-runtime-snapshot.json"
SCREENSHOT_PATH="/tmp/loupe-runtime-screen.png"
RUNTIME_PATH="/tmp/loupe-runtime-state.json"

fetch_snapshot() {
  .build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH"
}

curl -sS "$HOST/health" | grep -q LoupeKit
.build/debug/loupe app info --host "$HOST" --udid "$DEVICE" > "$RUNTIME_PATH"
grep -q '"simulatorUDID"' "$RUNTIME_PATH"
fetch_snapshot
grep -q '"uikit"' "$SNAPSHOT_PATH"
grep -q '"accessibility"' "$SNAPSHOT_PATH"
read -r WIDTH HEIGHT < <(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  size = snapshot.fetch("screen").fetch("size")
  puts [size.fetch("width"), size.fetch("height")].join(" ")
' "$SNAPSHOT_PATH")

.build/debug/loupe act drag \
  --udid "$DEVICE" \
  --from "$(ruby -e 'puts (ARGV.fetch(0).to_f / 2).round' "$WIDTH"),$(ruby -e 'puts (ARGV.fetch(0).to_f * 0.80).round' "$HEIGHT")" \
  --to "$(ruby -e 'puts (ARGV.fetch(0).to_f / 2).round' "$WIDTH"),$(ruby -e 'puts (ARGV.fetch(0).to_f * 0.35).round' "$HEIGHT")" \
  --duration 0.4 \
  --timeout 8

sleep 1

fetch_snapshot
.build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id example.customerList >/tmp/loupe-runtime-list-query.json

.build/debug/loupe ui screenshot \
  --udid "$DEVICE" \
  --output "$SCREENSHOT_PATH"

echo "runtime E2E smoke passed"
echo "runtime: $RUNTIME_PATH"
echo "snapshot: $SNAPSHOT_PATH"
echo "screenshot: $SCREENSHOT_PATH"
