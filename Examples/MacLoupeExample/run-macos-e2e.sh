#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_MACOS_PORT:-28746}"
HOST="http://127.0.0.1:${PORT}"

cd "$ROOT_DIR"

swift build --product loupe --product MacLoupeExample

APP_LOG="/tmp/loupe-macos-example.log"
SNAPSHOT_PATH="/tmp/loupe-macos-snapshot.json"
LOGS_PATH="/tmp/loupe-macos-logs.json"
NETWORK_PATH="/tmp/loupe-macos-network.json"
FLAG_PATH="/tmp/loupe-macos-flag.json"
FLAG_SET_PATH="/tmp/loupe-macos-flag-set.json"
ENV_PATH="/tmp/loupe-macos-env.json"
INSPECT_PATH="/tmp/loupe-macos-inspect.json"
QUERY_PATH="/tmp/loupe-macos-query.json"

rm -f "$APP_LOG" "$SNAPSHOT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$INSPECT_PATH" "$QUERY_PATH"

LOUPE_PORT="$PORT" .build/debug/MacLoupeExample >"$APP_LOG" 2>&1 &
APP_PID=$!
cleanup() {
  kill "$APP_PID" >/dev/null 2>&1 || true
  wait "$APP_PID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..120}; do
  if curl -fsS "$HOST/health" >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$APP_PID" >/dev/null 2>&1; then
    echo "error: MacLoupeExample exited before health was available" >&2
    cat "$APP_LOG" >&2 || true
    exit 1
  fi
  sleep 0.25
done

curl -fsS "$HOST/health" | grep -q LoupeKit

for _ in {1..120}; do
  .build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
  if ruby -rjson -e '
    snapshot = JSON.parse(File.read(ARGV.fetch(0)))
    exit(snapshot.fetch("nodes").values.any? { |node| node["testID"] == "mac.example.list" } ? 0 : 1)
  ' "$SNAPSHOT_PATH"; then
    break
  fi
  sleep 0.25
done

.build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$SNAPSHOT_PATH"
.build/debug/loupe inspect query "$SNAPSHOT_PATH" --test-id mac.example.list > "$QUERY_PATH"
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id mac.example.root > "$INSPECT_PATH"
.build/debug/loupe debug console --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe state flags get mac-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe state flags set mac-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe env appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe env appearance system --host "$HOST" >/dev/null

ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  abort "expected AppKit snapshot" unless snapshot.fetch("nodes").values.any? { |node| node["uiKit"] && node["typeName"] == "NSScrollView" }
  abort "missing mac.example.list" unless snapshot.fetch("nodes").values.any? { |node| node["testID"] == "mac.example.list" }

  query = JSON.parse(File.read(ARGV.fetch(1)))
  abort "expected query match for mac.example.list" unless query.any? { |node| node["testID"] == "mac.example.list" }

  inspection = JSON.parse(File.read(ARGV.fetch(2)))
  custom = inspection.fetch("node").fetch("custom")
  abort "expected platform=macOS custom metadata" unless custom.dig("platform", "value") == "macOS"

  logs = JSON.parse(File.read(ARGV.fetch(3)))
  abort "missing mac_example_visible log" unless logs.any? { |entry| entry["message"] == "mac_example_visible" }

  network = JSON.parse(File.read(ARGV.fetch(4)))
  abort "missing macOS network fixture" unless network.any? { |entry| entry["url"] == "https://api.example.test/macos/workbench" && entry["statusCode"] == 200 }

  flag = JSON.parse(File.read(ARGV.fetch(5)))
  abort "expected mac-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(6)))
  abort "expected mac-new-nav=true after set" unless flag_set.dig("after", "value") == true

  env = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected dark appearance" unless env["appearance"] == "dark"
' "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH"

echo "macOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
