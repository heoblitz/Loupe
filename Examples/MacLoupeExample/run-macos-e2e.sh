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
ACCESSIBILITY_PATH="/tmp/loupe-macos-accessibility.json"
LOGS_PATH="/tmp/loupe-macos-logs.json"
NETWORK_PATH="/tmp/loupe-macos-network.json"
REFS_PATH="/tmp/loupe-macos-refs.json"
OBJECT_GRAPH_PATH="/tmp/loupe-macos-object-graph.json"
FLAG_PATH="/tmp/loupe-macos-flag.json"
FLAG_SET_PATH="/tmp/loupe-macos-flag-set.json"
EMPTY_FLAG_PATH="/tmp/loupe-macos-empty-flag.json"
KEYCHAIN_PATH="/tmp/loupe-macos-keychain.json"
HIT_TEST_PATH="/tmp/loupe-macos-hit-test.json"
RESPONDER_PATH="/tmp/loupe-macos-responder-chain.json"
ENV_PATH="/tmp/loupe-macos-env.json"
AUDIT_PATH="/tmp/loupe-macos-audit.json"
PERF_PATH="/tmp/loupe-macos-perf.json"
INSPECT_PATH="/tmp/loupe-macos-inspect.json"
INSPECT_TITLE_PATH="/tmp/loupe-macos-inspect-title.json"
INSPECT_EMPTY_PATH="/tmp/loupe-macos-inspect-empty.json"
QUERY_PATH="/tmp/loupe-macos-query.json"

