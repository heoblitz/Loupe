#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_WATCHOS_PORT:-28748}"
HOST="http://127.0.0.1:${PORT}"
DERIVED_DATA="${LOUPE_WATCHOS_DERIVED_DATA:-/tmp/loupe-watch-example-derived-data}"

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

booted_watchos_udid() {
  xcrun simctl list devices booted --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("Apple Watch") }
    puts booted && booted["udid"]
  '
}

available_watchos_udid() {
  xcrun simctl list devices available --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    device = devices.find { |entry| entry["name"].include?("Apple Watch Series 11 (46mm)") } ||
      devices.find { |entry| entry["name"].include?("Apple Watch") }
    puts device && device["udid"]
  '
}

DEVICE="${LOUPE_WATCHOS_DEVICE:-$(booted_watchos_udid)}"
if [[ -z "$DEVICE" ]]; then
  DEVICE="$(available_watchos_udid)"
  if [[ -z "$DEVICE" ]]; then
    echo "error: no available Apple Watch simulator found" >&2
    exit 1
  fi
  xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
fi

run_with_timeout 120 xcrun simctl bootstatus "$DEVICE" -b >/tmp/loupe-watchos-bootstatus.log 2>&1 || {
  echo "error: Apple Watch simulator did not finish booting; see /tmp/loupe-watchos-bootstatus.log" >&2
  tail -40 /tmp/loupe-watchos-bootstatus.log >&2 || true
  exit 124
}

swift build --product loupe
xcodebuild \
  -scheme LoupeInjector \
  -destination 'generic/platform=watchOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-watchos-injector-build.log

export LOUPE_INJECTOR_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Debug-watchsimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector' \
    -print0 | xargs -0 ls -t 2>/dev/null | head -1 || true
)"
if [[ -z "$LOUPE_INJECTOR_PATH" ]]; then
  echo "error: could not find watchOS Simulator LoupeInjector; see /tmp/loupe-watchos-injector-build.log" >&2
  exit 1
fi

rm -rf "$DERIVED_DATA"
xcodebuild \
  -project Examples/LoupeWatchExample/LoupeWatchExample.xcodeproj \
  -scheme LoupeWatchExample \
  -configuration Debug \
  -sdk watchsimulator \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath "$DERIVED_DATA" \
  build >/tmp/loupe-watchos-example-build.log

APP_PATH="$DERIVED_DATA/Build/Products/Debug-watchsimulator/LoupeWatchExample.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app at $APP_PATH" >&2
  exit 1
fi

xcrun simctl terminate "$DEVICE" dev.loupe.watch-example >/dev/null 2>&1 || true
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"
LAUNCH_OUTPUT="$(.build/debug/loupe app launch \
  --device "$DEVICE" \
  --bundle-id dev.loupe.watch-example \
  --inject \
  --port "$PORT" \
  --timeout 30)"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$LAUNCH_OUTPUT" | tail -1)"
if [[ -z "$HOST" ]]; then
  echo "error: loupe app launch did not report a runtime host" >&2
  echo "$LAUNCH_OUTPUT" >&2
  exit 1
fi
cleanup() {
  xcrun simctl terminate "$DEVICE" dev.loupe.watch-example >/dev/null 2>&1 || true
}
trap cleanup EXIT

for _ in {1..120}; do
  if curl -fsS "$HOST/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

SNAPSHOT_PATH="/tmp/loupe-watchos-snapshot.json"
ACCESSIBILITY_PATH="/tmp/loupe-watchos-accessibility.json"
VIEW_TREE_PATH="/tmp/loupe-watchos-view-tree.txt"
ACCESSIBILITY_TREE_PATH="/tmp/loupe-watchos-accessibility-tree.txt"
RUNTIME_PATH="/tmp/loupe-watchos-runtime.json"
LOGS_PATH="/tmp/loupe-watchos-logs.json"
NETWORK_PATH="/tmp/loupe-watchos-network.json"
REFS_PATH="/tmp/loupe-watchos-refs.json"
LEAKS_PATH="/tmp/loupe-watchos-leaks.json"
ACTIVE_FLAG_PATH="/tmp/loupe-watchos-active-flag.json"
FOCUS_FLAG_PATH="/tmp/loupe-watchos-focus-flag.json"
INTERVAL_FLAG_PATH="/tmp/loupe-watchos-interval-flag.json"
QUERY_PATH="/tmp/loupe-watchos-query.json"
INSPECT_ROOT_PATH="/tmp/loupe-watchos-inspect-root.json"
INSPECT_SUMMARY_PATH="/tmp/loupe-watchos-inspect-summary.json"

