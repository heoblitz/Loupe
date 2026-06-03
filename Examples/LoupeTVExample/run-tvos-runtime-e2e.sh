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
FOCUS_SNAPSHOT_PATH="/tmp/loupe-tvos-focus-snapshot.json"
ACCESSIBILITY_PATH="/tmp/loupe-tvos-accessibility.json"
VIEW_TREE_PATH="/tmp/loupe-tvos-view-tree.txt"
ACCESSIBILITY_TREE_PATH="/tmp/loupe-tvos-accessibility-tree.txt"
RUNTIME_PATH="/tmp/loupe-tvos-runtime.json"
LOGS_PATH="/tmp/loupe-tvos-logs.json"
PRESS_LOGS_PATH="/tmp/loupe-tvos-press-logs.json"
NEW_NAV_LOGS_PATH="/tmp/loupe-tvos-new-nav-logs.json"
LEGACY_LOGS_PATH="/tmp/loupe-tvos-legacy-logs.json"
LOGOUT_LOGS_PATH="/tmp/loupe-tvos-logout-logs.json"
NETWORK_PATH="/tmp/loupe-tvos-network.json"
REFS_PATH="/tmp/loupe-tvos-refs.json"
OBJECT_GRAPH_PATH="/tmp/loupe-tvos-object-graph.json"
FLAG_PATH="/tmp/loupe-tvos-flag.json"
FLAG_SET_PATH="/tmp/loupe-tvos-flag-set.json"
FLAG_DISABLED_PATH="/tmp/loupe-tvos-flag-disabled.json"
EMPTY_FLAG_PATH="/tmp/loupe-tvos-empty-flag.json"
KEYCHAIN_PATH="/tmp/loupe-tvos-keychain.json"
KEYCHAIN_AFTER_LOGOUT_PATH="/tmp/loupe-tvos-keychain-after-logout.json"
HIT_TEST_PATH="/tmp/loupe-tvos-hit-test.json"
RESPONDER_PATH="/tmp/loupe-tvos-responder-chain.json"
ENV_PATH="/tmp/loupe-tvos-env.json"
AUDIT_PATH="/tmp/loupe-tvos-audit.json"
PERF_PATH="/tmp/loupe-tvos-perf.json"
INSPECT_ROOT_PATH="/tmp/loupe-tvos-inspect-root.json"
INSPECT_LIST_PATH="/tmp/loupe-tvos-inspect-list.json"
INSPECT_EMPTY_PATH="/tmp/loupe-tvos-inspect-empty.json"
QUERY_PATH="/tmp/loupe-tvos-query.json"
PRESS_SELECT_TRACE_DIR="/tmp/loupe-tvos-press-select-trace"
PRESS_DOWN_TRACE_DIR="/tmp/loupe-tvos-press-down-trace"
PRESS_NEW_NAV_TRACE_DIR="/tmp/loupe-tvos-press-new-nav-trace"
PRESS_LEGACY_TRACE_DIR="/tmp/loupe-tvos-press-legacy-trace"
PRESS_LOGOUT_TRACE_DIR="/tmp/loupe-tvos-press-logout-trace"
rm -f "$SNAPSHOT_PATH" "$DARK_SNAPSHOT_PATH" "$FOCUS_SNAPSHOT_PATH" "$ACCESSIBILITY_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$RUNTIME_PATH" "$LOGS_PATH" "$PRESS_LOGS_PATH" "$NEW_NAV_LOGS_PATH" "$LEGACY_LOGS_PATH" "$LOGOUT_LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$OBJECT_GRAPH_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$FLAG_DISABLED_PATH" "$EMPTY_FLAG_PATH" "$KEYCHAIN_PATH" "$KEYCHAIN_AFTER_LOGOUT_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$AUDIT_PATH" "$PERF_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$INSPECT_EMPTY_PATH" "$QUERY_PATH"
rm -rf "$PRESS_SELECT_TRACE_DIR" "$PRESS_DOWN_TRACE_DIR" "$PRESS_NEW_NAV_TRACE_DIR" "$PRESS_LEGACY_TRACE_DIR" "$PRESS_LOGOUT_TRACE_DIR"

