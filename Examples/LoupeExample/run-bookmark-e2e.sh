#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_BOOKMARK_PORT:-${LOUPE_PORT:-}}"

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
  local list_path="/tmp/loupe-bookmark-booted-devices.json"
  run_with_timeout "$(simctl_list_timeout)" xcrun simctl list devices booted --json >"$list_path"
  ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("iPhone") }
    puts booted && booted["udid"]
  ' <"$list_path"
}

DEVICE="${LOUPE_BOOKMARK_DEVICE:-$(booted_udid)}"
if [[ -z "$DEVICE" ]]; then
  DEVICES_PATH="/tmp/loupe-bookmark-available-devices.txt"
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
  local log_path="/tmp/loupe-bookmark-bootstatus.log"
  if run_with_timeout 90 xcrun simctl bootstatus "$DEVICE" -b >"$log_path" 2>&1; then
    return
  fi

  if run_with_timeout 5 xcrun simctl spawn "$DEVICE" launchctl print system >/dev/null 2>&1; then
    echo "warning: bootstatus timed out, but simulator launchd responds; continuing" >&2
    return
  fi

  xcrun simctl io "$DEVICE" screenshot /tmp/loupe-bookmark-boot-not-ready.png >/dev/null 2>&1 || true
  echo "error: simulator $DEVICE did not finish booting; see $log_path and /tmp/loupe-bookmark-boot-not-ready.png" >&2
  tail -40 "$log_path" >&2 || true
  exit 124
}

assert_device_ready
swift build

xcodebuild \
  -scheme LoupeInjector \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-bookmark-injector-build.log

xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-bookmark-example-build.log

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

LAUNCH_ARGUMENTS=(
  --device "$DEVICE"
  --bundle-id dev.loupe.example
  --inject
  --env LOUPE_EXAMPLE_ROUTE=bookmarks
)
if [[ -n "$PORT" ]]; then
  LAUNCH_ARGUMENTS+=(--env "LOUPE_PORT=$PORT")
fi
LAUNCH_OUTPUT="$(.build/debug/loupe app launch "${LAUNCH_ARGUMENTS[@]}")"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$LAUNCH_OUTPUT" | tail -1)"
if [[ -z "$HOST" ]]; then
  echo "error: loupe app launch did not report a runtime host" >&2
  echo "$LAUNCH_OUTPUT" >&2
  exit 1
fi

sleep 2

SNAPSHOT_PATH="/tmp/loupe-bookmark-snapshot.json"
OBSERVATION_PATH="/tmp/loupe-bookmark-observation.json"
INSPECT_PATH="/tmp/loupe-bookmark-inspect.json"
AUDIT_PATH="/tmp/loupe-bookmark-audit.json"
TRACE_DIR="/tmp/loupe-bookmark-trace"
rm -rf "$TRACE_DIR"

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

echo "case: bookmark list observation"
.build/debug/loupe app info --host "$HOST" --udid "$DEVICE" --timeout 5 >/tmp/loupe-bookmark-runtime.json
.build/debug/loupe app list --json >/tmp/loupe-bookmark-runtimes.json
grep -q "dev.loupe.example" /tmp/loupe-bookmark-runtimes.json
.build/debug/loupe ui set --host "$HOST" --udid "$DEVICE" --list >/tmp/loupe-bookmark-mutations.json
grep -q '"property" : "backgroundcolor"' /tmp/loupe-bookmark-mutations.json
fetch_snapshot
assert_query bookmark.tabs /tmp/loupe-bookmark-tabs-query.json
assert_query bookmark.tabbar /tmp/loupe-bookmark-tabbar-query.json
assert_query bookmark.list /tmp/loupe-bookmark-list-query.json
assert_query bookmark.item.swift /tmp/loupe-bookmark-first-query.json
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --test-id bookmark.tabs --depth 2 >/tmp/loupe-bookmark-view-tree.txt
grep -q "bookmark.tabs" /tmp/loupe-bookmark-view-tree.txt
.build/debug/loupe ui tree "$SNAPSHOT_PATH" --accessibility --test-id bookmark.tabbar --depth 1 >/tmp/loupe-bookmark-accessibility-tree.txt
grep -q "bookmark.tabbar" /tmp/loupe-bookmark-accessibility-tree.txt
.build/debug/loupe ui compact "$SNAPSHOT_PATH" >/tmp/loupe-bookmark-compact.json
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.tabbar > "$INSPECT_PATH"
grep -q '"className" : "UITabBar"' "$INSPECT_PATH"
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.list > "$INSPECT_PATH"
grep -q '"className" : "UITableView"' "$INSPECT_PATH"

