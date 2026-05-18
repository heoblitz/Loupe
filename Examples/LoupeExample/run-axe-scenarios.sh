#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-8765}"

cd "$ROOT_DIR"

if ! command -v axe >/dev/null 2>&1; then
  echo "error: AXe is required on PATH" >&2
  echo "hint: brew install cameroncooke/axe/axe" >&2
  exit 2
fi

booted_udid() {
  xcrun simctl list devices booted --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" }
    puts booted && booted["udid"]
  '
}

DEVICE="$(booted_udid)"
if [[ -z "$DEVICE" ]]; then
  FIRST_DEVICE="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  xcrun simctl boot "$FIRST_DEVICE"
  DEVICE="$(booted_udid)"
fi

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

xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true

.build/debug/loupe launch \
  --device "$DEVICE" \
  --bundle-id dev.loupe.example \
  --inject \
  --env LOUPE_PORT="$PORT" >/dev/null

sleep 2

HOST="http://127.0.0.1:$PORT"
SNAPSHOT_PATH="/tmp/loupe-axe-snapshot.json"
OBSERVATION_PATH="/tmp/loupe-axe-observation.json"
ACCESSIBILITY_PATH="/tmp/loupe-axe-accessibility.json"
INSPECT_PATH="/tmp/loupe-axe-inspect.json"
AUDIT_PATH="/tmp/loupe-axe-audit.json"
SUBTREE_PATH="/tmp/loupe-axe-subtree.json"
TRACE_DIR="/tmp/loupe-axe-trace"

fetch_snapshot() {
  curl -sS "$HOST/snapshot" > "$SNAPSHOT_PATH"
}

assert_query() {
  local test_id="$1"
  local output_path="$2"
  .build/debug/loupe query "$SNAPSHOT_PATH" --test-id "$test_id" > "$output_path"
  grep -q '"ref"' "$output_path"
}

