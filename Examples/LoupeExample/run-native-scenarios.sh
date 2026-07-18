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

simctl_list_timeout() {
  ruby -e 'value = ENV.fetch("LOUPE_SIMCTL_LIST_TIMEOUT", "60").to_f; puts(value.positive? ? value.to_i : 60)'
}

booted_udid() {
  local list_path="/tmp/loupe-native-booted-devices.json"
  run_with_timeout "$(simctl_list_timeout)" xcrun simctl list devices booted --json >"$list_path"
  ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("iPhone") }
    puts booted && booted["udid"]
  ' <"$list_path"
}

DEVICE="${LOUPE_DEVICE:-$(booted_udid)}"
if [[ -z "$DEVICE" ]]; then
  DEVICES_PATH="/tmp/loupe-native-available-devices.txt"
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
  local log_path="/tmp/loupe-native-bootstatus.log"
  if run_with_timeout 90 xcrun simctl bootstatus "$DEVICE" -b >"$log_path" 2>&1; then
    return
  fi

  if run_with_timeout 5 xcrun simctl spawn "$DEVICE" launchctl print system >/dev/null 2>&1; then
    echo "warning: bootstatus timed out, but simulator launchd responds; continuing" >&2
    return
  fi

  xcrun simctl io "$DEVICE" screenshot /tmp/loupe-native-boot-not-ready.png >/dev/null 2>&1 || true
  echo "error: simulator $DEVICE did not finish booting; see $log_path and /tmp/loupe-native-boot-not-ready.png" >&2
  tail -40 "$log_path" >&2 || true
  exit 124
}

assert_device_ready
swift build
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,id=$DEVICE"

terminate_app
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"

HOST=""
SNAPSHOT_PATH="/tmp/loupe-native-snapshot.json"
OBSERVATION_PATH="/tmp/loupe-native-observation.json"
ACCESSIBILITY_PATH="/tmp/loupe-native-accessibility.json"
INSPECT_PATH="/tmp/loupe-native-inspect.json"
AUDIT_PATH="/tmp/loupe-native-audit.json"
SUBTREE_PATH="/tmp/loupe-native-subtree.json"
TRACE_DIR="/tmp/loupe-native-trace"
TRACE_SUMMARY_PATH="/tmp/loupe-native-trace-summary.txt"
FRAME_MUTATION_PATH="/tmp/loupe-native-frame-mutation.json"
LAYOUT_MUTATION_PATH="/tmp/loupe-native-layout-mutation.json"
STACK_MUTATION_PATH="/tmp/loupe-native-stack-mutation.json"
APPLY_DESIGN_FIXTURE_PATH="/tmp/loupe-native-apply-design.json"
APPLY_DESIGN_COMPARE_PATH="/tmp/loupe-native-apply-design-compare.json"
APPLY_DESIGN_TRACE_DIR="/tmp/loupe-native-apply-design-suggestions"
SELF_SIZING_SKIP_PATH="/tmp/loupe-native-self-sizing-skip.json"
SELF_SIZING_MUTATION_PATH="/tmp/loupe-native-self-sizing-mutation.json"
SELF_SIZING_ALREADY_PATH="/tmp/loupe-native-self-sizing-already.json"
CONSTRAINTS_PATH="/tmp/loupe-native-constraints.json"
CONSTRAINT_MUTATION_PATH="/tmp/loupe-native-constraint-mutation.json"
CONSTRAINT_DEACTIVATE_PATH="/tmp/loupe-native-constraint-deactivate.json"
rm -rf "$TRACE_DIR" "$APPLY_DESIGN_TRACE_DIR"

launch_app() {
  local route="${1:-}"
  terminate_app
  local arguments=(
    --device "$DEVICE"
    --bundle-id dev.loupe.example
    --inject
    --timeout "$LAUNCH_TIMEOUT"
  )
  if [[ -n "$PORT" ]]; then
    arguments+=(--env "LOUPE_PORT=$PORT")
  fi
  if [[ -n "$route" ]]; then
    arguments+=(--env "LOUPE_EXAMPLE_ROUTE=$route")
  fi
  local launch_output
  launch_output="$(.build/debug/loupe app launch "${arguments[@]}")"
  HOST="$(awk '/^loupe host: / { print $3 }' <<<"$launch_output" | tail -1)"
  if [[ -z "$HOST" ]]; then
    echo "error: loupe app launch did not report a runtime host" >&2
    echo "$launch_output" >&2
    exit 1
  fi
  sleep 2
}