rm -f "$SNAPSHOT_PATH" "$ACCESSIBILITY_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$RUNTIME_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$LEAKS_PATH" "$ACTIVE_FLAG_PATH" "$FOCUS_FLAG_PATH" "$INTERVAL_FLAG_PATH" "$QUERY_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_SUMMARY_PATH"

curl -fsS "$HOST/health" | grep -q LoupeKit
.build/debug/loupe app info --host "$HOST" --udid "$DEVICE" > "$RUNTIME_PATH"

for _ in {1..120}; do
  .build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
  if ruby -rjson -e '
    snapshot = JSON.parse(File.read(ARGV.fetch(0)))
    exit(snapshot.fetch("nodes").values.any? { |node| node["testID"] == "watch.example.summary" } ? 0 : 1)
  ' "$SNAPSHOT_PATH"; then
    break
  fi
  sleep 0.25
done

.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH"
.build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id watch.example.summary > "$QUERY_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id watch.example.summary > "$INSPECT_SUMMARY_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --role application > "$INSPECT_ROOT_PATH"
.build/debug/loupe ui accessibility --host "$HOST" --timeout 10 --output "$ACCESSIBILITY_PATH" >/dev/null
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --all --view --depth 10 > "$VIEW_TREE_PATH"
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --all --accessibility --depth 10 > "$ACCESSIBILITY_TREE_PATH"
.build/debug/loupe debug logs --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe debug leaks --alive-only --host "$HOST" --udid "$DEVICE" --output "$LEAKS_PATH" >/dev/null
.build/debug/loupe debug defaults get watch-session-active --host "$HOST" --output "$ACTIVE_FLAG_PATH" >/dev/null
.build/debug/loupe debug defaults get watch-session-focus --host "$HOST" --output "$FOCUS_FLAG_PATH" >/dev/null
.build/debug/loupe debug defaults get watch-session-interval --host "$HOST" --output "$INTERVAL_FLAG_PATH" >/dev/null