fetch_snapshot
read -r WIDTH HEIGHT < <(ruby -rjson -e '
  snapshot = JSON.parse(File.read(ARGV.fetch(0)))
  size = snapshot.fetch("screen").fetch("size")
  puts [size.fetch("width"), size.fetch("height")].join(" ")
' "$SNAPSHOT_PATH")
MID_Y="$(ruby -e 'puts (ARGV.fetch(0).to_f * 0.45).round' "$HEIGHT")"
END_X="$(ruby -e 'puts (ARGV.fetch(0).to_f - 24).round' "$WIDTH")"

echo "case: navigation push by tap, pop by interactive edge drag"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.customer.1 --trace-dir "$TRACE_DIR"
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.detail --timeout 5 >/tmp/loupe-axe-wait-detail.json
test -f "$TRACE_DIR/before-snapshot.json"
test -f "$TRACE_DIR/after-snapshot.json"
test -f "$TRACE_DIR/before-accessibility.json"
test -f "$TRACE_DIR/after-accessibility.json"
test -f "$TRACE_DIR/before-logs.json"
test -f "$TRACE_DIR/after-logs.json"
test -f "$TRACE_DIR/action-before.json"
test -f "$TRACE_DIR/action-target.json"
test -f "$TRACE_DIR/action-after.json"
grep -q '"phase" : "target"' "$TRACE_DIR/action-target.json"
grep -q '"resolvedTarget"' "$TRACE_DIR/action-target.json"
test -f "$TRACE_DIR/before.png"
test -f "$TRACE_DIR/after.png"
fetch_snapshot
assert_query example.detail /tmp/loupe-axe-detail-query.json
.build/debug/loupe drag --udid "$DEVICE" --from "4,$MID_Y" --to "$END_X,$MID_Y" --duration 0.8
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-axe-wait-list.json
fetch_snapshot
assert_query example.customerList /tmp/loupe-axe-list-query.json

echo "case: navigation push and pop by tappable bar button"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.openComponents
sleep 1
fetch_snapshot
assert_query example.components /tmp/loupe-axe-components-query.json
.build/debug/loupe subtree "$SNAPSHOT_PATH" --test-id example.components --depth 4 > "$SUBTREE_PATH"
grep -q '"root"' "$SUBTREE_PATH"
grep -q '"example.components.switch"' "$SUBTREE_PATH"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.components.back
sleep 1
fetch_snapshot
assert_query example.customerList /tmp/loupe-axe-list-after-back-query.json

echo "case: UIKit component compact and inspect coverage"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.openComponents
sleep 1
curl -sS "$HOST/observation" > "$OBSERVATION_PATH"
curl -sS "$HOST/accessibility" > "$ACCESSIBILITY_PATH"
grep -q '"sourceRef"' "$ACCESSIBILITY_PATH"
grep -q '"example.components.switch"' "$ACCESSIBILITY_PATH"
grep -q '"className" : "UISwitch"' "$OBSERVATION_PATH"
grep -q '"className" : "UISlider"' "$OBSERVATION_PATH"
grep -q '"className" : "UISegmentedControl"' "$OBSERVATION_PATH"

fetch_snapshot
.build/debug/loupe accessibility "$SNAPSHOT_PATH" > "$ACCESSIBILITY_PATH"
grep -q '"rootRefs"' "$ACCESSIBILITY_PATH"
.build/debug/loupe query "$SNAPSHOT_PATH" --tree accessibility --test-id example.components.switch >/tmp/loupe-axe-accessibility-query.json
grep -q '"sourceRef"' /tmp/loupe-axe-accessibility-query.json
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
assert_query example.components.collection.0 /tmp/loupe-axe-collection-cell-query.json

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
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.components.back
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-axe-wait-list-before-fixtures.json
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.openFixtures
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures --timeout 5 >/tmp/loupe-axe-wait-fixtures.json
fetch_snapshot
assert_query example.fixtures /tmp/loupe-axe-fixtures-query.json
assert_query example.fixtures.swiftui.host /tmp/loupe-axe-swiftui-host-query.json
assert_query example.fixtures.tab.web /tmp/loupe-axe-web-tab-query.json
assert_query example.fixtures.tab.keyboard /tmp/loupe-axe-keyboard-tab-query.json
assert_query example.fixtures.tab.nested /tmp/loupe-axe-nested-tab-query.json

.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.tab.web
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.web.webView --timeout 5 >/tmp/loupe-axe-wait-web.json
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.web.webView > "$INSPECT_PATH"
grep -q '"className" : "WKWebView"' "$INSPECT_PATH"
grep -q '"role" : "webView"' "$INSPECT_PATH"
grep -q '"webView"' "$INSPECT_PATH"
grep -q '"url" : "https:\\/\\/loupe.local\\/fixture"' "$INSPECT_PATH"

.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.tab.keyboard
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.keyboard.firstName --timeout 5 >/tmp/loupe-axe-wait-keyboard.json
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.keyboard.firstName
.build/debug/loupe type "Ada" --udid "$DEVICE"
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.keyboard.firstName > "$INSPECT_PATH"
grep -q '"className" : "UITextField"' "$INSPECT_PATH"
grep -q '"text" : "Ada"' "$INSPECT_PATH"
grep -q '"isFirstResponder" : true' "$INSPECT_PATH"

.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.tab.nested
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.fixtures.nested.outerScroll --timeout 5 >/tmp/loupe-axe-wait-nested.json
fetch_snapshot
.build/debug/loupe inspect "$SNAPSHOT_PATH" --test-id example.fixtures.nested.horizontalScroll > "$INSPECT_PATH"
grep -q '"className" : "UIScrollView"' "$INSPECT_PATH"
grep -q '"role" : "scrollView"' "$INSPECT_PATH"
assert_query example.fixtures.nested.tile.0 /tmp/loupe-axe-nested-tile-query.json

echo "case: alert presentation by tap"
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.fixtures.back
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.customerList --timeout 5 >/tmp/loupe-axe-wait-list-before-alert.json
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.openComponents
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.components --timeout 5 >/tmp/loupe-axe-wait-components-before-alert.json
.build/debug/loupe tap --host "$HOST" --udid "$DEVICE" --test-id example.components.alertButton
.build/debug/loupe wait-for-visible --host "$HOST" --test-id example.components.alert --timeout 5 >/tmp/loupe-axe-wait-alert.json
fetch_snapshot
assert_query example.components.alert /tmp/loupe-axe-alert-query.json

echo "AXe scenario smoke passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "observation: $OBSERVATION_PATH"
echo "accessibility: $ACCESSIBILITY_PATH"
echo "inspect: $INSPECT_PATH"
echo "audit: $AUDIT_PATH"
echo "subtree: $SUBTREE_PATH"
echo "trace: $TRACE_DIR"
