#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_MACOS_PORT:-28746}"
HOST="http://127.0.0.1:${PORT}"

cd "$ROOT_DIR"

swift build --product loupe
swift build --product LoupeInjector
xcodebuild \
  -project Examples/MacLoupeExample/MacLoupeExample.xcodeproj \
  -scheme MacLoupeExample \
  -destination 'platform=macOS' \
  -configuration Debug \
  -derivedDataPath /tmp/loupe-macos-example-build \
  build >/tmp/loupe-macos-example-build.log
INJECTOR_PATH="$(
  find .build \
    -path '*debug/libLoupeInjector.dylib' \
    -print0 | xargs -0 ls -t 2>/dev/null | head -1 || true
)"
if [[ -z "$INJECTOR_PATH" ]]; then
  echo "error: could not find macOS LoupeInjector dylib" >&2
  exit 1
fi
APP_EXECUTABLE="$(
  find /tmp/loupe-macos-example-build \
    -path '*Debug/MacLoupeExample.app/Contents/MacOS/MacLoupeExample' \
    -print0 | xargs -0 ls -t 2>/dev/null | head -1 || true
)"
if [[ -z "$APP_EXECUTABLE" ]]; then
  echo "error: could not find built MacLoupeExample.app executable; see /tmp/loupe-macos-example-build.log" >&2
  exit 1
fi

APP_LOG="/tmp/loupe-macos-example.log"
SNAPSHOT_PATH="/tmp/loupe-macos-snapshot.json"
DARK_SNAPSHOT_PATH="/tmp/loupe-macos-dark-snapshot.json"
ACCESSIBILITY_PATH="/tmp/loupe-macos-accessibility.json"
VIEW_TREE_PATH="/tmp/loupe-macos-view-tree.txt"
ACCESSIBILITY_TREE_PATH="/tmp/loupe-macos-accessibility-tree.txt"
LOGS_PATH="/tmp/loupe-macos-logs.json"
ROUTE_LOGS_PATH="/tmp/loupe-macos-route-logs.json"
NEW_NAV_LOGS_PATH="/tmp/loupe-macos-new-nav-logs.json"
LOGOUT_LOGS_PATH="/tmp/loupe-macos-logout-logs.json"
NETWORK_PATH="/tmp/loupe-macos-network.json"
REFS_PATH="/tmp/loupe-macos-refs.json"
OBJECT_GRAPH_PATH="/tmp/loupe-macos-object-graph.json"
OBJECT_CLASSES_PATH="/tmp/loupe-macos-object-classes.json"
OBJECT_DESCRIPTION_PATH="/tmp/loupe-macos-object-description.json"
LEAKS_PATH="/tmp/loupe-macos-leaks.json"
FLAG_PATH="/tmp/loupe-macos-flag.json"
FLAG_SET_PATH="/tmp/loupe-macos-flag-set.json"
LOGOUT_FLAG_SET_PATH="/tmp/loupe-macos-logout-flag-set.json"
EMPTY_FLAG_PATH="/tmp/loupe-macos-empty-flag.json"
ERROR_FLAG_PATH="/tmp/loupe-macos-error-flag.json"
ERROR_FLAG_SET_PATH="/tmp/loupe-macos-error-flag-set.json"
ERROR_SNAPSHOT_PATH="/tmp/loupe-macos-error-snapshot.json"
ERROR_INSPECT_PATH="/tmp/loupe-macos-error-inspect.json"
ERROR_LOGS_PATH="/tmp/loupe-macos-error-logs.json"
KEYCHAIN_PATH="/tmp/loupe-macos-keychain.json"
KEYCHAIN_AFTER_LOGOUT_PATH="/tmp/loupe-macos-keychain-after-logout.json"
HIT_TEST_PATH="/tmp/loupe-macos-hit-test.json"
RESPONDER_PATH="/tmp/loupe-macos-responder-chain.json"
ENV_PATH="/tmp/loupe-macos-env.json"
AUDIT_PATH="/tmp/loupe-macos-audit.json"
PERF_PATH="/tmp/loupe-macos-perf.json"
DETAIL_SCROLL_PATH="/tmp/loupe-macos-detail-scroll.json"
LONG_LIST_SCROLL_PATH="/tmp/loupe-macos-long-list-scroll.json"
MUTATION_PATH="/tmp/loupe-macos-mutation.json"
INSPECT_PATH="/tmp/loupe-macos-inspect.json"
INSPECT_TITLE_PATH="/tmp/loupe-macos-inspect-title.json"
INSPECT_EMPTY_PATH="/tmp/loupe-macos-inspect-empty.json"
QUERY_PATH="/tmp/loupe-macos-query.json"
DETAIL_SNAPSHOT_PATH="/tmp/loupe-macos-detail-snapshot.json"
LONG_LIST_SNAPSHOT_PATH="/tmp/loupe-macos-long-list-snapshot.json"
SWIFTUI_SNAPSHOT_PATH="/tmp/loupe-macos-swiftui-snapshot.json"
DETAIL_TRACE_DIR="/tmp/loupe-macos-detail-route-trace"
DETAIL_BACK_TRACE_DIR="/tmp/loupe-macos-detail-back-trace"
LONG_LIST_TRACE_DIR="/tmp/loupe-macos-long-list-route-trace"
LONG_LIST_BACK_TRACE_DIR="/tmp/loupe-macos-long-list-back-trace"
SWIFTUI_TRACE_DIR="/tmp/loupe-macos-swiftui-route-trace"
SWIFTUI_BACK_TRACE_DIR="/tmp/loupe-macos-swiftui-back-trace"

