#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_TVOS_PORT:-28747}"
HOST="http://127.0.0.1:${PORT}"
DERIVED_DATA="${LOUPE_TVOS_DERIVED_DATA:-/tmp/loupe-tvos-example-derived-data}"

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

booted_tvos_udid() {
  xcrun simctl list devices booted --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("Apple TV") }
    puts booted && booted["udid"]
  '
}

available_tvos_udid() {
  xcrun simctl list devices available --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    device = devices.find { |entry| entry["name"].include?("Apple TV 4K") } ||
      devices.find { |entry| entry["name"].include?("Apple TV") }
    puts device && device["udid"]
  '
}

DEVICE="${LOUPE_TVOS_DEVICE:-$(booted_tvos_udid)}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(available_tvos_udid)"
  if [[ -z "$DEVICE" ]]; then
    echo "error: no available Apple TV simulator found" >&2
    exit 1
  fi
  xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
fi

run_with_timeout 120 xcrun simctl bootstatus "$DEVICE" -b >/tmp/loupe-tvos-bootstatus.log 2>&1 || {
  echo "error: Apple TV simulator did not finish booting; see /tmp/loupe-tvos-bootstatus.log" >&2
  tail -40 /tmp/loupe-tvos-bootstatus.log >&2 || true
  exit 124
}

swift build --product loupe
rm -rf "$DERIVED_DATA"
xcodebuild \
  -project Examples/LoupeTVExample/LoupeTVExample.xcodeproj \
  -scheme LoupeTVExample \
  -configuration Debug \
  -sdk appletvsimulator \
  -destination 'generic/platform=tvOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  build >/tmp/loupe-tvos-example-build.log

APP_PATH="$DERIVED_DATA/Build/Products/Debug-appletvsimulator/LoupeTVExample.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

xcrun simctl terminate "$DEVICE" dev.loupe.tvos-example >/dev/null 2>&1 || true
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"
SIMCTL_CHILD_LOUPE_PORT="$PORT" xcrun simctl launch "$DEVICE" dev.loupe.tvos-example >/tmp/loupe-tvos-launch.log
cleanup() {
  xcrun simctl terminate "$DEVICE" dev.loupe.tvos-example >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..120}; do
  if curl -fsS "$HOST/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

SNAPSHOT_PATH="/tmp/loupe-tvos-snapshot.json"
RUNTIME_PATH="/tmp/loupe-tvos-runtime.json"
LOGS_PATH="/tmp/loupe-tvos-logs.json"
NETWORK_PATH="/tmp/loupe-tvos-network.json"
FLAG_PATH="/tmp/loupe-tvos-flag.json"
FLAG_SET_PATH="/tmp/loupe-tvos-flag-set.json"
ENV_PATH="/tmp/loupe-tvos-env.json"
INSPECT_ROOT_PATH="/tmp/loupe-tvos-inspect-root.json"
INSPECT_LIST_PATH="/tmp/loupe-tvos-inspect-list.json"
QUERY_PATH="/tmp/loupe-tvos-query.json"
rm -f "$SNAPSHOT_PATH" "$RUNTIME_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$QUERY_PATH"

curl -fsS "$HOST/health" | grep -q LoupeKit
.build/debug/loupe runtime info --host "$HOST" --udid "$DEVICE" > "$RUNTIME_PATH"

for _ in {1..120}; do
  .build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
  if ruby -rjson -e '
    snapshot = JSON.parse(File.read(ARGV.fetch(0)))
    exit(snapshot.fetch("nodes").values.any? { |node| node["testID"] == "tv.example.collection" } ? 0 : 1)
  ' "$SNAPSHOT_PATH"; then
    break
  fi
  sleep 0.25
done

.build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$SNAPSHOT_PATH"
.build/debug/loupe inspect query "$SNAPSHOT_PATH" --test-id tv.example.collection > "$QUERY_PATH"
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id tv.example.root > "$INSPECT_ROOT_PATH"
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id tv.example.collection > "$INSPECT_LIST_PATH"
.build/debug/loupe debug console --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe state flags get tv-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe state flags set tv-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe env appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe env appearance system --host "$HOST" >/dev/null

ruby -rjson -e '
  runtime = JSON.parse(File.read(ARGV.fetch(0)))
  identity = runtime.fetch("identity")
  abort "expected tvOS bundle id" unless identity["bundleIdentifier"] == "dev.loupe.tvos-example"
  abort "expected simulator UDID" unless identity["simulatorUDID"] == ARGV.fetch(10)

  snapshot = JSON.parse(File.read(ARGV.fetch(1)))
  size = snapshot.fetch("screen").fetch("size")
  abort "expected nonzero tvOS screen" unless size.fetch("width") > 0 && size.fetch("height") > 0
  abort "missing tv.example.collection" unless snapshot.fetch("nodes").values.any? { |node| node["testID"] == "tv.example.collection" }

  query = JSON.parse(File.read(ARGV.fetch(2)))
  abort "expected query match for tv.example.collection" unless query.any? { |node| node["testID"] == "tv.example.collection" }

  root = JSON.parse(File.read(ARGV.fetch(3))).fetch("node")
  abort "expected root fixture metadata" unless root.fetch("custom").dig("fixture", "value") == true
  abort "expected root platform metadata" unless root.fetch("custom").dig("platform", "value") == "tvOS"

  list = JSON.parse(File.read(ARGV.fetch(4))).fetch("node")
  abort "expected UIScrollView list" unless list.dig("uiKit", "className") == "UIScrollView"

  logs = JSON.parse(File.read(ARGV.fetch(5)))
  abort "missing tv_example_visible log" unless logs.any? { |entry| entry["message"] == "tv_example_visible" }

  network = JSON.parse(File.read(ARGV.fetch(6)))
  abort "missing tvOS network fixture" unless network.any? { |entry| entry["url"] == "https://api.example.test/tvos/workbench" && entry["statusCode"] == 200 }

  flag = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected tv-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(8)))
  abort "expected tv-new-nav=true after set" unless flag_set.dig("after", "value") == true

  env = JSON.parse(File.read(ARGV.fetch(9)))
  abort "expected dark appearance" unless env["appearance"] == "dark"
' "$RUNTIME_PATH" "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$DEVICE"

echo "tvOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