rm -f "$APP_LOG" "$SNAPSHOT_PATH" "$DARK_SNAPSHOT_PATH" "$ACCESSIBILITY_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$REFS_PATH" "$OBJECT_GRAPH_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$EMPTY_FLAG_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$AUDIT_PATH" "$PERF_PATH" "$INSPECT_PATH" "$INSPECT_TITLE_PATH" "$INSPECT_EMPTY_PATH" "$QUERY_PATH"

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
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id mac.example.emptyFeed > "$INSPECT_EMPTY_PATH"
.build/debug/loupe observe fetch "$HOST/accessibility" --timeout 10 --output "$ACCESSIBILITY_PATH" >/dev/null
.build/debug/loupe debug console --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe debug object-graph DeviceActuationService --host "$HOST" --output "$OBJECT_GRAPH_PATH" >/dev/null
.build/debug/loupe state flags get mac-new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe state flags set mac-new-nav --bool true --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe state flags get mac-empty-feed --host "$HOST" --output "$EMPTY_FLAG_PATH" >/dev/null
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
.build/debug/loupe perf scroll --host "$HOST" --test-id mac.example.list --delta 0,40 --output "$PERF_PATH" >/dev/null
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

  by_test_id = snapshot.fetch("nodes").values.each_with_object({}) { |node, map| map[node["testID"]] = node if node["testID"] }
  abort "missing mac.example.emptyFeed" unless by_test_id["mac.example.emptyFeed"]
  empty = JSON.parse(File.read(ARGV.fetch(15))).fetch("node")
  abort "expected AppKit empty feed scroll view" unless empty.dig("uiKit", "className") == "NSScrollView"
  abort "expected empty feed role" unless empty["role"] == "scrollView"
  empty_rows = snapshot.fetch("nodes").values.select { |node| node["testID"]&.start_with?("mac.example.emptyFeed.row") }
  abort "expected no rendered empty feed rows" unless empty_rows.empty?

  segmented = by_test_id.fetch("mac.example.segmented")
  abort "expected AppKit segmented role" unless segmented["role"] == "segmentedControl"
  abort "expected AppKit segmented selection" unless segmented.dig("uiKit", "segmentedControl", "selectedSegmentIndex") == 1
  abort "expected AppKit segmented labels" unless segmented.dig("uiKit", "segmentedControl", "segments") == ["List", "Detail"]

  slider = by_test_id.fetch("mac.example.slider")
  abort "expected AppKit slider role" unless slider["role"] == "slider"
  abort "expected AppKit slider value" unless slider.dig("uiKit", "slider", "value") == 42
  abort "expected AppKit slider range" unless slider.dig("uiKit", "slider", "minimumValue") == 0 && slider.dig("uiKit", "slider", "maximumValue") == 100

  stepper = by_test_id.fetch("mac.example.stepper")
  abort "expected AppKit stepper role" unless stepper["role"] == "stepper"
  abort "expected AppKit stepper value" unless stepper.dig("uiKit", "stepper", "value") == 4
  abort "expected AppKit stepper increment" unless stepper.dig("uiKit", "stepper", "stepValue") == 2

  progress = by_test_id.fetch("mac.example.progress")
  abort "expected AppKit progress role" unless progress["role"] == "progress"
  abort "expected AppKit normalized progress" unless (progress.dig("uiKit", "progressView", "value").to_f - 0.65).abs < 0.001

  image = by_test_id.fetch("mac.example.image")
  abort "expected AppKit image role" unless image["role"] == "image"
  abort "expected AppKit image size" unless image.dig("uiKit", "imageView", "imageSize", "width") == 24 && image.dig("uiKit", "imageView", "imageSize", "height") == 24
  abort "native AX child should not be present in view snapshot" if by_test_id["mac.example.nativeAX.action"]

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

  logs = JSON.parse(File.read(ARGV.fetch(3)))
  abort "missing mac_example_visible log" unless logs.any? { |entry| entry["message"] == "mac_example_visible" }
  abort "missing macOS empty-feed diagnostic log" unless logs.any? { |entry| entry["message"] == "mac_example_empty_feed" && entry.dig("metadata", "reason", "value") == "api_returned_empty_items" }

  network = JSON.parse(File.read(ARGV.fetch(4)))
  event = network.find { |entry| entry["url"] == "https://api.example.test/macos/workbench" }
  abort "missing macOS network fixture" unless event
  abort "expected macOS network status 200" unless event["statusCode"] == 200
  abort "expected macOS GET method" unless event["method"] == "GET"
  abort "expected macOS network metadata" unless event.dig("metadata", "screen", "value") == "workbench"
  abort "expected macOS response body" unless event["responseBody"]&.include?("macOS")
  feed_event = network.find { |entry| entry["url"] == "https://api.example.test/macos/feed" }
  abort "missing macOS empty feed network fixture" unless feed_event
  abort "expected macOS empty feed 204" unless feed_event["statusCode"] == 204
  abort "expected macOS empty feed metadata" unless feed_event.dig("metadata", "empty", "value") == true
  abort "expected macOS empty feed response body" unless feed_event["responseBody"]&.include?("\"items\":[]")

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

  flag = JSON.parse(File.read(ARGV.fetch(5)))
  abort "expected mac-new-nav=false" unless flag.dig("value", "value") == false

  flag_set = JSON.parse(File.read(ARGV.fetch(6)))
  abort "expected mac-new-nav=true after set" unless flag_set.dig("after", "value") == true

  empty_flag = JSON.parse(File.read(ARGV.fetch(16)))
  abort "expected mac-empty-feed=true" unless empty_flag.dig("value", "value") == true

  keychain = JSON.parse(File.read(ARGV.fetch(9)))
  abort "missing macOS keychain fixture metadata" unless keychain.any? { |entry| entry["service"] == "dev.loupe.macos-example" && entry["account"] == "fixture" }

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

  env = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected dark appearance" unless env["appearance"] == "dark"

  audit = JSON.parse(File.read(ARGV.fetch(12)))
  target_ids = ["mac.example.title", "mac.example.status", "mac.example.refresh"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected macOS dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
  bad_sentinel = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && issue["testID"] == "mac.example.dark.badContrast" }
  abort "expected macOS dark contrast sentinel issue" if bad_sentinel.empty?
' "$SNAPSHOT_PATH" "$QUERY_PATH" "$INSPECT_PATH" "$LOGS_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$FLAG_SET_PATH" "$ENV_PATH" "$REFS_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$AUDIT_PATH" "$INSPECT_TITLE_PATH" "$ACCESSIBILITY_PATH" "$INSPECT_EMPTY_PATH" "$EMPTY_FLAG_PATH" "$PERF_PATH" "$OBJECT_GRAPH_PATH"

echo "macOS example E2E passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "logs: $LOGS_PATH"
