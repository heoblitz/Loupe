#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-8765}"

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
  local list_path="/tmp/loupe-native-booted-devices.json"
  run_with_timeout "$(simctl_list_timeout)" xcrun simctl list devices booted --json >"$list_path"
  ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" }
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

HOST="http://127.0.0.1:$PORT"
SNAPSHOT_PATH="/tmp/loupe-native-snapshot.json"
OBSERVATION_PATH="/tmp/loupe-native-observation.json"
ACCESSIBILITY_PATH="/tmp/loupe-native-accessibility.json"
INSPECT_PATH="/tmp/loupe-native-inspect.json"
AUDIT_PATH="/tmp/loupe-native-audit.json"
SUBTREE_PATH="/tmp/loupe-native-subtree.json"
TRACE_DIR="/tmp/loupe-native-trace"

launch_app() {
  local route="${1:-}"
  terminate_app
  local arguments=(
    --device "$DEVICE"
    --bundle-id dev.loupe.example
    --inject
    --env "LOUPE_PORT=$PORT"
  )
  if [[ -n "$route" ]]; then
    arguments+=(--env "LOUPE_EXAMPLE_ROUTE=$route")
  fi
  .build/debug/loupe launch "${arguments[@]}" >/dev/null
  sleep 2
}

fetch_snapshot() {
  .build/debug/loupe fetch "$HOST/snapshot" --timeout 10 --output "$SNAPSHOT_PATH"
}

assert_query() {
  local test_id="$1"
  local output_path="$2"
  .build/debug/loupe query "$SNAPSHOT_PATH" --test-id "$test_id" > "$output_path"
  grep -q '"ref"' "$output_path"
}

query_ref() {
  local test_id="$1"
  .build/debug/loupe query "$SNAPSHOT_PATH" --test-id "$test_id" --max-results 1 |
    ruby -rjson -e 'puts JSON.parse(STDIN.read).fetch(0).fetch("ref")'
}

inspect_value() {
  local test_id="$1"
  local path="$2"
  .build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id "$test_id" |
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
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.bottomSheet.grabber --timeout 5 >/tmp/loupe-native-wait-bottomsheet.json
fetch_snapshot
assert_query example.bottomSheet.scrollView /tmp/loupe-native-bottomsheet-scroll-query.json
COLLAPSED_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
COLLAPSED_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
GRABBER_REF="$(query_ref example.bottomSheet.grabber)"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --ref "$GRABBER_REF" --expect-visible example.bottomSheet.expandedMarker
fetch_snapshot
EXPANDED_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
EXPANDED_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
CONTENT_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.uiKit.scrollView.contentSize.height)"
ruby -e '
  moved_up = ARGV.fetch(0).to_f < ARGV.fetch(1).to_f - 120
  grew = ARGV.fetch(2).to_f > ARGV.fetch(3).to_f + 120
  long_list = ARGV.fetch(4).to_f > ARGV.fetch(2).to_f + 400
  exit(moved_up && grew && long_list ? 0 : 1)
' "$EXPANDED_Y" "$COLLAPSED_Y" "$EXPANDED_HEIGHT" "$COLLAPSED_HEIGHT" "$CONTENT_HEIGHT"

echo "case: navigation pop by interactive edge drag from routed detail screen"
launch_app detail
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.detail --timeout 5 >/tmp/loupe-native-wait-detail.json
fetch_snapshot
assert_query example.detail /tmp/loupe-native-detail-query.json
.build/debug/loupe drag --udid "$DEVICE" --from "4,$MID_Y" --to "$END_X,$MID_Y" --duration 0.8
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-native-wait-list.json
fetch_snapshot
assert_query example.customerList /tmp/loupe-native-list-query.json

