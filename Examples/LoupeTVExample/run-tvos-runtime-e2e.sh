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
DARK_SNAPSHOT_PATH="/tmp/loupe-tvos-dark-snapshot.json"
RUNTIME_PATH="/tmp/loupe-tvos-runtime.json"
LOGS_PATH="/tmp/loupe-tvos-logs.json"
NETWORK_PATH="/tmp/loupe-tvos-network.json"
REFS_PATH="/tmp/loupe-tvos-refs.json"
FLAG_PATH="/tmp/loupe-tvos-flag.json"
FLAG_SET_PATH="/tmp/loupe-tvos-flag-set.json"
KEYCHAIN_PATH="/tmp/loupe-tvos-keychain.json"
HIT_TEST_PATH="/tmp/loupe-tvos-hit-test.json"
RESPONDER_PATH="/tmp/loupe-tvos-responder-chain.json"
ENV_PATH="/tmp/loupe-tvos-env.json"
AUDIT_PATH="/tmp/loupe-tvos-audit.json"
INSPECT_ROOT_PATH="/tmp/loupe-tvos-inspect-root.json"
INSPECT_LIST_PATH="/tmp/loupe-tvos-inspect-list.json"
QUERY_PATH="/tmp/loupe-tvos-query.json"
rm -f "$SNAPSHOT_PATH" "$DARK_SNAPSHOT_PATH" "$RUNTIME_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$AUDIT_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$QUERY_PATH"

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
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe state flags get tv-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe state flags set tv-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe state keychain list --host "$HOST" --output "$KEYCHAIN_PATH" >/dev/null
BUTTON_POINT="$(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  node = snapshot.fetch("nodes").values.find { |candidate| candidate["testID"] == "tv.example.refresh" }
  abort "missing tv.example.refresh frame" unless node && node["frame"]
  frame = node.fetch("frame")
  puts "#{(frame.fetch("x") + frame.fetch("width") / 2.0).round},#{(frame.fetch("y") + frame.fetch("height") / 2.0).round}"
' "$SNAPSHOT_PATH")"
.build/debug/loupe ui hit-test --host "$HOST" --point "$BUTTON_POINT" --output "$HIT_TEST_PATH" >/dev/null
.build/debug/loupe ui responder-chain --host "$HOST" --test-id tv.example.refresh --output "$RESPONDER_PATH" >/dev/null
.build/debug/loupe env appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe observe fetch "$HOST/snapshot" --timeout 10 --output "$DARK_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe ui audit "$DARK_SNAPSHOT_PATH" --kind lowTextContrast > "$AUDIT_PATH"
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
  abort "expected tvOS list role" unless list["role"] == "scrollView"
  abort "expected tvOS list scroll properties" unless list.dig("uiKit", "scrollView", "isScrollEnabled") == true
  abort "expected tvOS list content taller than frame" unless list.dig("uiKit", "scrollView", "contentSize", "height").to_f > list.fetch("frame").fetch("height").to_f

  refresh = snapshot.fetch("nodes").values.find { |node| node["testID"] == "tv.example.refresh" }
  abort "missing tv.example.refresh focused node" unless refresh
  abort "expected tv.example.refresh button role" unless refresh["role"] == "button"
  abort "expected tv.example.refresh text" unless refresh["text"] == "Refresh snapshot"
  abort "expected tv.example.refresh interactive" unless refresh["isInteractive"] == true
  abort "expected tv.example.refresh focus state" unless refresh.dig("uiKit", "isFocused") == true
  abort "expected tv.example.refresh focus eligibility" unless refresh.dig("uiKit", "canBecomeFocused") == true
  abort "expected tv.example.refresh focused control state" unless refresh.dig("uiKit", "control", "controlState")&.include?("focused")
  abort "expected tv.example.refresh primary action" unless refresh.dig("uiKit", "control", "controlEvents")&.include?("primaryActionTriggered")
  abort "expected tv.example.refresh accessibility label" unless refresh.dig("accessibility", "label") == "Refresh snapshot"
  abort "expected tv.example.refresh accessibility element" unless refresh.dig("accessibility", "isElement") == true

  secondary = snapshot.fetch("nodes").values.find { |node| node["testID"] == "tv.example.secondary" }
  abort "missing tv.example.secondary focusable node" unless secondary
  abort "expected tv.example.secondary focus eligibility" unless secondary.dig("uiKit", "canBecomeFocused") == true
  abort "expected tv.example.secondary not focused at launch" unless secondary.dig("uiKit", "isFocused") == false

  focused_nodes = snapshot.fetch("nodes").values.select { |node| node.dig("uiKit", "isFocused") == true }
  abort "expected exactly one focused tvOS node, got #{focused_nodes.map { |node| node["testID"] || node["typeName"] }.inspect}" unless focused_nodes.count == 1

  logs = JSON.parse(File.read(ARGV.fetch(5)))
  abort "missing tv_example_visible log" unless logs.any? { |entry| entry["message"] == "tv_example_visible" }

  network = JSON.parse(File.read(ARGV.fetch(6)))
  event = network.find { |entry| entry["url"] == "https://api.example.test/tvos/workbench" }
  abort "missing tvOS network fixture" unless event
  abort "expected tvOS network status 200" unless event["statusCode"] == 200
  abort "expected tvOS GET method" unless event["method"] == "GET"
  abort "expected tvOS network metadata" unless event.dig("metadata", "screen", "value") == "workbench"
  abort "expected tvOS response body" unless event["responseBody"]&.include?("tvOS")

  refs = JSON.parse(File.read(ARGV.fetch(11)))
  abort "missing tvOS reference evidence" unless refs.any? { |entry| entry["owner"] == "TVWorkbenchController" && entry["target"] == "DeviceActuationService" }

  flag = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected tv-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(8)))
  abort "expected tv-new-nav=true after set" unless flag_set.dig("after", "value") == true

  keychain = JSON.parse(File.read(ARGV.fetch(12)))
  abort "missing tvOS keychain fixture metadata" unless keychain.any? { |entry| entry["service"] == "dev.loupe.tvos-example" && entry["account"] == "fixture" }

  hit = JSON.parse(File.read(ARGV.fetch(13)))
  abort "expected tvOS hit-test evidence" unless hit["hitRef"] && hit["hitTypeName"]
  abort "expected tv.example.refresh in hit-test responder chain" unless hit.fetch("responderChain").any? { |entry| entry["testID"] == "tv.example.refresh" }

  responder = JSON.parse(File.read(ARGV.fetch(14)))
  abort "expected tv.example.refresh responder chain" unless responder.fetch("responderChain").any? { |entry| entry["testID"] == "tv.example.refresh" }

  env = JSON.parse(File.read(ARGV.fetch(9)))
  abort "expected dark appearance" unless env["appearance"] == "dark"

  audit = JSON.parse(File.read(ARGV.fetch(15)))
  target_ids = ["tv.example.title", "tv.example.status", "tv.example.refresh"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected tvOS dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
' "$RUNTIME_PATH" "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$DEVICE" "$REFS_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$AUDIT_PATH"

echo "tvOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