rm -f "$APP_LOG" "$SNAPSHOT_PATH" "$DARK_SNAPSHOT_PATH" "$ACCESSIBILITY_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$LOGS_PATH" "$ROUTE_LOGS_PATH" "$NEW_NAV_LOGS_PATH" "$LOGOUT_LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$OBJECT_GRAPH_PATH" "$OBJECT_CLASSES_PATH" "$OBJECT_DESCRIPTION_PATH" "$LEAKS_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$LOGOUT_FLAG_SET_PATH" "$EMPTY_FLAG_PATH" "$ERROR_FLAG_PATH" "$ERROR_FLAG_SET_PATH" "$ERROR_SNAPSHOT_PATH" "$ERROR_INSPECT_PATH" "$ERROR_LOGS_PATH" "$KEYCHAIN_PATH" "$KEYCHAIN_AFTER_LOGOUT_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$AUDIT_PATH" "$PERF_PATH" "$DETAIL_SCROLL_PATH" "$LONG_LIST_SCROLL_PATH" "$MUTATION_PATH" "$INSPECT_PATH" "$INSPECT_TITLE_PATH" "$INSPECT_EMPTY_PATH" "$QUERY_PATH" "$DETAIL_SNAPSHOT_PATH" "$LONG_LIST_SNAPSHOT_PATH" "$SWIFTUI_SNAPSHOT_PATH"
rm -rf "$DETAIL_TRACE_DIR" "$DETAIL_BACK_TRACE_DIR" "$LONG_LIST_TRACE_DIR" "$LONG_LIST_BACK_TRACE_DIR" "$SWIFTUI_TRACE_DIR" "$SWIFTUI_BACK_TRACE_DIR"

DYLD_INSERT_LIBRARIES="$INJECTOR_PATH" LOUPE_PORT="$PORT" "$APP_EXECUTABLE" >"$APP_LOG" 2>&1 &
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
  .build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH" >/dev/null
  if ruby -rjson -e '
    snapshot = JSON.parse(File.read(ARGV.fetch(0)))
    exit(snapshot.fetch("nodes").values.any? { |node| node["testID"] == "mac.example.list" } ? 0 : 1)
  ' "$SNAPSHOT_PATH"; then
    break
  fi
  sleep 0.25
done

.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH"
.build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id mac.example.list > "$QUERY_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id mac.example.root > "$INSPECT_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id mac.example.title > "$INSPECT_TITLE_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id mac.example.emptyFeed > "$INSPECT_EMPTY_PATH"
.build/debug/loupe ui accessibility --host "$HOST" --timeout 10 --output "$ACCESSIBILITY_PATH" >/dev/null
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --view --depth 6 > "$VIEW_TREE_PATH"
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --accessibility --depth 6 > "$ACCESSIBILITY_TREE_PATH"
.build/debug/loupe debug logs --host "$HOST" --output "$LOGS_PATH" >/dev/null
for _ in {1..40}; do
  .build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
  if ruby -rjson -e '
    events = JSON.parse(File.read(ARGV.fetch(0)))
    exit(events.any? { |entry| entry["url"]&.include?("/__loupe_network_fixture/macos/error-route") } ? 0 : 1)
  ' "$NETWORK_PATH"; then
    break
  fi
  sleep 0.25