echo "case: navigation push by testID tap, then pop by ref tap"
launch_app
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.openComponents --trace-dir "$TRACE_DIR"
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.components --timeout 5 >/tmp/loupe-native-wait-components.json
fetch_snapshot
assert_query example.components /tmp/loupe-native-components-query.json
test -f "$TRACE_DIR/action-target.json"
grep -q '"phase" : "target"' "$TRACE_DIR/action-target.json"
grep -q '"resolvedTarget"' "$TRACE_DIR/action-target.json"
.build/debug/loupe subtree "$SNAPSHOT_PATH" --test-id example.components --depth 4 > "$SUBTREE_PATH"
grep -q '"root"' "$SUBTREE_PATH"
grep -q '"example.components.switch"' "$SUBTREE_PATH"
BACK_REF="$(query_ref example.components.back)"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --ref "$BACK_REF"
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-native-wait-list-after-ref-tap.json

echo "case: routed UIKit component screen"
launch_app components
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.components --timeout 5 >/tmp/loupe-native-wait-components-routed.json
fetch_snapshot

echo "case: UIKit component compact and inspect coverage"
.build/debug/loupe fetch "$HOST/observation" --timeout 5 --output "$OBSERVATION_PATH"
.build/debug/loupe fetch "$HOST/accessibility" --timeout 5 --output "$ACCESSIBILITY_PATH"
grep -q '"sourceRef"' "$ACCESSIBILITY_PATH"
grep -q '"example.components.switch"' "$ACCESSIBILITY_PATH"
grep -q '"className" : "UISwitch"' "$OBSERVATION_PATH"
grep -q '"className" : "UISlider"' "$OBSERVATION_PATH"
grep -q '"className" : "UISegmentedControl"' "$OBSERVATION_PATH"

fetch_snapshot
.build/debug/loupe accessibility "$SNAPSHOT_PATH" > "$ACCESSIBILITY_PATH"
grep -q '"rootRefs"' "$ACCESSIBILITY_PATH"
.build/debug/loupe query "$SNAPSHOT_PATH" --tree accessibility --test-id example.components.switch >/tmp/loupe-native-accessibility-query.json
grep -q '"sourceRef"' /tmp/loupe-native-accessibility-query.json
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.switch > "$INSPECT_PATH"
grep -q '"className" : "UISwitch"' "$INSPECT_PATH"
grep -q '"isOn" : true' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.segmented > "$INSPECT_PATH"
grep -q '"selectedSegmentIndex" : 1' "$INSPECT_PATH"
grep -q '"Large"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.image > "$INSPECT_PATH"
grep -q '"className" : "UIImageView"' "$INSPECT_PATH"
grep -q '"imageSize"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.scrollView > "$INSPECT_PATH"
grep -q '"className" : "UIScrollView"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.stepper > "$INSPECT_PATH"
grep -q '"className" : "UIStepper"' "$INSPECT_PATH"
grep -q '"stepper"' "$INSPECT_PATH"
grep -q '"stepValue" : 2' "$INSPECT_PATH"
grep -q '"value" : 4' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.datePicker > "$INSPECT_PATH"
grep -q '"className" : "UIDatePicker"' "$INSPECT_PATH"
grep -q '"datePicker"' "$INSPECT_PATH"
grep -q '"mode" : "date"' "$INSPECT_PATH"
grep -q '"date"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.tabBar > "$INSPECT_PATH"
grep -q '"className" : "UITabBar"' "$INSPECT_PATH"
grep -q '"tabBar"' "$INSPECT_PATH"
grep -q '"items"' "$INSPECT_PATH"
grep -q '"selectedItem" : "Home"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.collectionView > "$INSPECT_PATH"
grep -q '"className" : "UICollectionView"' "$INSPECT_PATH"
assert_query example.components.collection.0 /tmp/loupe-native-collection-cell-query.json

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.pickerView > "$INSPECT_PATH"
grep -q '"className" : "UIPickerView"' "$INSPECT_PATH"
grep -q '"pickerView"' "$INSPECT_PATH"
grep -q '"numberOfComponents" : 1' "$INSPECT_PATH"
grep -q '"selectedRows"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.pageControl > "$INSPECT_PATH"
grep -q '"className" : "UIPageControl"' "$INSPECT_PATH"
grep -q '"currentPage" : 2' "$INSPECT_PATH"
grep -q '"numberOfPages" : 5' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.progress > "$INSPECT_PATH"
grep -q '"className" : "UIProgressView"' "$INSPECT_PATH"
grep -q '"progressView"' "$INSPECT_PATH"
grep -q '"value"' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.components.activity > "$INSPECT_PATH"
grep -q '"className" : "UIActivityIndicatorView"' "$INSPECT_PATH"
grep -q '"isAnimating" : true' "$INSPECT_PATH"