curl -fsS "$HOST/health" | grep -q LoupeKit
.build/debug/loupe app info --host "$HOST" --udid "$DEVICE" > "$RUNTIME_PATH"

for _ in {1..120}; do
  .build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
  if ruby -rjson -e '
    snapshot = JSON.parse(File.read(ARGV.fetch(0)))
    exit(snapshot.fetch("nodes").values.any? { |node| node["testID"] == "tv.example.collection" } ? 0 : 1)
  ' "$SNAPSHOT_PATH"; then
    break
  fi
  sleep 0.25
done

.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH"
.build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id tv.example.collection > "$QUERY_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id tv.example.root > "$INSPECT_ROOT_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id tv.example.collection > "$INSPECT_LIST_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id tv.example.emptyFeed > "$INSPECT_EMPTY_PATH"
.build/debug/loupe ui accessibility --host "$HOST" --timeout 10 --output "$ACCESSIBILITY_PATH" >/dev/null
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --view --depth 8 > "$VIEW_TREE_PATH"
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --accessibility --depth 8 > "$ACCESSIBILITY_TREE_PATH"
.build/debug/loupe debug logs --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe debug object-graph DeviceActuationService --host "$HOST" --udid "$DEVICE" --output "$OBJECT_GRAPH_PATH" >/dev/null
.build/debug/loupe debug flags get tv-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe debug flags set tv-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe debug flags get tv-empty-feed --host "$HOST" --output "$EMPTY_FLAG_PATH" >/dev/null
.build/debug/loupe debug keychain list --host "$HOST" --output "$KEYCHAIN_PATH" >/dev/null
BUTTON_POINT="$(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  node = snapshot.fetch("nodes").values.find { |candidate| candidate["testID"] == "tv.example.refresh" }
  abort "missing tv.example.refresh frame" unless node && node["frame"]
  frame = node.fetch("frame")
  puts "#{(frame.fetch("x") + frame.fetch("width") / 2.0).round},#{(frame.fetch("y") + frame.fetch("height") / 2.0).round}"
' "$SNAPSHOT_PATH")"
.build/debug/loupe ui hit-test --host "$HOST" --point "$BUTTON_POINT" --output "$HIT_TEST_PATH" >/dev/null
.build/debug/loupe ui responder-chain --host "$HOST" --test-id tv.example.refresh --output "$RESPONDER_PATH" >/dev/null
.build/debug/loupe debug scroll --host "$HOST" --udid "$DEVICE" --test-id tv.example.collection --delta 0,80 --output "$PERF_PATH" >/dev/null
.build/debug/loupe act press select --host "$HOST" --udid "$DEVICE" --trace-dir "$PRESS_SELECT_TRACE_DIR" --expect-visible tv.example.status
.build/debug/loupe act wait value --host "$HOST" --test-id tv.example.status --key text --equals "Snapshot refreshed" --timeout 5 >/tmp/loupe-tvos-wait-refresh.json
.build/debug/loupe debug logs --host "$HOST" --output "$PRESS_LOGS_PATH" >/dev/null
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
.build/debug/loupe act press down --host "$HOST" --udid "$DEVICE" --trace-dir "$PRESS_DOWN_TRACE_DIR" --expect-visible tv.example.secondary
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$FOCUS_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe act press down --host "$HOST" --udid "$DEVICE" --expect-visible tv.example.logout
.build/debug/loupe act press down --host "$HOST" --udid "$DEVICE" --expect-visible tv.example.legacyFlow
.build/debug/loupe act press select --host "$HOST" --udid "$DEVICE" --trace-dir "$PRESS_NEW_NAV_TRACE_DIR" --expect-visible tv.example.status
.build/debug/loupe act wait value --host "$HOST" --test-id tv.example.status --key text --equals "New nav active" --timeout 5 >/tmp/loupe-tvos-wait-new-nav.json
.build/debug/loupe debug logs --host "$HOST" --output "$NEW_NAV_LOGS_PATH" >/dev/null
.build/debug/loupe debug flags set tv-new-nav --bool false --host "$HOST" --output "$FLAG_DISABLED_PATH" >/dev/null
.build/debug/loupe act press select --host "$HOST" --udid "$DEVICE" --trace-dir "$PRESS_LEGACY_TRACE_DIR" --expect-visible tv.example.status
.build/debug/loupe act wait value --host "$HOST" --test-id tv.example.status --key text --equals "Legacy flow active" --timeout 5 >/tmp/loupe-tvos-wait-legacy.json
.build/debug/loupe debug logs --host "$HOST" --output "$LEGACY_LOGS_PATH" >/dev/null
.build/debug/loupe act press up --host "$HOST" --udid "$DEVICE" --expect-visible tv.example.logout
.build/debug/loupe act press select --host "$HOST" --udid "$DEVICE" --trace-dir "$PRESS_LOGOUT_TRACE_DIR" --expect-visible tv.example.status
.build/debug/loupe act wait value --host "$HOST" --test-id tv.example.status --key text --equals "Logged out" --timeout 5 >/tmp/loupe-tvos-wait-logout.json
.build/debug/loupe debug keychain list --host "$HOST" --output "$KEYCHAIN_AFTER_LOGOUT_PATH" >/dev/null
.build/debug/loupe debug logs --host "$HOST" --output "$LOGOUT_LOGS_PATH" >/dev/null
.build/debug/loupe ui appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$DARK_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe ui audit "$DARK_SNAPSHOT_PATH" --kind lowTextContrast > "$AUDIT_PATH"
.build/debug/loupe ui appearance system --host "$HOST" >/dev/null