ruby -rjson -e '
  runtime = JSON.parse(File.read(ARGV.fetch(0)))
  identity = runtime.fetch("identity")
  abort "expected watchOS bundle id" unless identity["bundleIdentifier"] == "dev.loupe.watch-example"
  abort "expected watchOS runtime platform" unless identity["platform"] == "watchOS"
  abort "expected simulator UDID" unless identity["simulatorUDID"] == ARGV.fetch(13)

  snapshot = JSON.parse(File.read(ARGV.fetch(1)))
  root = JSON.parse(File.read(ARGV.fetch(4))).fetch("node")
  abort "expected watchOS registered-probes backend" unless root.fetch("custom").dig("observationBackend", "value") == "registered-probes"
  abort "expected watchOS root metadata" unless root.fetch("custom").dig("platform", "value") == "watchOS"

  by_test_id = snapshot.fetch("nodes").values.each_with_object({}) { |node, map| map[node["testID"]] = node if node["testID"] }
  required_ids = [
    "watch.example.summary",
    "watch.example.swiftui.screen",
    "watch.example.metric.heartRate",
    "watch.example.metric.pace",
    "watch.example.metrics",
    "watch.example.interval",
    "watch.example.hydration",
    "watch.example.nextInterval",
    "watch.example.clearHydration",
    "watch.example.controls",
  ]
  missing_ids = required_ids.reject { |id| by_test_id[id] }
  abort "missing watchOS probes: #{missing_ids.join(", ")}" unless missing_ids.empty?

  summary = JSON.parse(File.read(ARGV.fetch(3))).fetch("node")
  abort "expected summary probe label" unless summary["label"] == "Tempo session summary"
  abort "expected summary probe metadata" unless summary.fetch("custom").dig("loupe.probe", "value") == true
  abort "expected no-import local fallback metadata" unless summary.fetch("custom").dig("source", "value") == "local-fallback"
  summary_frame = summary.fetch("frame")
  abort "expected summary probe bounds width" unless summary_frame.fetch("width").to_f > 40
  abort "expected summary probe bounds height" unless summary_frame.fetch("height").to_f > 20

  swiftui_screen = by_test_id.fetch("watch.example.swiftui.screen")
  abort "expected watchOS SwiftUI screen probe label" unless swiftui_screen["label"] == "watchOS SwiftUI screen"
  abort "expected watchOS SwiftUI probe metadata" unless swiftui_screen.dig("swiftui", "origin") == "probe"
  abort "expected watchOS SwiftUI metadata flag" unless swiftui_screen.fetch("custom").dig("loupe.swiftUI", "value") == true

  metrics_frame = by_test_id.fetch("watch.example.metrics").fetch("frame")
  heart_frame = by_test_id.fetch("watch.example.metric.heartRate").fetch("frame")
  pace_frame = by_test_id.fetch("watch.example.metric.pace").fetch("frame")
  abort "expected metrics probe to cover metric tiles" unless metrics_frame.fetch("width").to_f >= heart_frame.fetch("width").to_f + pace_frame.fetch("width").to_f

  query = JSON.parse(File.read(ARGV.fetch(2)))
  abort "expected query match for watch.example.summary" unless query.any? { |node| node["testID"] == "watch.example.summary" }

  accessibility = JSON.parse(File.read(ARGV.fetch(5)))
  ax_nodes = accessibility.fetch("nodes").values
  abort "missing watchOS summary accessibility node" unless ax_nodes.any? { |node| node["testID"] == "watch.example.summary" && node["label"] == "Tempo session summary" }
  abort "missing watchOS controls accessibility node" unless ax_nodes.any? { |node| node["testID"] == "watch.example.controls" && node["label"] == "Session controls" }

  view_tree = File.read(ARGV.fetch(6))
  ax_tree = File.read(ARGV.fetch(7))
  abort "expected watchOS view tree evidence" unless view_tree.include?("LoupeWatchProbe") && view_tree.include?("watch.example.summary")
  abort "expected watchOS SwiftUI screen view tree evidence" unless view_tree.include?("watch.example.swiftui.screen") && view_tree.include?("swiftui=probe")
  abort "expected watchOS accessibility tree evidence" unless ax_tree.include?("watch.example.summary") && ax_tree.include?("Session controls")

  logs = JSON.parse(File.read(ARGV.fetch(8)))
  visible_log = logs.find { |entry| entry["message"] == "watch_example_dashboard_visible" }
  abort "missing watchOS dashboard log" unless visible_log
  abort "expected watchOS log metadata" unless visible_log.dig("metadata", "focus", "value") == "Tempo" &&
    visible_log.dig("metadata", "interval", "value") == 3 &&
    visible_log.dig("metadata", "hydrationDue", "value") == true

  network = JSON.parse(File.read(ARGV.fetch(9)))
  event = network.find { |entry| entry["url"] == "watch://session/summary" }
  abort "missing watchOS app-authored network event" unless event
  abort "expected watchOS network metadata" unless event.dig("metadata", "platform", "value") == "watchOS" &&
    event.dig("metadata", "source", "value") == "app-authored"

  refs = JSON.parse(File.read(ARGV.fetch(10)))
  abort "missing watchOS reference evidence" unless refs.any? { |entry| entry["owner"] == "WatchSessionDashboard" && entry["target"] == "WatchSessionStore" && entry["kind"] == "strong" }

  leaks = JSON.parse(File.read(ARGV.fetch(11)))
  abort "expected weak lifetime probe evidence" unless leaks["evidenceKind"] == "weak-lifetime-probe"
  abort "missing watch session lifetime probe" unless leaks.fetch("probes").any? { |entry| entry["name"] == "watch session store" && entry["isAlive"] == true }

  active = JSON.parse(File.read(ARGV.fetch(12)))
  focus = JSON.parse(File.read(ARGV.fetch(14)))
  interval = JSON.parse(File.read(ARGV.fetch(15)))
  abort "expected active watch session flag" unless active.dig("value", "value") == true
  abort "expected watch session focus default" unless focus.dig("value", "value") == "Tempo"
  abort "expected watch session interval default" unless interval.dig("value", "value") == 3
' "$RUNTIME_PATH" "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_SUMMARY_PATH" "$INSPECT_ROOT_PATH" "$ACCESSIBILITY_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$LEAKS_PATH" "$ACTIVE_FLAG_PATH" "$DEVICE" "$FOCUS_FLAG_PATH" "$INTERVAL_FLAG_PATH"

echo "watchOS runtime E2E passed on $DEVICE with $HOST"