.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.design.card > "$INSPECT_PATH"
grep -q '"cornerRadius" : 20' "$INSPECT_PATH"
grep -q '"backgroundColor"' "$INSPECT_PATH"
grep -q '"borderWidth" : 2' "$INSPECT_PATH"

echo "case: layout audit emits machine-readable design checks"
.build/debug/loupe audit "$SNAPSHOT_PATH" > "$AUDIT_PATH"
grep -q '"issueCount"' "$AUDIT_PATH"
grep -q '"issues"' "$AUDIT_PATH"

echo "case: mixed fixture tabs for SwiftUI, WebKit, keyboard, and nested scroll"
launch_app fixtures
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures --timeout 5 >/tmp/loupe-native-wait-fixtures.json
fetch_snapshot
assert_query example.fixtures /tmp/loupe-native-fixtures-query.json
assert_query example.fixtures.swiftui.host /tmp/loupe-native-swiftui-host-query.json
assert_query example.fixtures.tab.web /tmp/loupe-native-web-tab-query.json
assert_query example.fixtures.tab.keyboard /tmp/loupe-native-keyboard-tab-query.json
assert_query example.fixtures.tab.nested /tmp/loupe-native-nested-tab-query.json

launch_app fixtures.web
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.web.webView --timeout 5 >/tmp/loupe-native-wait-web.json
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.web.webView > "$INSPECT_PATH"
grep -q '"className" : "WKWebView"' "$INSPECT_PATH"
grep -q '"role" : "webView"' "$INSPECT_PATH"
grep -q '"webView"' "$INSPECT_PATH"
grep -q '"url" : "https:\\/\\/loupe.local\\/fixture"' "$INSPECT_PATH"

launch_app fixtures.keyboard
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.keyboard.firstName --timeout 5 >/tmp/loupe-native-wait-keyboard.json
.build/debug/loupe type "1" --udid "$DEVICE"
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.keyboard.firstName > "$INSPECT_PATH"
grep -q '"className" : "UITextField"' "$INSPECT_PATH"
grep -q '"text" : "1"' "$INSPECT_PATH"
grep -q '"isFirstResponder" : true' "$INSPECT_PATH"

launch_app fixtures.nested
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.nested.outerScroll --timeout 5 >/tmp/loupe-native-wait-nested.json
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.nested.horizontalScroll > "$INSPECT_PATH"
grep -q '"className" : "UIScrollView"' "$INSPECT_PATH"
grep -q '"role" : "scrollView"' "$INSPECT_PATH"
assert_query example.fixtures.nested.tile.0 /tmp/loupe-native-nested-tile-query.json

echo "case: routed alert presentation"
launch_app components.alert
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.components.alert --timeout 5 >/tmp/loupe-native-wait-alert.json
fetch_snapshot
assert_query example.components.alert /tmp/loupe-native-alert-query.json

echo "native HID scenario smoke passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "observation: $OBSERVATION_PATH"
echo "accessibility: $ACCESSIBILITY_PATH"
echo "inspect: $INSPECT_PATH"
echo "audit: $AUDIT_PATH"
echo "subtree: $SUBTREE_PATH"
echo "trace: $TRACE_DIR"