done
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe debug object-graph DeviceActuationService --host "$HOST" --output "$OBJECT_GRAPH_PATH" >/dev/null
.build/debug/loupe debug objects classes --matching DeviceActuationService --limit 20 --host "$HOST" --output "$OBJECT_CLASSES_PATH" >/dev/null
.build/debug/loupe debug objects describe DeviceActuationService --host "$HOST" --output "$OBJECT_DESCRIPTION_PATH" >/dev/null
.build/debug/loupe debug leaks --alive-only --host "$HOST" --output "$LEAKS_PATH" >/dev/null
.build/debug/loupe debug flags get mac-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe act targets --host "$HOST" >/tmp/loupe-macos-action-targets.txt
grep -E -q 'button "Refresh snapshot" \[.*press' /tmp/loupe-macos-action-targets.txt
.build/debug/loupe act perform --host "$HOST" --test-id mac.example.refresh --action press >/tmp/loupe-macos-perform-press.json
grep -q '"action":"press"' /tmp/loupe-macos-perform-press.json
.build/debug/loupe act wait value --host "$HOST" --test-id mac.example.status --key text --equals "Snapshot refreshed" --timeout 5 >/tmp/loupe-macos-wait-refresh.json
.build/debug/loupe debug flags set mac-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe act wait value --host "$HOST" --test-id mac.example.status --key text --equals "New nav active" --timeout 5 >/tmp/loupe-macos-wait-new-nav.json
.build/debug/loupe debug logs --host "$HOST" --output "$NEW_NAV_LOGS_PATH" >/dev/null
.build/debug/loupe debug flags get mac-empty-feed --host "$HOST" --output "$EMPTY_FLAG_PATH" >/dev/null
.build/debug/loupe debug keychain list --host "$HOST" --output "$KEYCHAIN_PATH" >/dev/null
.build/debug/loupe debug flags set mac-logout --bool true --host "$HOST" --output "$LOGOUT_FLAG_SET_PATH" >/dev/null
.build/debug/loupe act wait value --host "$HOST" --test-id mac.example.status --key text --equals "Logged out" --timeout 5 >/tmp/loupe-macos-wait-logout.json
.build/debug/loupe debug keychain list --host "$HOST" --output "$KEYCHAIN_AFTER_LOGOUT_PATH" >/dev/null
.build/debug/loupe debug logs --host "$HOST" --output "$LOGOUT_LOGS_PATH" >/dev/null
BUTTON_POINT="$(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  node = snapshot.fetch("nodes").values.find { |candidate| candidate["testID"] == "mac.example.refresh" }
  abort "missing mac.example.refresh frame" unless node && node["frame"]
  frame = node.fetch("frame")
  puts "#{(frame.fetch("x") + frame.fetch("width") / 2.0).round},#{(frame.fetch("y") + frame.fetch("height") / 2.0).round}"
' "$SNAPSHOT_PATH")"
.build/debug/loupe ui hit-test --host "$HOST" --point "$BUTTON_POINT" --output "$HIT_TEST_PATH" >/dev/null
.build/debug/loupe ui responder-chain --host "$HOST" --test-id mac.example.refresh --output "$RESPONDER_PATH" >/dev/null
.build/debug/loupe debug scroll --host "$HOST" --test-id mac.example.list --delta 0,40 --output "$PERF_PATH" >/dev/null
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.openDetail --trace-dir "$DETAIL_TRACE_DIR" --expect-visible mac.example.detail
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.detail.summary --timeout 5 >/tmp/loupe-macos-wait-detail.json
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$DETAIL_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe debug scroll --host "$HOST" --test-id mac.example.detail.scroll --delta 0,80 --output "$DETAIL_SCROLL_PATH" >/dev/null
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.detail.back --trace-dir "$DETAIL_BACK_TRACE_DIR" --expect-visible mac.example.root
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.openLongList --timeout 5 >/tmp/loupe-macos-wait-workbench-after-detail.json
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.openLongList --trace-dir "$LONG_LIST_TRACE_DIR" --expect-visible mac.example.longList
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.longList.scroll --timeout 5 >/tmp/loupe-macos-wait-long-list.json
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$LONG_LIST_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe debug scroll --host "$HOST" --test-id mac.example.longList.scroll --delta 0,120 --output "$LONG_LIST_SCROLL_PATH" >/dev/null
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.longList.back --trace-dir "$LONG_LIST_BACK_TRACE_DIR" --expect-visible mac.example.root
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.refresh --timeout 5 >/tmp/loupe-macos-wait-workbench-after-long-list.json
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.openSwiftUI --trace-dir "$SWIFTUI_TRACE_DIR" --expect-visible mac.example.swiftuiRoute
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.swiftuiRoute.probe --timeout 5 >/tmp/loupe-macos-wait-swiftui-route.json
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SWIFTUI_SNAPSHOT_PATH" >/dev/null
ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  by_test_id = snapshot.fetch("nodes").values.each_with_object({}) { |node, map| map[node["testID"]] = node if node["testID"] }
  root = by_test_id.fetch("mac.example.swiftuiRoute")
  host = by_test_id.fetch("mac.example.swiftuiRoute.host")
  probe = by_test_id.fetch("mac.example.swiftuiRoute.probe")
  by_test_id.fetch("mac.example.swiftuiRoute.controls")
  by_test_id.fetch("mac.example.swiftuiRoute.rows")
  by_test_id.fetch("mac.example.swiftuiRoute.row.1")
  abort "expected macOS SwiftUI route root" unless root.fetch("custom").dig("platform", "value") == "macOS"
  abort "expected macOS SwiftUI route host metadata" unless host.dig("swiftui", "origin") == "host"
  abort "expected macOS SwiftUI route probe metadata" unless probe.dig("swiftui", "origin") == "probe"
  abort "expected macOS SwiftUI root type summary" unless host.dig("swiftui", "rootTypeName") == "MacSwiftUIScreenView"
  properties = host.dig("swiftui", "properties") || []
  abort "expected macOS SwiftUI private property summary" unless properties.any? { |property|
    property["name"] == "mode" && property.dig("value", "value") == "Inspect"
  }
  abort "expected macOS SwiftUI route probe label" unless probe["label"] == "macOS SwiftUI route probe"