echo "case: bookmark text tap is rejected"
if .build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --text "Swift Documentation" >/tmp/loupe-bookmark-text-tap.log 2>&1; then
  echo "error: tap --text unexpectedly succeeded" >&2
  exit 1
fi
grep -q 'tap expects --test-id, --ref, or coordinates' /tmp/loupe-bookmark-text-tap.log
if .build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.missing >/tmp/loupe-bookmark-missing-tap.out 2>/tmp/loupe-bookmark-missing-tap.err; then
  echo "error: missing target tap unexpectedly succeeded" >&2
  exit 1
fi
AUTO_TRACE_DIR="$(awk '/^trace: / { print $2 }' /tmp/loupe-bookmark-missing-tap.err | tail -1)"
test -f "$AUTO_TRACE_DIR/error.json"
test -f "$AUTO_TRACE_DIR/failure-snapshot.json"
test -f "$AUTO_TRACE_DIR/failure-logs.json"
.build/debug/loupe debug trace summary "$AUTO_TRACE_DIR" >/tmp/loupe-bookmark-failure-trace-summary.txt
grep -q "bookmark.missing" "$AUTO_TRACE_DIR/action-failure.json"
grep -q "No Loupe accessibility or view node matched selector" /tmp/loupe-bookmark-failure-trace-summary.txt

echo "case: bookmark detail by testID tap and back by ref tap"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.item.swift --trace-dir "$TRACE_DIR" --expect-visible bookmark.detail
test -f "$TRACE_DIR/target-crop.png"
test -f "$TRACE_DIR/before-logs.json"
test -f "$TRACE_DIR/after-logs.json"
.build/debug/loupe debug trace summary "$TRACE_DIR" >/tmp/loupe-bookmark-action-trace-summary.txt
grep -q "bookmark.detail" /tmp/loupe-bookmark-action-trace-summary.txt
.build/debug/loupe debug trace diff "$TRACE_DIR/before-snapshot.json" "$TRACE_DIR/after-snapshot.json" >/tmp/loupe-bookmark-action-diff.txt
grep -q "bookmark.detail" /tmp/loupe-bookmark-action-diff.txt
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.detail --timeout 5 >/tmp/loupe-bookmark-wait-detail.json
fetch_snapshot
assert_query bookmark.detail /tmp/loupe-bookmark-detail-query.json
.build/debug/loupe ui set --host "$HOST" --udid "$DEVICE" --test-id bookmark.detail.title text "Runtime Edited Bookmark" >/tmp/loupe-bookmark-set-title.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.detail.title > "$INSPECT_PATH"
grep -q '"text" : "Runtime Edited Bookmark"' "$INSPECT_PATH"
.build/debug/loupe ui reflect /tmp/loupe-bookmark-set-title.json --source Examples/LoupeExample/LoupeExample >/tmp/loupe-bookmark-reflect-title.json
grep -q 'BookmarkViewController.swift' /tmp/loupe-bookmark-reflect-title.json
grep -q 'Runtime Edited Bookmark' /tmp/loupe-bookmark-reflect-title.json
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.detail.favorite > "$INSPECT_PATH"
grep -q '"className" : "UISwitch"' "$INSPECT_PATH"
grep -q '"isOn" : true' "$INSPECT_PATH"
.build/debug/loupe ui set --host "$HOST" --udid "$DEVICE" --test-id bookmark.detail.favorite switch.isOn false >/tmp/loupe-bookmark-set-favorite-off.json
.build/debug/loupe act wait value --host "$HOST" --test-id bookmark.detail.favorite --key uiKit.switch.isOn --equals false --timeout 5 >/tmp/loupe-bookmark-wait-set-favorite-off.json
.build/debug/loupe ui set --host "$HOST" --udid "$DEVICE" --test-id bookmark.detail.favorite switch.isOn true >/tmp/loupe-bookmark-set-favorite-on.json
.build/debug/loupe act wait value --host "$HOST" --test-id bookmark.detail.favorite --key uiKit.switch.isOn --equals true --timeout 5 >/tmp/loupe-bookmark-wait-favorite-on.json
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.detail.favorite.toggle --expect-visible bookmark.detail
.build/debug/loupe act wait value --host "$HOST" --test-id bookmark.detail.favorite --key uiKit.switch.isOn --equals false --timeout 5 >/tmp/loupe-bookmark-wait-favorite-off.json
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.detail.favorite.toggle --expect-visible bookmark.detail
.build/debug/loupe act wait value --host "$HOST" --test-id bookmark.detail.favorite --key uiKit.switch.isOn --equals true --timeout 5 >/tmp/loupe-bookmark-wait-favorite-on-again.json
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.detail.category > "$INSPECT_PATH"
grep -q '"className" : "UISegmentedControl"' "$INSPECT_PATH"
grep -q '"selectedSegmentIndex" : 0' "$INSPECT_PATH"
BACK_REF="$(query_ref bookmark.detail.back)"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --snapshot "$SNAPSHOT_PATH" --ref "$BACK_REF"
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.list --timeout 5 >/tmp/loupe-bookmark-wait-list.json
.build/debug/loupe act wait gone --host "$HOST" --test-id bookmark.detail --timeout 5 >/tmp/loupe-bookmark-wait-detail-gone.json
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.add --timeout 5 >/tmp/loupe-bookmark-wait-add.json

