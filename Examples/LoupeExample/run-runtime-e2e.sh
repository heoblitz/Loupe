#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-}"

cd "$ROOT_DIR"

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

simctl_list_timeout() {
  ruby -e 'value = ENV.fetch("LOUPE_SIMCTL_LIST_TIMEOUT", "60").to_f; puts(value.positive? ? value.to_i : 60)'
}

booted_udid() {
  local list_path="/tmp/loupe-runtime-booted-devices.json"
  run_with_timeout "$(simctl_list_timeout)" xcrun simctl list devices booted --json >"$list_path"
  ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("iPhone") }
    puts booted && booted["udid"]
  ' <"$list_path"
}

DEVICE="${LOUPE_DEVICE:-$(booted_udid)}"
if [[ -z "$DEVICE" ]]; then
  DEVICES_PATH="/tmp/loupe-runtime-available-devices.txt"
  run_with_timeout "$(simctl_list_timeout)" xcrun simctl list devices available >"$DEVICES_PATH"
  FIRST_DEVICE="$(awk -F '[()]' '/iPhone/ { print $2; exit }' "$DEVICES_PATH")"
  if [[ -z "$FIRST_DEVICE" ]]; then
    echo "error: no available iPhone simulator found" >&2
    exit 1
  fi
  xcrun simctl boot "$FIRST_DEVICE" >/dev/null 2>&1 || true
  DEVICE="$FIRST_DEVICE"
fi

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

assert_device_ready() {
  local log_path="/tmp/loupe-runtime-bootstatus.log"
  if run_with_timeout 90 xcrun simctl bootstatus "$DEVICE" -b >"$log_path" 2>&1; then
    return
  fi

  if run_with_timeout 5 xcrun simctl spawn "$DEVICE" launchctl print system >/dev/null 2>&1; then
    echo "warning: bootstatus timed out, but simulator launchd responds; continuing" >&2
    return
  fi

  xcrun simctl io "$DEVICE" screenshot /tmp/loupe-runtime-boot-not-ready.png >/dev/null 2>&1 || true
  echo "error: simulator $DEVICE did not finish booting; see $log_path and /tmp/loupe-runtime-boot-not-ready.png" >&2
  tail -40 "$log_path" >&2 || true
  exit 124
}

assert_device_ready
swift build

xcodebuild \
  -scheme LoupeInjector \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-injector-build.log

xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-example-build.log

export LOUPE_INJECTOR_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Debug-iphonesimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector' \
    -print0 | xargs -0 ls -t | head -1
)"

APP_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Debug-iphonesimulator/LoupeExample.app' \
    -print0 | xargs -0 ls -td | head -1
)"

terminate_app
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"

LAUNCH_ARGUMENTS=(
  --device "$DEVICE"
  --bundle-id dev.loupe.example
  --inject
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
grep -q '"uiKit"' "$SNAPSHOT_PATH"
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