fetch_snapshot() {
  .build/debug/loupe ui snapshot --host "$HOST" --timeout 10 --output "$SNAPSHOT_PATH"
}

assert_query() {
  local test_id="$1"
  local output_path="$2"
  .build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id "$test_id" > "$output_path"
  grep -q '"ref"' "$output_path"
}

query_ref() {
  local test_id="$1"
  .build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id "$test_id" --max-results 1 |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch(0).fetch("ref")'
}

query_nav_back_ref() {
  local ref
  ref="$(
    .build/debug/loupe ui query "$SNAPSHOT_PATH" --text Back --max-results 1 |
      ruby -rjson -e '
        results = JSON.parse(STDIN.read)
        puts results.dig(0, "ref").to_s
      '
  )"
  if [[ -n "$ref" ]]; then
    printf '%s\n' "$ref"
    return
  fi

  .build/debug/loupe ui query "$SNAPSHOT_PATH" --role button --max-results 1 |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch(0).fetch("ref")'
}

inspect_value() {
  local test_id="$1"
  local path="$2"
  .build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id "$test_id" |
    ruby -rjson -e '
      value = JSON.parse(STDIN.read)
      ARGV.fetch(0).split(".").each { |key| value = value.fetch(key) }
      puts value
    ' "$path"
}