' "$SWIFTUI_SNAPSHOT_PATH"
.build/debug/loupe act tap --backend runtime --host "$HOST" --test-id mac.example.swiftuiRoute.back --trace-dir "$SWIFTUI_BACK_TRACE_DIR" --expect-visible mac.example.root
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.refresh --timeout 5 >/tmp/loupe-macos-wait-workbench-after-swiftui.json
.build/debug/loupe debug logs --host "$HOST" --output "$ROUTE_LOGS_PATH" >/dev/null
.build/debug/loupe ui set --host "$HOST" --test-id mac.example.status text "AppKit mutation applied" --no-animate --output "$MUTATION_PATH" >/dev/null
.build/debug/loupe ui appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$DARK_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe ui audit "$DARK_SNAPSHOT_PATH" --kind lowTextContrast > "$AUDIT_PATH"
.build/debug/loupe ui appearance system --host "$HOST" >/dev/null
.build/debug/loupe debug flags get mac-error-route --host "$HOST" --output "$ERROR_FLAG_PATH" >/dev/null
.build/debug/loupe debug flags set mac-error-route --bool true --host "$HOST" --output "$ERROR_FLAG_SET_PATH" >/dev/null
.build/debug/loupe act wait visible --host "$HOST" --test-id mac.example.error --timeout 5 >/tmp/loupe-macos-wait-error-route.json
.build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$ERROR_SNAPSHOT_PATH" >/dev/null
.build/debug/loupe ui node "$ERROR_SNAPSHOT_PATH" --test-id mac.example.error > "$ERROR_INSPECT_PATH"
.build/debug/loupe debug logs --host "$HOST" --output "$ERROR_LOGS_PATH" >/dev/null

ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  abort "expected AppKit snapshot" unless snapshot.fetch("nodes").values.any? { |node| node["appkit"] && node["typeName"] == "NSScrollView" }
  abort "missing mac.example.list" unless snapshot.fetch("nodes").values.any? { |node| node["testID"] == "mac.example.list" }
  view_tree = File.read(ARGV.fetch(21))
  ax_tree = File.read(ARGV.fetch(22))
  abort "expected macOS view tree evidence" unless view_tree.include?("mac.example.list") && view_tree.include?("ambiguousLayout=")
  abort "expected macOS SwiftUI host view tree evidence" unless view_tree.include?("mac.example.swiftui.host")
  abort "expected macOS SwiftUI probe view tree evidence" unless view_tree.include?("mac.example.swiftui.probe")
  abort "expected macOS accessibility tree evidence" unless ax_tree.include?("mac.example.refresh")
  abort "expected macOS SwiftUI probe accessibility tree evidence" unless ax_tree.include?("mac.example.swiftui.probe")

  query = JSON.parse(File.read(ARGV.fetch(1)))
  abort "expected query match for mac.example.list" unless query.any? { |node| node["testID"] == "mac.example.list" }

  inspection = JSON.parse(File.read(ARGV.fetch(2)))
  custom = inspection.fetch("node").fetch("custom")
  abort "expected platform=macOS custom metadata" unless custom.dig("platform", "value") == "macOS"

  title = JSON.parse(File.read(ARGV.fetch(13))).fetch("node")
  abort "expected macOS title static text role" unless title["role"] == "staticText"
  abort "expected macOS title to be non-interactive" unless title["isInteractive"] == false
  abort "expected macOS rendered text" unless title["renderedText"] == "Mac Loupe Workbench"
  abort "expected macOS semantic text" unless title["semanticText"] == "Mac Loupe Workbench"
  abort "expected AppKit accessibility value" unless title.dig("accessibility", "value") == "Mac Loupe Workbench"
  abort "expected AppKit font name" unless title.dig("style", "fontName")
  abort "expected AppKit font size" unless title.dig("style", "fontSize").is_a?(Numeric)
  abort "expected AppKit label properties" unless title.dig("appkit", "label", "textAlignment") == "natural"
  abort "expected AppKit label line break mode" unless title.dig("appkit", "label", "lineBreakMode")

  by_test_id = snapshot.fetch("nodes").values.each_with_object({}) { |node, map| map[node["testID"]] = node if node["testID"] }
  abort "missing mac.example.emptyFeed" unless by_test_id["mac.example.emptyFeed"]
  empty = JSON.parse(File.read(ARGV.fetch(15))).fetch("node")
  abort "expected AppKit empty feed scroll view" unless empty.dig("appkit", "className") == "NSScrollView"
  abort "expected empty feed role" unless empty["role"] == "scrollView"
  empty_rows = snapshot.fetch("nodes").values.select { |node| node["testID"]&.start_with?("mac.example.emptyFeed.row") }
  abort "expected no rendered empty feed rows" unless empty_rows.empty?
  retry_banner = by_test_id.fetch("mac.example.emptyFeed.retryBanner")
  abort "expected macOS retry banner evidence" unless retry_banner["renderedText"]&.include?("Retry banner")

  segmented = by_test_id.fetch("mac.example.segmented")
  abort "expected AppKit segmented role" unless segmented["role"] == "segmentedControl"
  abort "expected AppKit segmented selection" unless segmented.dig("appkit", "segmentedControl", "selectedSegmentIndex") == 1
  abort "expected AppKit segmented labels" unless segmented.dig("appkit", "segmentedControl", "segments") == ["List", "Detail"]

  slider = by_test_id.fetch("mac.example.slider")
  abort "expected AppKit slider role" unless slider["role"] == "slider"
  abort "expected AppKit slider value" unless slider.dig("appkit", "slider", "value") == 42
  abort "expected AppKit slider range" unless slider.dig("appkit", "slider", "minimumValue") == 0 && slider.dig("appkit", "slider", "maximumValue") == 100

  stepper = by_test_id.fetch("mac.example.stepper")
  abort "expected AppKit stepper role" unless stepper["role"] == "stepper"
  abort "expected AppKit stepper value" unless stepper.dig("appkit", "stepper", "value") == 4
  abort "expected AppKit stepper increment" unless stepper.dig("appkit", "stepper", "stepValue") == 2

  progress = by_test_id.fetch("mac.example.progress")
  abort "expected AppKit progress role" unless progress["role"] == "progress"
  abort "expected AppKit normalized progress" unless (progress.dig("appkit", "progressView", "value").to_f - 0.65).abs < 0.001

  image = by_test_id.fetch("mac.example.image")
  abort "expected AppKit image role" unless image["role"] == "image"
  abort "expected AppKit image size" unless image.dig("appkit", "imageView", "imageSize", "width") == 24 && image.dig("appkit", "imageView", "imageSize", "height") == 24
  abort "native AX child should not be present in view snapshot" if by_test_id["mac.example.nativeAX.action"]
  by_test_id.fetch("mac.example.swiftui.host")
  swiftui_probe = by_test_id.fetch("mac.example.swiftui.probe")
  abort "expected SwiftUI probe NSViewRepresentable class evidence" unless swiftui_probe.dig("appkit", "className") == "NSView"
  swiftui_probe_frame = swiftui_probe.fetch("frame")
  abort "expected macOS SwiftUI probe bounds width" unless swiftui_probe_frame.fetch("width").to_f > 100
  abort "expected macOS SwiftUI probe bounds height" unless swiftui_probe_frame.fetch("height").to_f > 40

  accessibility = JSON.parse(File.read(ARGV.fetch(14)))
  ax_nodes = accessibility.fetch("nodes")
  native_ax = ax_nodes.values.find { |node| node["testID"] == "mac.example.nativeAX.action" }
  host = by_test_id.fetch("mac.example.nativeAX.host")
  abort "missing native AppKit accessibility element" unless native_ax
  abort "expected native AppKit accessibility ref" unless native_ax["ref"].start_with?("ax-native-#{host.fetch("ref")}-")
  abort "expected native AX sourceRef to host view" unless native_ax["sourceRef"] == host.fetch("ref")
  abort "expected native AX parentRef to host accessibility node" unless native_ax["parentRef"] == "ax-#{host.fetch("ref")}"
  abort "expected native AX button role" unless native_ax["role"] == "button"
  abort "expected native AX label" unless native_ax["label"] == "Native AX Action"
  abort "expected native AX value" unless native_ax["value"] == "available"
  abort "expected native AX hint" unless native_ax["hint"] == "Runs the native accessibility fixture"
  abort "expected native AX test id" unless native_ax["testID"] == "mac.example.nativeAX.action"
  abort "expected native AX interactive" unless native_ax["isInteractive"] == true
  abort "expected native AX frame" unless native_ax["frame"]
  abort "expected native AX activation point" unless native_ax["activationPoint"]
  swiftui_probe_ax = ax_nodes.values.find { |node| node["testID"] == "mac.example.swiftui.probe" }
  abort "missing macOS SwiftUI probe accessibility node" unless swiftui_probe_ax && swiftui_probe_ax["label"] == "macOS SwiftUI probe"
  abort "expected macOS SwiftUI probe native accessibility source ref" unless swiftui_probe_ax["sourceRef"] == swiftui_probe.fetch("ref")

  logs = JSON.parse(File.read(ARGV.fetch(3)))
  abort "missing mac_example_visible log" unless logs.any? { |entry| entry["message"] == "mac_example_visible" }
  abort "missing macOS empty-feed diagnostic log" unless logs.any? { |entry| entry["message"] == "mac_example_empty_feed" && entry.dig("metadata", "reason", "value") == "api_returned_empty_items" }

  network = JSON.parse(File.read(ARGV.fetch(4)))
  event = network.find { |entry| entry["url"]&.include?("/__loupe_network_fixture/macos/workbench") }
  abort "missing macOS network fixture" unless event
  abort "expected macOS network status 200" unless event["statusCode"] == 200
  abort "expected macOS GET method" unless event["method"] == "GET"
  abort "expected macOS network metadata" unless event.dig("metadata", "screen", "value") == "workbench"
  abort "expected macOS automatic network capture" unless event.dig("metadata", "captureKind", "value") == "automatic" && event.dig("metadata", "source", "value") == "urlProtocol"
  abort "expected macOS response body" unless event["responseBody"]&.include?("macOS")
  feed_event = network.find { |entry| entry["url"]&.include?("/__loupe_network_fixture/macos/feed") }
  abort "missing macOS empty feed network fixture" unless feed_event
  abort "expected macOS empty feed 204" unless feed_event["statusCode"] == 204
  abort "expected macOS empty feed metadata" unless feed_event.dig("metadata", "empty", "value") == true
  abort "expected macOS empty feed response body" unless feed_event["responseBody"]&.include?("\"items\":[]")
  error_event = network.find { |entry| entry["url"]&.include?("/__loupe_network_fixture/macos/error-route") }
  abort "missing macOS error-route network fixture" unless error_event
  abort "expected macOS error-route 503" unless error_event["statusCode"] == 503
  abort "expected macOS error-route metadata" unless error_event.dig("metadata", "screen", "value") == "error" && error_event.dig("metadata", "retry", "value") == true
  abort "expected macOS error-route response body" unless error_event["responseBody"]&.include?("feed_service_unavailable")

  refs = JSON.parse(File.read(ARGV.fetch(8)))
  abort "missing macOS reference evidence" unless refs.any? { |entry| entry["owner"] == "MacWorkbenchController" && entry["target"] == "DeviceActuationService" }
  abort "missing macOS weak reference evidence" unless refs.any? { |entry| entry["owner"] == "MacLegacyFlowCoordinator" && entry["target"] == "DeviceActuationService" && entry["kind"] == "weak" }

  graph = JSON.parse(File.read(ARGV.fetch(18)))
  abort "expected app-authored reference graph kind" unless graph["evidenceKind"] == "app-authored-reference-evidence"
  abort "expected graph target" unless graph["target"] == "DeviceActuationService"
  graph_owners = graph.fetch("owners").map { |entry| entry["owner"] }
  abort "expected MacWorkbenchController owner in graph" unless graph_owners.include?("MacWorkbenchController")
  abort "expected MacLegacyFlowCoordinator owner in graph" unless graph_owners.include?("MacLegacyFlowCoordinator")
  abort "expected graph owner evidence ids" unless graph.fetch("owners").all? { |entry| entry["evidenceID"].is_a?(String) && !entry["evidenceID"].empty? }
  abort "expected graph edge to DeviceActuationService" unless graph.fetch("edges").any? { |edge| edge["target"] == "DeviceActuationService" && edge["owner"] == "MacWorkbenchController" }
  abort "expected graph edge evidence ids" unless graph.fetch("edges").all? { |edge| edge["evidenceID"].is_a?(String) && !edge["evidenceID"].empty? }
  abort "expected graph node for DeviceActuationService" unless graph.fetch("nodes").any? { |node| node["name"] == "DeviceActuationService" && node["incomingCount"].to_i >= 2 }

  classes = JSON.parse(File.read(ARGV.fetch(41)))
  abort "expected ObjC class-list evidence" unless classes["evidenceKind"] == "objc-runtime-class-list"
  abort "expected DeviceActuationService class" unless classes.fetch("classes").any? { |entry| entry["name"] == "DeviceActuationService" }
  description = JSON.parse(File.read(ARGV.fetch(42)))
  abort "expected DeviceActuationService class description" unless description["name"] == "DeviceActuationService" && description["evidenceKind"] == "objc-runtime-class-description"
  leaks = JSON.parse(File.read(ARGV.fetch(43)))
  abort "expected weak lifetime probe evidence" unless leaks["evidenceKind"] == "weak-lifetime-probe"
  abort "expected alive DeviceActuationService probe" unless leaks.fetch("probes").any? { |probe| probe["name"] == "DeviceActuationService" && probe["isAlive"] == true && probe["expectedDeallocated"] == true }

  flag = JSON.parse(File.read(ARGV.fetch(5)))
  abort "expected mac-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(6)))
  abort "expected mac-new-nav=true after set" unless flag_set.dig("after", "value") == true
  new_nav_logs = JSON.parse(File.read(ARGV.fetch(23)))
  abort "missing macOS new-nav flow log" unless new_nav_logs.any? { |entry| entry["message"] == "mac_example_new_nav_flow" }

  empty_flag = JSON.parse(File.read(ARGV.fetch(16)))
  abort "expected mac-empty-feed=true" unless empty_flag.dig("value", "value") == true

  keychain = JSON.parse(File.read(ARGV.fetch(9)))
  abort "missing macOS keychain fixture metadata" unless keychain.any? { |entry| entry["service"] == "dev.loupe.macos-example" && entry["account"] == "fixture" }
  logout_flag_set = JSON.parse(File.read(ARGV.fetch(24)))
  abort "expected mac-logout set response" unless logout_flag_set.dig("after", "value") == true
  keychain_after_logout = JSON.parse(File.read(ARGV.fetch(25)))
  abort "expected macOS logout to clear keychain fixture" if keychain_after_logout.any? { |entry| entry["service"] == "dev.loupe.macos-example" && entry["account"] == "fixture" }
  logout_logs = JSON.parse(File.read(ARGV.fetch(26)))
  abort "missing macOS logout keychain-clear log" unless logout_logs.any? { |entry| entry["message"] == "mac_example_logout_cleared_keychain" }

  hit = JSON.parse(File.read(ARGV.fetch(10)))
  abort "expected mac.example.refresh hit-test" unless hit["hitTestID"] == "mac.example.refresh"

  responder = JSON.parse(File.read(ARGV.fetch(11)))
  abort "expected mac.example.refresh responder chain" unless responder.fetch("responderChain").any? { |entry| entry["testID"] == "mac.example.refresh" }

  perf = JSON.parse(File.read(ARGV.fetch(17)))
  abort "expected macOS perf target" unless perf["testID"] == "mac.example.list"
  abort "expected macOS runtime perf without trace dir" unless perf["traceDirectory"].nil?
  abort "expected macOS scroll before offset" unless perf["beforeOffset"].is_a?(Hash)
  abort "expected macOS scroll after offset" unless perf["afterOffset"].is_a?(Hash)
  abort "expected macOS positive scroll delta" unless perf.dig("delta", "y").to_f > 0
  abort "expected macOS profile elapsed" unless perf["actionElapsed"].to_f >= 0

  detail_snapshot = JSON.parse(File.read(ARGV.fetch(27)))
  detail_ids = detail_snapshot.fetch("nodes").values.map { |node| node["testID"] }.compact
  abort "expected macOS detail route root" unless detail_ids.include?("mac.example.detail")
  abort "expected macOS detail route summary" unless detail_ids.include?("mac.example.detail.summary")
  detail_scroll = detail_snapshot.fetch("nodes").values.find { |node| node["testID"] == "mac.example.detail.scroll" }
  abort "expected macOS detail scroll route" unless detail_scroll && detail_scroll.dig("appkit", "scrollView", "contentSize", "height").to_f > detail_scroll.fetch("frame").fetch("height").to_f
  detail_perf = JSON.parse(File.read(ARGV.fetch(28)))
  abort "expected macOS detail scroll target" unless detail_perf["testID"] == "mac.example.detail.scroll"
  abort "expected macOS detail positive scroll delta" unless detail_perf.dig("delta", "y").to_f > 0

  long_snapshot = JSON.parse(File.read(ARGV.fetch(31)))
  long_ids = long_snapshot.fetch("nodes").values.map { |node| node["testID"] }.compact
  abort "expected macOS long-list route root" unless long_ids.include?("mac.example.longList")
  abort "expected macOS long-list route scroll" unless long_ids.include?("mac.example.longList.scroll")
  long_perf = JSON.parse(File.read(ARGV.fetch(32)))
  abort "expected macOS long-list scroll target" unless long_perf["testID"] == "mac.example.longList.scroll"
  abort "expected macOS long-list positive scroll delta" unless long_perf.dig("delta", "y").to_f > 0

  [ARGV.fetch(29), ARGV.fetch(30), ARGV.fetch(33), ARGV.fetch(34)].each do |trace|
    ["action-before.json", "action-target.json", "action-after.json", "before-snapshot.json", "after-snapshot.json", "before-accessibility.json", "after-accessibility.json", "before-logs.json", "after-logs.json"].each do |name|
      abort "missing macOS runtime route trace #{trace}/#{name}" unless File.exist?(File.join(trace, name))
    end
    action = JSON.parse(File.read(File.join(trace, "action-target.json")))
    abort "expected macOS runtime tap trace" unless action["command"] == "tap" && action["backend"] == "runtime"
  end

  route_logs = JSON.parse(File.read(ARGV.fetch(35)))
  abort "missing macOS detail route log" unless route_logs.any? { |entry| entry["message"] == "mac_example_detail_route" }
  abort "missing macOS long-list route log" unless route_logs.any? { |entry| entry["message"] == "mac_example_long_list_route" }
  abort "missing macOS SwiftUI route log" unless route_logs.any? { |entry| entry["message"] == "mac_example_swiftui_route" }
  abort "missing macOS workbench route log" unless route_logs.any? { |entry| entry["message"] == "mac_example_workbench_route" }

  mutation = JSON.parse(File.read(ARGV.fetch(19)))
  abort "expected AppKit text mutation property" unless mutation["property"] == "text"
  abort "expected AppKit mutation target" unless mutation.dig("target", "testID") == "mac.example.status"
  abort "expected AppKit mutation before text" unless mutation.dig("before", "renderedText") == "Logged out"
  abort "expected AppKit mutation after text" unless mutation.dig("after", "renderedText") == "AppKit mutation applied"
  abort "expected AppKit mutation effective value" unless mutation.dig("effective", "value") == "AppKit mutation applied"
  abort "expected AppKit mutation changed" unless mutation["changed"] == true

  env = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected dark appearance" unless env["appearance"] == "dark"

  audit = JSON.parse(File.read(ARGV.fetch(12)))
  dark_snapshot = JSON.parse(File.read(ARGV.fetch(20)))
  target_ids = ["mac.example.title", "mac.example.status", "mac.example.refresh"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected macOS dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
  dark_status = dark_snapshot.fetch("nodes").values.find { |node| node["testID"] == "mac.example.status" }
  abort "expected dark snapshot after AppKit mutation" unless dark_status && dark_status["renderedText"] == "AppKit mutation applied"
  bad_sentinel = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && issue["testID"] == "mac.example.dark.badContrast" }
  abort "expected macOS dark contrast sentinel issue" if bad_sentinel.empty?

  error_flag = JSON.parse(File.read(ARGV.fetch(36)))
  abort "expected mac-error-route=false" unless error_flag.dig("value", "value") == false
  error_flag_set = JSON.parse(File.read(ARGV.fetch(37)))
  abort "expected mac-error-route=true after set" unless error_flag_set.dig("after", "value") == true
  error_snapshot = JSON.parse(File.read(ARGV.fetch(38)))
  error_ids = error_snapshot.fetch("nodes").values.map { |node| node["testID"] }.compact
  abort "expected macOS error route root" unless error_ids.include?("mac.example.error")
  abort "expected macOS error route title" unless error_ids.include?("mac.example.error.title")
  abort "expected macOS error route retry banner" unless error_ids.include?("mac.example.error.retryBanner")
  error_root = JSON.parse(File.read(ARGV.fetch(39))).fetch("node")
  abort "expected macOS error route platform metadata" unless error_root.fetch("custom").dig("platform", "value") == "macOS"
  error_logs = JSON.parse(File.read(ARGV.fetch(40)))
  abort "missing macOS error-route log" unless error_logs.any? { |entry| entry["message"] == "mac_example_error_route" && entry.dig("metadata", "reason", "value") == "feed_service_unavailable" }