ruby -rjson -e '
  runtime = JSON.parse(File.read(ARGV.fetch(0)))
  identity = runtime.fetch("identity")
  abort "expected tvOS bundle id" unless identity["bundleIdentifier"] == "dev.loupe.tvos-example"
  abort "expected simulator UDID" unless identity["simulatorUDID"] == ARGV.fetch(10)

  snapshot = JSON.parse(File.read(ARGV.fetch(1)))
  focus_snapshot = JSON.parse(File.read(ARGV.fetch(16)))
  accessibility = JSON.parse(File.read(ARGV.fetch(20)))
  view_tree = File.read(ARGV.fetch(31))
  ax_tree = File.read(ARGV.fetch(32))
  size = snapshot.fetch("screen").fetch("size")
  abort "expected nonzero tvOS screen" unless size.fetch("width") > 0 && size.fetch("height") > 0
  abort "missing tv.example.collection" unless snapshot.fetch("nodes").values.any? { |node| node["testID"] == "tv.example.collection" }
  abort "missing tv.example.emptyFeed" unless snapshot.fetch("nodes").values.any? { |node| node["testID"] == "tv.example.emptyFeed" }
  abort "expected tvOS view tree evidence" unless view_tree.include?("tv.example.collection") && view_tree.include?("ambiguousLayout=")
  abort "expected tvOS accessibility tree evidence" unless ax_tree.include?("tv.example.refresh")

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

  empty = JSON.parse(File.read(ARGV.fetch(21))).fetch("node")
  abort "expected empty feed scroll view" unless empty.dig("uiKit", "className") == "UIScrollView"
  abort "expected empty feed role" unless empty["role"] == "scrollView"
  empty_children = snapshot.fetch("nodes").values.select { |node| node["testID"]&.start_with?("tv.example.emptyFeed.row") }
  abort "expected no rendered empty feed rows" unless empty_children.empty?

  ax_nodes = accessibility.fetch("nodes").values
  abort "missing tvOS accessibility tree refresh button" unless ax_nodes.any? { |node| node["testID"] == "tv.example.refresh" && node["role"] == "button" }
  abort "missing tvOS accessibility tree logout button" unless ax_nodes.any? { |node| node["testID"] == "tv.example.logout" && node["role"] == "button" }

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

  status = snapshot.fetch("nodes").values.find { |node| node["testID"] == "tv.example.status" }
  abort "expected press select to refresh status" unless status && status["text"] == "Snapshot refreshed"

  secondary = snapshot.fetch("nodes").values.find { |node| node["testID"] == "tv.example.secondary" }
  abort "missing tv.example.secondary focusable node" unless secondary
  abort "expected tv.example.secondary focus eligibility" unless secondary.dig("uiKit", "canBecomeFocused") == true
  abort "expected tv.example.secondary not focused at launch" unless secondary.dig("uiKit", "isFocused") == false

  focused_nodes = snapshot.fetch("nodes").values.select { |node| node.dig("uiKit", "isFocused") == true }
  abort "expected exactly one focused tvOS node, got #{focused_nodes.map { |node| node["testID"] || node["typeName"] }.inspect}" unless focused_nodes.count == 1

  logs = JSON.parse(File.read(ARGV.fetch(5)))
  abort "missing tv_example_visible log" unless logs.any? { |entry| entry["message"] == "tv_example_visible" }
  abort "missing empty-feed diagnostic log" unless logs.any? { |entry| entry["message"] == "tv_example_empty_feed" && entry.dig("metadata", "reason", "value") == "api_returned_empty_items" }

  press_logs = JSON.parse(File.read(ARGV.fetch(17)))
  abort "missing tv_example_refresh_triggered log after press select" unless press_logs.any? { |entry| entry["message"] == "tv_example_refresh_triggered" }

  new_nav_logs = JSON.parse(File.read(ARGV.fetch(33)))
  abort "missing new-nav flow log after flag enabled" unless new_nav_logs.any? { |entry| entry["message"] == "tv_example_new_nav_flow" }

  legacy_logs = JSON.parse(File.read(ARGV.fetch(22)))
  abort "missing legacy flow log after flag disabled" unless legacy_logs.any? { |entry| entry["message"] == "tv_example_legacy_flow" }

  logout_logs = JSON.parse(File.read(ARGV.fetch(23)))
  abort "missing logout keychain-clear log" unless logout_logs.any? { |entry| entry["message"] == "tv_example_logout_cleared_keychain" }

  select_trace = ARGV.fetch(18)
  down_trace = ARGV.fetch(19)
  new_nav_trace = ARGV.fetch(34)
  legacy_trace = ARGV.fetch(24)
  logout_trace = ARGV.fetch(25)
  [
    "action-before.json",
    "action-target.json",
    "action-after.json",
    "before-snapshot.json",
    "after-snapshot.json",
    "before-accessibility.json",
    "after-accessibility.json",
    "before-logs.json",
    "after-logs.json",
    "before.png",
    "after.png",
  ].each do |name|
    abort "missing select press trace #{name}" unless File.exist?(File.join(select_trace, name))
    abort "missing down press trace #{name}" unless File.exist?(File.join(down_trace, name))
    abort "missing new-nav press trace #{name}" unless File.exist?(File.join(new_nav_trace, name))
    abort "missing legacy press trace #{name}" unless File.exist?(File.join(legacy_trace, name))
    abort "missing logout press trace #{name}" unless File.exist?(File.join(logout_trace, name))
  end
  select_action = JSON.parse(File.read(File.join(select_trace, "action-target.json")))
  abort "expected select press trace command" unless select_action["command"] == "press"
  abort "expected select press trace button" unless select_action["press"] == "select"
  abort "expected select remotePress source" unless select_action["resolvedSource"] == "remotePress:select"

  down_action = JSON.parse(File.read(File.join(down_trace, "action-target.json")))
  abort "expected down press trace command" unless down_action["command"] == "press"
  abort "expected down press trace button" unless down_action["press"] == "down"
  abort "expected down remotePress source" unless down_action["resolvedSource"] == "remotePress:down"

  new_nav_action = JSON.parse(File.read(File.join(new_nav_trace, "action-target.json")))
  abort "expected new-nav select trace command" unless new_nav_action["command"] == "press"
  abort "expected new-nav select trace button" unless new_nav_action["press"] == "select"

  new_nav_after = JSON.parse(File.read(File.join(new_nav_trace, "after-snapshot.json")))
  new_nav_status = new_nav_after.fetch("nodes").values.find { |node| node["testID"] == "tv.example.status" }
  abort "expected new-nav trace after snapshot to show new flow" unless new_nav_status && new_nav_status["text"] == "New nav active"

  legacy_action = JSON.parse(File.read(File.join(legacy_trace, "action-target.json")))
  abort "expected legacy select trace command" unless legacy_action["command"] == "press"
  abort "expected legacy select trace button" unless legacy_action["press"] == "select"

  logout_action = JSON.parse(File.read(File.join(logout_trace, "action-target.json")))
  abort "expected logout select trace command" unless logout_action["command"] == "press"
  abort "expected logout select trace button" unless logout_action["press"] == "select"

  legacy_after = JSON.parse(File.read(File.join(legacy_trace, "after-snapshot.json")))
  legacy_status = legacy_after.fetch("nodes").values.find { |node| node["testID"] == "tv.example.status" }
  abort "expected legacy trace after snapshot to show old flow" unless legacy_status && legacy_status["text"] == "Legacy flow active"

  logout_after = JSON.parse(File.read(File.join(logout_trace, "after-snapshot.json")))
  logout_status = logout_after.fetch("nodes").values.find { |node| node["testID"] == "tv.example.status" }
  abort "expected logout trace after snapshot" unless logout_status && logout_status["text"] == "Logged out"

  focused_after_down = focus_snapshot.fetch("nodes").values.select { |node| node.dig("uiKit", "isFocused") == true }
  abort "expected tv.example.secondary focused after press down, got #{focused_after_down.map { |node| node["testID"] || node["typeName"] }.inspect}" unless focused_after_down.any? { |node| node["testID"] == "tv.example.secondary" }

  network = JSON.parse(File.read(ARGV.fetch(6)))
  event = network.find { |entry| entry["url"] == "https://api.example.test/tvos/workbench" }
  abort "missing tvOS network fixture" unless event
  abort "expected tvOS network status 200" unless event["statusCode"] == 200
  abort "expected tvOS GET method" unless event["method"] == "GET"
  abort "expected tvOS network metadata" unless event.dig("metadata", "screen", "value") == "workbench"
  abort "expected tvOS response body" unless event["responseBody"]&.include?("tvOS")
  feed_event = network.find { |entry| entry["url"] == "https://api.example.test/tvos/feed" }
  abort "missing empty feed network fixture" unless feed_event
  abort "expected empty feed 204" unless feed_event["statusCode"] == 204
  abort "expected empty feed metadata" unless feed_event.dig("metadata", "empty", "value") == true
  abort "expected empty feed response body" unless feed_event["responseBody"]&.include?("\"items\":[]")

  refs = JSON.parse(File.read(ARGV.fetch(11)))
  abort "missing tvOS reference evidence" unless refs.any? { |entry| entry["owner"] == "TVWorkbenchController" && entry["target"] == "DeviceActuationService" }
  abort "missing tvOS weak reference evidence" unless refs.any? { |entry| entry["owner"] == "TVLegacyFlowCoordinator" && entry["target"] == "DeviceActuationService" && entry["kind"] == "weak" }

  graph = JSON.parse(File.read(ARGV.fetch(30)))
  abort "expected app-authored reference graph kind" unless graph["evidenceKind"] == "app-authored-reference-evidence"
  abort "expected graph target" unless graph["target"] == "DeviceActuationService"
  graph_owners = graph.fetch("owners").map { |entry| entry["owner"] }
  abort "expected TVWorkbenchController owner in graph" unless graph_owners.include?("TVWorkbenchController")
  abort "expected TVLegacyFlowCoordinator owner in graph" unless graph_owners.include?("TVLegacyFlowCoordinator")
  abort "expected graph owner evidence ids" unless graph.fetch("owners").all? { |entry| entry["evidenceID"].is_a?(String) && !entry["evidenceID"].empty? }
  abort "expected graph edge to DeviceActuationService" unless graph.fetch("edges").any? { |edge| edge["target"] == "DeviceActuationService" && edge["owner"] == "TVWorkbenchController" }
  abort "expected graph edge evidence ids" unless graph.fetch("edges").all? { |edge| edge["evidenceID"].is_a?(String) && !edge["evidenceID"].empty? }
  abort "expected graph node for DeviceActuationService" unless graph.fetch("nodes").any? { |node| node["name"] == "DeviceActuationService" && node["incomingCount"].to_i >= 2 }

  flag = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected tv-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(8)))
  abort "expected tv-new-nav=true after set" unless flag_set.dig("after", "value") == true

  flag_disabled = JSON.parse(File.read(ARGV.fetch(26)))
  abort "expected tv-new-nav=false after disable" unless flag_disabled.dig("after", "value") == false

  empty_flag = JSON.parse(File.read(ARGV.fetch(27)))
  abort "expected tv-empty-feed=true" unless empty_flag.dig("value", "value") == true

  keychain = JSON.parse(File.read(ARGV.fetch(12)))
  abort "missing tvOS keychain fixture metadata" unless keychain.any? { |entry| entry["service"] == "dev.loupe.tvos-example" && entry["account"] == "fixture" }

  keychain_after_logout = JSON.parse(File.read(ARGV.fetch(28)))
  abort "expected logout to clear tvOS keychain fixture" if keychain_after_logout.any? { |entry| entry["service"] == "dev.loupe.tvos-example" && entry["account"] == "fixture" }

  hit = JSON.parse(File.read(ARGV.fetch(13)))
  abort "expected tvOS hit-test evidence" unless hit["hitRef"] && hit["hitTypeName"]
  abort "expected tv.example.refresh in hit-test responder chain" unless hit.fetch("responderChain").any? { |entry| entry["testID"] == "tv.example.refresh" }

  responder = JSON.parse(File.read(ARGV.fetch(14)))
  abort "expected tv.example.refresh responder chain" unless responder.fetch("responderChain").any? { |entry| entry["testID"] == "tv.example.refresh" }

  perf = JSON.parse(File.read(ARGV.fetch(29)))
  abort "expected tvOS perf target" unless perf["testID"] == "tv.example.collection"
  abort "expected tvOS runtime perf without trace dir" unless perf["traceDirectory"].nil?
  abort "expected tvOS scroll before offset" unless perf["beforeOffset"].is_a?(Hash)
  abort "expected tvOS scroll after offset" unless perf["afterOffset"].is_a?(Hash)
  abort "expected tvOS positive scroll delta" unless perf.dig("delta", "y").to_f > 0
  abort "expected tvOS profile elapsed" unless perf["actionElapsed"].to_f >= 0

  env = JSON.parse(File.read(ARGV.fetch(9)))
  abort "expected dark appearance" unless env["appearance"] == "dark"

  audit = JSON.parse(File.read(ARGV.fetch(15)))
  target_ids = ["tv.example.title", "tv.example.status", "tv.example.refresh"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected tvOS dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
  bad_sentinel = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && issue["testID"] == "tv.example.dark.badContrast" }
  abort "expected dark contrast sentinel issue" if bad_sentinel.empty?
' "$RUNTIME_PATH" "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_ROOT_PATH" "$INSPECT_LIST_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$DEVICE" "$REFS_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$AUDIT_PATH" "$FOCUS_SNAPSHOT_PATH" "$PRESS_LOGS_PATH" "$PRESS_SELECT_TRACE_DIR" "$PRESS_DOWN_TRACE_DIR" "$ACCESSIBILITY_PATH" "$INSPECT_EMPTY_PATH" "$LEGACY_LOGS_PATH" "$LOGOUT_LOGS_PATH" "$PRESS_LEGACY_TRACE_DIR" "$PRESS_LOGOUT_TRACE_DIR" "$FLAG_DISABLED_PATH" "$EMPTY_FLAG_PATH" "$KEYCHAIN_AFTER_LOGOUT_PATH" "$PERF_PATH" "$OBJECT_GRAPH_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$NEW_NAV_LOGS_PATH" "$PRESS_NEW_NAV_TRACE_DIR"

echo "tvOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
