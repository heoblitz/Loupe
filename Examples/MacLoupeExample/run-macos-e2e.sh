#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_MACOS_PORT:-28746}"
HOST="http://127.0.0.1:${PORT}"

cd "$ROOT_DIR"

swift build --product loupe --product MacLoupeExample

APP_LOG="/tmp/loupe-macos-example.log"
SNAPSHOT_PATH="/tmp/loupe-macos-snapshot.json"
DARK_SNAPSHOT_PATH="/tmp/loupe-macos-dark-snapshot.json"
LOGS_PATH="/tmp/loupe-macos-logs.json"
NETWORK_PATH="/tmp/loupe-macos-network.json"
REFS_PATH="/tmp/loupe-macos-refs.json"
FLAG_PATH="/tmp/loupe-macos-flag.json"
FLAG_SET_PATH="/tmp/loupe-macos-flag-set.json"
KEYCHAIN_PATH="/tmp/loupe-macos-keychain.json"
HIT_TEST_PATH="/tmp/loupe-macos-hit-test.json"
RESPONDER_PATH="/tmp/loupe-macos-responder-chain.json"
ENV_PATH="/tmp/loupe-macos-env.json"
AUDIT_PATH="/tmp/loupe-macos-audit.json"
INSPECT_PATH="/tmp/loupe-macos-inspect.json"
INSPECT_TITLE_PATH="/tmp/loupe-macos-inspect-title.json"
QUERY_PATH="/tmp/loupe-macos-query.json"

rm -f "$APP_LOG" "$SNAPSHOT_PATH" "$DARK_SNAPSHOT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$AUDIT_PATH" "$INSPECT_PATH" "$INSPECT_TITLE_PATH" "$QUERY_PATH"

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
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id mac.example.title > "$INSPECT_TITLE_PATH"
.build/debug/loupe debug console --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe state flags get mac-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe state flags set mac-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe state keychain list --host "$HOST" --output "$KEYCHAIN_PATH" >/dev/null
BUTTON_POINT="$(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  node = snapshot.fetch("nodes").values.find { |candidate| candidate["testID"] == "mac.example.refresh" }
  abort "missing mac.example.refresh frame" unless node && node["frame"]
  frame = node.fetch("frame")
  puts "#{(frame.fetch("x") + frame.fetch("width") / 2.0).round},#{(frame.fetch("y") + frame.fetch("height") / 2.0).round}"
' "$SNAPSHOT_PATH")"
.build/debug/loupe ui hit-test --host "$HOST" --point "$BUTTON_POINT" --output "$HIT_TEST_PATH" >/dev/null
.build/debug/loupe ui responder-chain --host "$HOST" --test-id mac.example.refresh --output "$RESPONDER_PATH" >/dev/null
.build/debug/loupe env appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$DARK_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe ui audit "$DARK_SNAPSHOT_PATH" --kind lowTextContrast > "$AUDIT_PATH"
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

  title = JSON.parse(File.read(ARGV.fetch(13))).fetch("node")
  abort "expected macOS rendered text" unless title["renderedText"] == "Mac Loupe Workbench"
  abort "expected macOS semantic text" unless title["semanticText"] == "Mac Loupe Workbench"
  abort "expected AppKit accessibility value" unless title.dig("accessibility", "value") == "Mac Loupe Workbench"
  abort "expected AppKit font name" unless title.dig("style", "fontName")
  abort "expected AppKit font size" unless title.dig("style", "fontSize").is_a?(Numeric)
  abort "expected AppKit label properties" unless title.dig("uiKit", "label", "textAlignment") == "natural"
  abort "expected AppKit label line break mode" unless title.dig("uiKit", "label", "lineBreakMode")

  logs = JSON.parse(File.read(ARGV.fetch(3)))
  abort "missing mac_example_visible log" unless logs.any? { |entry| entry["message"] == "mac_example_visible" }

  network = JSON.parse(File.read(ARGV.fetch(4)))
  event = network.find { |entry| entry["url"] == "https://api.example.test/macos/workbench" }
  abort "missing macOS network fixture" unless event
  abort "expected macOS network status 200" unless event["statusCode"] == 200
  abort "expected macOS GET method" unless event["method"] == "GET"
  abort "expected macOS network metadata" unless event.dig("metadata", "screen", "value") == "workbench"
  abort "expected macOS response body" unless event["responseBody"]&.include?("macOS")

  refs = JSON.parse(File.read(ARGV.fetch(8)))
  abort "missing macOS reference evidence" unless refs.any? { |entry| entry["owner"] == "MacWorkbenchController" && entry["target"] == "DeviceActuationService" }

  flag = JSON.parse(File.read(ARGV.fetch(5)))
  abort "expected mac-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(6)))
  abort "expected mac-new-nav=true after set" unless flag_set.dig("after", "value") == true

  keychain = JSON.parse(File.read(ARGV.fetch(9)))
  abort "missing macOS keychain fixture metadata" unless keychain.any? { |entry| entry["service"] == "dev.loupe.macos-example" && entry["account"] == "fixture" }

  hit = JSON.parse(File.read(ARGV.fetch(10)))
  abort "expected mac.example.refresh hit-test" unless hit["hitTestID"] == "mac.example.refresh"

  responder = JSON.parse(File.read(ARGV.fetch(11)))
  abort "expected mac.example.refresh responder chain" unless responder.fetch("responderChain").any? { |entry| entry["testID"] == "mac.example.refresh" }

  env = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected dark appearance" unless env["appearance"] == "dark"

  audit = JSON.parse(File.read(ARGV.fetch(12)))
  target_ids = ["mac.example.title", "mac.example.status", "mac.example.refresh"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected macOS dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
' "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$REFS_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$AUDIT_PATH" "$INSPECT_TITLE_PATH"

echo "macOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