echo "case: bookmark creation form by selector tap and type"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.add --expect-visible bookmark.editor
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.editor --timeout 5 >/tmp/loupe-bookmark-wait-editor.json
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.editor.title --timeout 5 >/tmp/loupe-bookmark-wait-editor-title.json
fetch_snapshot
sleep 1
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --snapshot "$SNAPSHOT_PATH" --ref "$(query_ref bookmark.editor.title)"
sleep 1
CREATED_TITLE="20260519"
.build/debug/loupe act type "$CREATED_TITLE" --udid "$DEVICE"
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.editor.title > "$INSPECT_PATH"
grep -q "\"text\" : \"$CREATED_TITLE\"" "$INSPECT_PATH"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.editor.save
.build/debug/loupe act wait gone --host "$HOST" --test-id bookmark.editor --timeout 5 >/tmp/loupe-bookmark-wait-editor-gone.json
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.item.created --timeout 5 >/tmp/loupe-bookmark-wait-created.json
fetch_snapshot
assert_query bookmark.item.created /tmp/loupe-bookmark-created-query.json

echo "case: bookmark favorites tab and detail"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.tab.favorites
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.favorites --timeout 5 >/tmp/loupe-bookmark-wait-favorites.json
fetch_snapshot
assert_query bookmark.favorites /tmp/loupe-bookmark-favorites-query.json
assert_query bookmark.item.swift /tmp/loupe-bookmark-favorite-first-query.json
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.item.swift
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.detail --timeout 5 >/tmp/loupe-bookmark-wait-favorite-detail.json
fetch_snapshot
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id bookmark.detail.favorite > "$INSPECT_PATH"
grep -q '"isOn" : true' "$INSPECT_PATH"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --x 32 --y 78 --width 402 --height 874 --trace-dir "$TRACE_DIR-favorite-back"
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.favorites --timeout 8 >/tmp/loupe-bookmark-wait-favorites-return.json

echo "case: bookmark search tab"
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.tabbar --timeout 5 >/tmp/loupe-bookmark-wait-tabbar-before-search.json
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.tab.search --timeout 5 >/tmp/loupe-bookmark-wait-search-tab.json
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.tab.search
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.search --timeout 5 >/tmp/loupe-bookmark-wait-search.json
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --test-id bookmark.search.field
.build/debug/loupe act type "$CREATED_TITLE" --udid "$DEVICE"
.build/debug/loupe act wait visible --host "$HOST" --test-id bookmark.item.created --timeout 5 >/tmp/loupe-bookmark-wait-search-result.json
fetch_snapshot
assert_query bookmark.search /tmp/loupe-bookmark-search-query.json
assert_query bookmark.item.created /tmp/loupe-bookmark-search-result-query.json

echo "case: bookmark layout audit and runtime stability"
.build/debug/loupe ui compact --host "$HOST" --timeout 5 --output "$OBSERVATION_PATH"
grep -q '"bookmark.item.created"' "$OBSERVATION_PATH"
.build/debug/loupe ui audit "$SNAPSHOT_PATH" > "$AUDIT_PATH"
grep -q '"issueCount"' "$AUDIT_PATH"
.build/debug/loupe app info --host "$HOST" --udid "$DEVICE" --timeout 5 >/tmp/loupe-bookmark-runtime-after.json

echo "bookmark E2E smoke passed"
echo "snapshot: $SNAPSHOT_PATH"
echo "observation: $OBSERVATION_PATH"
echo "inspect: $INSPECT_PATH"
echo "audit: $AUDIT_PATH"
echo "trace: $TRACE_DIR"