' "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$REFS_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$AUDIT_PATH" "$INSPECT_TITLE_PATH" "$ACCESSIBILITY_PATH" "$INSPECT_EMPTY_PATH" "$EMPTY_FLAG_PATH" "$PERF_PATH" "$OBJECT_GRAPH_PATH" "$MUTATION_PATH" "$DARK_SNAPSHOT_PATH" "$VIEW_TREE_PATH" "$ACCESSIBILITY_TREE_PATH" "$NEW_NAV_LOGS_PATH" "$LOGOUT_FLAG_SET_PATH" "$KEYCHAIN_AFTER_LOGOUT_PATH" "$LOGOUT_LOGS_PATH" "$DETAIL_SNAPSHOT_PATH" "$DETAIL_SCROLL_PATH" "$DETAIL_TRACE_DIR" "$DETAIL_BACK_TRACE_DIR" "$LONG_LIST_SNAPSHOT_PATH" "$LONG_LIST_SCROLL_PATH" "$LONG_LIST_TRACE_DIR" "$LONG_LIST_BACK_TRACE_DIR" "$ROUTE_LOGS_PATH" "$ERROR_FLAG_PATH" "$ERROR_FLAG_SET_PATH" "$ERROR_SNAPSHOT_PATH" "$ERROR_INSPECT_PATH" "$ERROR_LOGS_PATH" "$OBJECT_CLASSES_PATH" "$OBJECT_DESCRIPTION_PATH" "$LEAKS_PATH"

echo "macOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