launch_app
fetch_snapshot
read -r WIDTH HEIGHT < <(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  size = snapshot.fetch("screen").fetch("size")
  puts [size.fetch("width"), size.fetch("height")].join(" ")
' "$SNAPSHOT_PATH")
MID_Y="$(ruby -e 'puts (ARGV.fetch(0).to_f * 0.45).round' "$HEIGHT")"
END_X="$(ruby -e 'puts (ARGV.fetch(0).to_f - 24).round' "$WIDTH")"

echo "case: bottom sheet grabber tap expands and internal scroll moves"
launch_app bottomSheet
.build/debug/loupe act wait visible --host "$HOST" --test-id example.bottomSheet.grabber --timeout 5 >/tmp/loupe-native-wait-bottomsheet.json
fetch_snapshot
assert_query example.bottomSheet.scrollView /tmp/loupe-native-bottomsheet-scroll-query.json
COLLAPSED_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
COLLAPSED_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
read -r GRABBER_X GRABBER_Y < <(.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.bottomSheet.grabber |
  ruby -rjson -e '
    frame = JSON.parse(STDIN.read).fetch("node").fetch("frame")
    puts [(frame.fetch("x") + frame.fetch("width") / 2.0).round, (frame.fetch("y") + frame.fetch("height") / 2.0).round].join(" ")
  ')
DRAG_END_Y="$(ruby -e 'puts [(ARGV.fetch(0).to_f - 280).round, 80].max' "$GRABBER_Y")"
.build/debug/loupe act drag --host "$HOST" --udid "$DEVICE" --from "$GRABBER_X,$GRABBER_Y" --to "$GRABBER_X,$DRAG_END_Y" --duration 0.5 --trace-dir /tmp/loupe-native-bottomsheet-grabber-drag-trace
fetch_snapshot
AFTER_DRAG_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
AFTER_DRAG_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
ruby -e '
  y_same = (ARGV.fetch(0).to_f - ARGV.fetch(1).to_f).abs < 8
  height_same = (ARGV.fetch(2).to_f - ARGV.fetch(3).to_f).abs < 8
  exit(y_same && height_same ? 0 : 1)
' "$COLLAPSED_Y" "$AFTER_DRAG_Y" "$COLLAPSED_HEIGHT" "$AFTER_DRAG_HEIGHT"
GRABBER_REF="$(query_ref example.bottomSheet.grabber)"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --snapshot "$SNAPSHOT_PATH" --ref "$GRABBER_REF" --expect-visible example.bottomSheet.expandedMarker
fetch_snapshot
EXPANDED_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
EXPANDED_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
CONTENT_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.uikit.scrollView.contentSize.height)"
ruby -e '
  moved_up = ARGV.fetch(0).to_f < ARGV.fetch(1).to_f - 120
  grew = ARGV.fetch(2).to_f > ARGV.fetch(3).to_f + 120
  long_list = ARGV.fetch(4).to_f > ARGV.fetch(2).to_f + 400
  exit(moved_up && grew && long_list ? 0 : 1)
' "$EXPANDED_Y" "$COLLAPSED_Y" "$EXPANDED_HEIGHT" "$COLLAPSED_HEIGHT" "$CONTENT_HEIGHT"

echo "case: navigation pop by ref from routed detail screen"
launch_app detail
.build/debug/loupe act wait visible --host "$HOST" --test-id example.detail --timeout 5 >/tmp/loupe-native-wait-detail.json
fetch_snapshot
assert_query example.detail /tmp/loupe-native-detail-query.json
DETAIL_BACK_REF="$(query_nav_back_ref)"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --snapshot "$SNAPSHOT_PATH" --ref "$DETAIL_BACK_REF"
.build/debug/loupe act wait visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-native-wait-list.json
fetch_snapshot
assert_query example.customerList /tmp/loupe-native-list-query.json

echo "case: navigation push by testID tap, then pop by ref tap"
launch_app
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id example.openComponents --trace-dir "$TRACE_DIR" --expect-visible example.components
.build/debug/loupe act wait visible --host "$HOST" --test-id example.components --timeout 5 >/tmp/loupe-native-wait-components.json
fetch_snapshot
assert_query example.components /tmp/loupe-native-components-query.json
test -f "$TRACE_DIR/before-logs.json"
test -f "$TRACE_DIR/after-logs.json"
test -f "$TRACE_DIR/action-target.json"
grep -q '"phase" : "target"' "$TRACE_DIR/action-target.json"
grep -q '"resolvedTarget"' "$TRACE_DIR/action-target.json"
.build/debug/loupe debug trace summary "$TRACE_DIR" > "$TRACE_SUMMARY_PATH"
grep -q "example_components_visible" "$TRACE_SUMMARY_PATH"
.build/debug/loupe ui subtree "$SNAPSHOT_PATH" --test-id example.components --depth 4 > "$SUBTREE_PATH"
grep -q '"root"' "$SUBTREE_PATH"
grep -q '"example.components.switch"' "$SUBTREE_PATH"
BACK_REF="$(query_ref example.components.back)"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --snapshot "$SNAPSHOT_PATH" --ref "$BACK_REF"
.build/debug/loupe act wait visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-native-wait-list-after-ref-tap.json

echo "case: routed UIKit component screen"
launch_app components
.build/debug/loupe act wait visible --host "$HOST" --test-id example.components --timeout 5 >/tmp/loupe-native-wait-components-routed.json
fetch_snapshot

echo "case: accessibility action targets are copyable and one-shot"
TARGETS_PATH="/tmp/loupe-native-action-targets.txt"
TARGETS_RETRY_OUT="/tmp/loupe-native-action-targets-retry.out"
TARGETS_RETRY_ERR="/tmp/loupe-native-action-targets-retry.err"
.build/debug/loupe act targets --host "$HOST" --udid "$DEVICE" > "$TARGETS_PATH"
grep -Eq '^App: .+$' "$TARGETS_PATH"
if grep -Eq 'testID=|frame=|point=' "$TARGETS_PATH"; then
  echo "error: default action targets leaked internal fields" >&2
  exit 1
fi
DONE_ALIAS="$(ruby -e '
  matches = File.readlines(ARGV.fetch(0), chomp: true).select { |line| line.match?(/\A#\d+ button "Done" \[/) }
  abort "expected exactly one Done action target, got #{matches.inspect}" unless matches.length == 1
  puts matches.fetch(0)[/\A#\d+/]
' "$TARGETS_PATH")"
.build/debug/loupe act tap "$DONE_ALIAS" --host "$HOST" --udid "$DEVICE"
TARGET_DONE_NODE_PATH="/tmp/loupe-native-target-done-node.json"
TARGET_DONE=false
for _ in {1..20}; do
  fetch_snapshot
  if .build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.button >"$TARGET_DONE_NODE_PATH" &&
      grep -q '"renderedText" : "Done"' "$TARGET_DONE_NODE_PATH"; then
    TARGET_DONE=true
    break
  fi
  sleep 0.25
done
if [[ "$TARGET_DONE" != "true" ]]; then
  echo "error: Done action target did not update the primary button within 5 seconds" >&2
  exit 1
fi
if .build/debug/loupe act tap "$DONE_ALIAS" --host "$HOST" --udid "$DEVICE" >"$TARGETS_RETRY_OUT" 2>"$TARGETS_RETRY_ERR"; then
  echo "error: consumed action target unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'loupe act targets' "$TARGETS_RETRY_ERR"

echo "case: accessibility action discovery and semantic execution"
TARGETS_ACTIONS_PATH="/tmp/loupe-native-action-capabilities.txt"
.build/debug/loupe act targets --host "$HOST" --udid "$DEVICE" > "$TARGETS_ACTIONS_PATH"
grep -E -q 'slider .*\[.*increment.*decrement' "$TARGETS_ACTIONS_PATH"
grep -q '"custom:Reset switch"' "$TARGETS_ACTIONS_PATH"
.build/debug/loupe act perform --host "$HOST" --udid "$DEVICE" --test-id example.components.slider --action increment >/tmp/loupe-native-perform-increment.json
grep -q '"action":"increment"' /tmp/loupe-native-perform-increment.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.slider > "$INSPECT_PATH"
ruby -rjson -e '
  node = JSON.parse(File.read(ARGV.fetch(0))).fetch("node")
  value = node.fetch("uikit").fetch("slider").fetch("value")
  abort "slider accessibility increment did not change value" unless value > 42
' "$INSPECT_PATH"
.build/debug/loupe act perform --host "$HOST" --udid "$DEVICE" --test-id example.components.switch --action 'custom:Reset switch' >/tmp/loupe-native-perform-custom.json
grep -q '"action":"custom:Reset switch"' /tmp/loupe-native-perform-custom.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.switch > "$INSPECT_PATH"
grep -q '"isOn" : false' "$INSPECT_PATH"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id example.components.switch
.build/debug/loupe act wait value --host "$HOST" --test-id example.components.switch --key uikit.switch.isOn --equals true --timeout 5 >/tmp/loupe-native-wait-switch-restored.json

echo "case: UIKit component compact and inspect coverage"
.build/debug/loupe ui compact --host "$HOST" --timeout 5 --output "$OBSERVATION_PATH"
.build/debug/loupe ui accessibility --host "$HOST" --timeout 5 --output "$ACCESSIBILITY_PATH"
grep -q '"sourceRef"' "$ACCESSIBILITY_PATH"
grep -q '"example.components.switch"' "$ACCESSIBILITY_PATH"
grep -q '"className" : "UISwitch"' "$OBSERVATION_PATH"
grep -q '"className" : "UISlider"' "$OBSERVATION_PATH"
grep -q '"className" : "UISegmentedControl"' "$OBSERVATION_PATH"

fetch_snapshot
.build/debug/loupe ui accessibility "$SNAPSHOT_PATH" > "$ACCESSIBILITY_PATH"
grep -q '"rootRefs"' "$ACCESSIBILITY_PATH"
.build/debug/loupe ui query "$SNAPSHOT_PATH" --tree accessibility --test-id example.components.switch >/tmp/loupe-native-accessibility-query.json
grep -q '"sourceRef"' /tmp/loupe-native-accessibility-query.json
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.switch > "$INSPECT_PATH"
grep -q '"className" : "UISwitch"' "$INSPECT_PATH"
grep -q '"isOn" : true' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.segmented > "$INSPECT_PATH"
grep -q '"selectedSegmentIndex" : 1' "$INSPECT_PATH"
grep -q '"Large"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.image > "$INSPECT_PATH"
grep -q '"className" : "UIImageView"' "$INSPECT_PATH"
grep -q '"imageSize"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.scrollView > "$INSPECT_PATH"
grep -q '"className" : "UIScrollView"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.stepper > "$INSPECT_PATH"
grep -q '"className" : "UIStepper"' "$INSPECT_PATH"
grep -q '"stepper"' "$INSPECT_PATH"
grep -q '"stepValue" : 2' "$INSPECT_PATH"
grep -q '"value" : 4' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.datePicker > "$INSPECT_PATH"
grep -q '"className" : "UIDatePicker"' "$INSPECT_PATH"
grep -q '"datePicker"' "$INSPECT_PATH"
grep -q '"mode" : "date"' "$INSPECT_PATH"
grep -q '"date"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.tabBar > "$INSPECT_PATH"
grep -q '"className" : "UITabBar"' "$INSPECT_PATH"
grep -q '"tabBar"' "$INSPECT_PATH"
grep -q '"items"' "$INSPECT_PATH"
grep -q '"selectedItem" : "Home"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.collectionView > "$INSPECT_PATH"
grep -q '"className" : "UICollectionView"' "$INSPECT_PATH"
grep -q '"collectionView"' "$INSPECT_PATH"
grep -q '"usesEstimatedItemSize" : false' "$INSPECT_PATH"
assert_query example.components.collection.0 /tmp/loupe-native-collection-cell-query.json

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.selfSizingCollectionView > "$INSPECT_PATH"
grep -q '"className" : "UICollectionView"' "$INSPECT_PATH"
grep -q '"collectionView"' "$INSPECT_PATH"
grep -q '"usesEstimatedItemSize" : true' "$INSPECT_PATH"
assert_query example.components.selfSizingCollection.0 /tmp/loupe-native-self-sizing-collection-cell-query.json

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.pickerView > "$INSPECT_PATH"
grep -q '"className" : "UIPickerView"' "$INSPECT_PATH"
grep -q '"pickerView"' "$INSPECT_PATH"
grep -q '"numberOfComponents" : 1' "$INSPECT_PATH"
grep -q '"selectedRows"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.pageControl > "$INSPECT_PATH"
grep -q '"className" : "UIPageControl"' "$INSPECT_PATH"
grep -q '"currentPage" : 2' "$INSPECT_PATH"
grep -q '"numberOfPages" : 5' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.progress > "$INSPECT_PATH"
grep -q '"className" : "UIProgressView"' "$INSPECT_PATH"
grep -q '"progressView"' "$INSPECT_PATH"
grep -q '"value"' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.activity > "$INSPECT_PATH"
grep -q '"className" : "UIActivityIndicatorView"' "$INSPECT_PATH"
grep -q '"isAnimating" : true' "$INSPECT_PATH"

.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.design.card > "$INSPECT_PATH"
grep -q '"cornerRadius" : 20' "$INSPECT_PATH"
grep -q '"backgroundColor"' "$INSPECT_PATH"
grep -q '"borderWidth" : 2' "$INSPECT_PATH"

echo "case: layout audit emits machine-readable design checks"
.build/debug/loupe ui audit "$SNAPSHOT_PATH" > "$AUDIT_PATH"
grep -q '"issueCount"' "$AUDIT_PATH"
grep -q '"issues"' "$AUDIT_PATH"

echo "case: frame, Auto Layout, and stack view runtime mutations"
.build/debug/loupe ui set --host "$HOST" --test-id example.design.card frame --rect 20,220,320,140 --output "$FRAME_MUTATION_PATH"
grep -q '"property" : "frame"' "$FRAME_MUTATION_PATH"
grep -q '"animation"' "$FRAME_MUTATION_PATH"
grep -q '"duration"' "$FRAME_MUTATION_PATH"
grep -q '"requested"' "$FRAME_MUTATION_PATH"
grep -q '"effective"' "$FRAME_MUTATION_PATH"
grep -q '"changed"' "$FRAME_MUTATION_PATH"

.build/debug/loupe ui set --host "$HOST" --test-id example.components.label layout.hugging.horizontal --number 260.5 --no-animate --output "$LAYOUT_MUTATION_PATH"
grep -q '"property" : "layout.hugging.horizontal"' "$LAYOUT_MUTATION_PATH"
if grep -q '"animation"' "$LAYOUT_MUTATION_PATH"; then
  echo "error: --no-animate mutation unexpectedly included animation" >&2
  exit 1
fi
grep -q '"changed" : true' "$LAYOUT_MUTATION_PATH"
grep -q '"value" : 260.5' "$LAYOUT_MUTATION_PATH"

.build/debug/loupe ui set --host "$HOST" --test-id example.components.switchRow stack.axis vertical --output "$STACK_MUTATION_PATH"
grep -q '"property" : "stack.axis"' "$STACK_MUTATION_PATH"
grep -q '"changed" : true' "$STACK_MUTATION_PATH"
grep -q '"value" : "vertical"' "$STACK_MUTATION_PATH"
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.switchRow > "$INSPECT_PATH"
grep -q '"axis" : "vertical"' "$INSPECT_PATH"

echo "case: compare-design suggestion application"
ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  node = snapshot.fetch("nodes").values.find { |candidate| candidate["testID"] == "example.components.label" }
  abort("missing label node for design suggestion probe") unless node
  screen = snapshot.fetch("screen").fetch("size")
  design = {
    "frame" => {
      "name" => "Apply Design Suggestions Probe",
      "width" => screen.fetch("width"),
      "height" => screen.fetch("height")
    },
    "nodes" => [
      {
        "id" => "probe.components.label",
        "aliases" => ["example.components.label"],
        "name" => "UIKit label color probe",
        "role" => "staticText",
        "text" => node.fetch("text", "UIKit Label"),
        "frame" => node.fetch("frame"),
        "style" => {
          "textColor" => "#FF3366"
        }
      }
    ]
  }
  File.write(ARGV.fetch(1), JSON.pretty_generate(design))
' "$SNAPSHOT_PATH" "$APPLY_DESIGN_FIXTURE_PATH"
.build/debug/loupe ui compare-design "$SNAPSHOT_PATH" "$APPLY_DESIGN_FIXTURE_PATH" --json --suggest-mutations > "$APPLY_DESIGN_COMPARE_PATH"
ruby -rjson -e '
  comparison = JSON.parse(File.read(ARGV.fetch(0)))
  suggestion = comparison.fetch("suggestions").find { |item| item.fetch("property") == "textColor" }
  abort("missing textColor suggestion") unless suggestion
' "$APPLY_DESIGN_COMPARE_PATH"
.build/debug/loupe ui apply-design-suggestions "$APPLY_DESIGN_COMPARE_PATH" --host "$HOST" --snapshot "$SNAPSHOT_PATH" --properties textColor --max 1 --output-dir "$APPLY_DESIGN_TRACE_DIR"
ruby -rjson -e '
  summary = JSON.parse(File.read(File.join(ARGV.fetch(0), "summary.json")))
  abort("expected one selected suggestion") unless summary.fetch("selectedSuggestions") == 1
  abort("expected one mutation request") unless summary.fetch("mutationRequests") == 1
  abort("expected one changed mutation") unless summary.fetch("changedMutations") == 1
  abort("expected no failed mutations") unless summary.fetch("failedMutations") == 0
  application = summary.fetch("applications").fetch(0)
  abort("expected textColor application") unless application.fetch("property") == "textColor"
  abort("missing mutation response path") unless File.file?(application.fetch("response"))
' "$APPLY_DESIGN_TRACE_DIR"
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.components.label > "$INSPECT_PATH"
ruby -rjson -e '
  node = JSON.parse(File.read(ARGV.fetch(0))).fetch("node")
  color = node.fetch("style").fetch("textColor")
  red = color.fetch("red").to_f
  green = color.fetch("green").to_f
  blue = color.fetch("blue").to_f
  abort("textColor mutation did not apply") unless (red - 1).abs < 0.02 && (green - 0.2).abs < 0.03 && (blue - 0.4).abs < 0.03
' "$INSPECT_PATH"

echo "case: collection self-sizing probe only runs for supported sizing contexts"
.build/debug/loupe ui set --host "$HOST" --test-id example.components.collection.0.label layout.hugging.horizontal 260 --try-self-sizing --no-animate --output "$SELF_SIZING_SKIP_PATH"
ruby -rjson -e '
  result = JSON.parse(File.read(ARGV.fetch(0)))
  probe = result.fetch("selfSizingProbe")
  abort("fixed collection unexpectedly attempted self sizing") unless probe.fetch("attempted") == false
  abort("fixed collection unexpectedly applied self sizing") unless probe.fetch("applied") == false
  abort("unexpected fixed collection reason") unless probe.fetch("reason") == "flow_layout_item_size_is_fixed"
  context = probe.fetch("context")
  abort("unexpected fixed collection context") unless context.fetch("containerTestID") == "example.components.collectionView"
' "$SELF_SIZING_SKIP_PATH"

.build/debug/loupe ui set --host "$HOST" --test-id example.components.selfSizingCollection.0.label layout.hugging.horizontal 260 --try-self-sizing --no-animate --output "$SELF_SIZING_MUTATION_PATH"
ruby -rjson -e '
  result = JSON.parse(File.read(ARGV.fetch(0)))
  probe = result.fetch("selfSizingProbe")
  abort("self-sizing collection did not attempt") unless probe.fetch("attempted") == true
  abort("self-sizing collection did not apply") unless probe.fetch("applied") == true
  abort("self-sizing mode not enabled") unless probe.fetch("effectiveMode") == "enabledIncludingConstraints"
  context = probe.fetch("context")
  abort("unexpected self-sizing container") unless context.fetch("containerTestID") == "example.components.selfSizingCollectionView"
  abort("unexpected self-sizing owner") unless context.fetch("sizingOwner") == "estimatedFlowLayoutSelfSizing"
' "$SELF_SIZING_MUTATION_PATH"

.build/debug/loupe ui set --host "$HOST" --test-id example.components.selfSizingCollection.0.label layout.hugging.vertical 252 --try-self-sizing --no-animate --output "$SELF_SIZING_ALREADY_PATH"
ruby -rjson -e '
  result = JSON.parse(File.read(ARGV.fetch(0)))
  probe = result.fetch("selfSizingProbe")
  abort("already-enabled self sizing should not attempt again") unless probe.fetch("attempted") == false
  abort("already-enabled self sizing should stay applied") unless probe.fetch("applied") == true
  abort("unexpected already-enabled reason") unless probe.fetch("reason") == "already_enabledIncludingConstraints"
  warning = result.fetch("warning", "")
  abort("already-enabled result should not emit self-sizing warning") if warning.include?("trySelfSizing")
' "$SELF_SIZING_ALREADY_PATH"

echo "case: Auto Layout constraint listing and mutation"
.build/debug/loupe ui constraints --host "$HOST" --test-id example.design.card --json --output "$CONSTRAINTS_PATH"
DESIGN_CARD_HEIGHT_CONSTRAINT_ID="$(ruby -rjson -e '
  constraints = JSON.parse(File.read(ARGV.fetch(0)))
  constraint = constraints.find { |item|
    item.fetch("firstAttribute") == "height" &&
      item.fetch("firstItem", "").include?("example.design.card")
  }
  abort("missing design card height constraint") unless constraint
  puts constraint.fetch("id")
' "$CONSTRAINTS_PATH")"
.build/debug/loupe ui set-constraint --host "$HOST" --id "$DESIGN_CARD_HEIGHT_CONSTRAINT_ID" constant 104 --output "$CONSTRAINT_MUTATION_PATH"
ruby -rjson -e '
  result = JSON.parse(File.read(ARGV.fetch(0)))
  abort("constraint mutation did not report changed") unless result.fetch("changed")
  abort("unexpected effective constant") unless (result.fetch("effective").fetch("constant").to_f - 104).abs < 0.5
' "$CONSTRAINT_MUTATION_PATH"
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.design.card > "$INSPECT_PATH"
ruby -rjson -e '
  height = JSON.parse(File.read(ARGV.fetch(0))).fetch("node").fetch("frame").fetch("height").to_f
  abort("constraint mutation did not resize design card") unless height > 100
' "$INSPECT_PATH"
.build/debug/loupe ui deactivate-constraint --host "$HOST" --id "$DESIGN_CARD_HEIGHT_CONSTRAINT_ID" --output "$CONSTRAINT_DEACTIVATE_PATH"
ruby -rjson -e '
  result = JSON.parse(File.read(ARGV.fetch(0)))
  abort("constraint deactivate did not report changed") unless result.fetch("changed")
  abort("constraint is still active") unless result.fetch("after").fetch("isActive") == false
' "$CONSTRAINT_DEACTIVATE_PATH"

echo "case: mixed fixture tabs for SwiftUI, WebKit, keyboard, and nested scroll"
launch_app fixtures.swiftui
.build/debug/loupe act wait visible --host "$HOST" --test-id example.fixtures --timeout 5 >/tmp/loupe-native-wait-fixtures.json
fetch_snapshot
assert_query example.fixtures /tmp/loupe-native-fixtures-query.json
assert_query example.fixtures.swiftui.host /tmp/loupe-native-swiftui-host-query.json
assert_query example.fixtures.swiftui.probe /tmp/loupe-native-swiftui-probe-query.json
assert_query example.fixtures.tab.web /tmp/loupe-native-web-tab-query.json
assert_query example.fixtures.tab.keyboard /tmp/loupe-native-keyboard-tab-query.json
assert_query example.fixtures.tab.nested /tmp/loupe-native-nested-tab-query.json
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.fixtures.swiftui.probe > "$INSPECT_PATH"
.build/debug/loupe ui accessibility "$SNAPSHOT_PATH" > "$ACCESSIBILITY_PATH"
ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(2)))
  probe = JSON.parse(File.read(ARGV.fetch(0))).fetch("node")
  host = snapshot.fetch("nodes").values.find { |node| node["testID"] == "example.fixtures.swiftui.host" }
  abort "missing SwiftUI host" unless host
  by_test_id = snapshot.fetch("nodes").values.each_with_object({}) { |node, map| map[node["testID"]] = node if node["testID"] }
  by_test_id.fetch("example.fixtures.swiftui.controls")
  by_test_id.fetch("example.fixtures.swiftui.rows")
  by_test_id.fetch("example.fixtures.swiftui.row.1")
  abort "expected SwiftUI host metadata" unless host.dig("swiftui", "origin") == "host"
  abort "expected SwiftUI probe metadata" unless probe.dig("swiftui", "origin") == "probe"
  abort "expected SwiftUI root type summary" unless host.dig("swiftui", "rootTypeName") == "SwiftUIFixtureView"
  properties = host.dig("swiftui", "properties") || []
  abort "expected SwiftUI private property summary" unless properties.any? { |property|
    property["name"] == "mode" && property.dig("value", "value") == "Focus"
  }
  abort "expected SwiftUI probe UIViewRepresentable class evidence" unless probe.dig("uikit", "className") == "UIView"
  frame = probe.fetch("frame")
  abort "expected SwiftUI probe bounds width" unless frame.fetch("width").to_f > 100
  abort "expected SwiftUI probe bounds height" unless frame.fetch("height").to_f > 80
  accessibility = JSON.parse(File.read(ARGV.fetch(1)))
  nodes = accessibility.fetch("nodes").values
  probe_ax = nodes.find { |node| node["testID"] == "example.fixtures.swiftui.probe" }
  abort "missing SwiftUI probe accessibility node" unless probe_ax && probe_ax["label"] == "iOS SwiftUI probe"
  abort "expected SwiftUI probe source ref" unless probe_ax["sourceRef"] == probe.fetch("ref")
' "$INSPECT_PATH" "$ACCESSIBILITY_PATH" "$SNAPSHOT_PATH"

launch_app fixtures.web
.build/debug/loupe act wait visible --host "$HOST" --test-id example.fixtures.web.webView --timeout 5 >/tmp/loupe-native-wait-web.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.fixtures.web.webView > "$INSPECT_PATH"
grep -q '"className" : "WKWebView"' "$INSPECT_PATH"
grep -q '"role" : "webView"' "$INSPECT_PATH"
grep -q '"webView"' "$INSPECT_PATH"
grep -q '"url" : "https:\\/\\/loupe.local\\/fixture"' "$INSPECT_PATH"

launch_app fixtures.keyboard
.build/debug/loupe act wait visible --host "$HOST" --test-id example.fixtures.keyboard.firstName --timeout 5 >/tmp/loupe-native-wait-keyboard.json
.build/debug/loupe act input --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.keyboard.firstName --text "1"
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.fixtures.keyboard.firstName > "$INSPECT_PATH"
grep -q '"className" : "UITextField"' "$INSPECT_PATH"
grep -q '"text" : "1"' "$INSPECT_PATH"
grep -q '"isFirstResponder" : true' "$INSPECT_PATH"

launch_app fixtures.nested
.build/debug/loupe act wait visible --host "$HOST" --test-id example.fixtures.nested.outerScroll --timeout 5 >/tmp/loupe-native-wait-nested.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.fixtures.nested.horizontalScroll > "$INSPECT_PATH"
grep -q '"className" : "UIScrollView"' "$INSPECT_PATH"
grep -q '"role" : "scrollView"' "$INSPECT_PATH"
assert_query example.fixtures.nested.tile.0 /tmp/loupe-native-nested-tile-query.json

echo "case: routed alert presentation"
launch_app components.alert
.build/debug/loupe act wait visible --host "$HOST" --test-id example.components.alert --timeout 5 >/tmp/loupe-native-wait-alert.json
fetch_snapshot
assert_query example.components.alert /tmp/loupe-native-alert-query.json

echo "native HID scenario smoke passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "observation: $OBSERVATION_PATH"
echo "accessibility: $ACCESSIBILITY_PATH"
echo "inspect: $INSPECT_PATH"
echo "audit: $AUDIT_PATH"
echo "subtree: $SUBTREE_PATH"
echo "frame mutation: $FRAME_MUTATION_PATH"
echo "layout mutation: $LAYOUT_MUTATION_PATH"
echo "stack mutation: $STACK_MUTATION_PATH"
echo "apply design suggestions: $APPLY_DESIGN_TRACE_DIR"
echo "self-sizing skip: $SELF_SIZING_SKIP_PATH"
echo "self-sizing mutation: $SELF_SIZING_MUTATION_PATH"
echo "self-sizing already: $SELF_SIZING_ALREADY_PATH"
echo "constraints: $CONSTRAINTS_PATH"
echo "constraint mutation: $CONSTRAINT_MUTATION_PATH"
echo "constraint deactivate: $CONSTRAINT_DEACTIVATE_PATH"
echo "trace: $TRACE_DIR"
