#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-}"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh

booted_udid() {
  xcrun simctl list devices booted --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("iPhone") }
    puts booted && booted["udid"]
  '
}

DEVICE="${LOUPE_DEVICE:-$(booted_udid)}"
if [[ -z "$DEVICE" ]]; then
  echo "error: no booted simulator found; run run-native-scenarios.sh once to build, install, and boot" >&2
  exit 1
fi

HOST=""
SNAPSHOT_PATH="/tmp/loupe-gesture-snapshot.json"
TRACE_DIR="/tmp/loupe-gesture-bottomsheet-scroll-trace"
rm -rf "$TRACE_DIR"

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

terminate_app() {
  xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true
}

launch_app() {
  terminate_app
  local arguments=(
    --device "$DEVICE"
    --bundle-id dev.loupe.example
    --inject
    --env "LOUPE_EXAMPLE_ROUTE=bottomSheet"
  )
  if [[ -n "$PORT" ]]; then
    arguments+=(--env "LOUPE_PORT=$PORT")
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

query_ref() {
  local test_id="$1"
  .build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id "$test_id" --max-results 1 |
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

swift build
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,id=$DEVICE"
terminate_app
run_with_timeout 30 xcrun simctl install "$DEVICE" "$APP_PATH"
launch_app
.build/debug/loupe act wait visible --host "$HOST" --test-id example.bottomSheet.grabber --timeout 5 >/tmp/loupe-gesture-wait-bottomsheet.json
fetch_snapshot

COLLAPSED_Y="$(inspect_value example.bottomSheet.scrollView node.frame.y)"
COLLAPSED_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.frame.height)"
read -r GRABBER_X GRABBER_Y < <(.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.bottomSheet.grabber |
  ruby -rjson -e '
    frame = JSON.parse(STDIN.read).fetch("node").fetch("frame")
    puts [(frame.fetch("x") + frame.fetch("width") / 2.0).round, (frame.fetch("y") + frame.fetch("height") / 2.0).round].join(" ")
  ')
DRAG_END_Y="$(ruby -e 'puts [(ARGV.fetch(0).to_f - 280).round, 80].max' "$GRABBER_Y")"
.build/debug/loupe act drag --host "$HOST" --udid "$DEVICE" --from "$GRABBER_X,$GRABBER_Y" --to "$GRABBER_X,$DRAG_END_Y" --duration 0.5 --trace-dir /tmp/loupe-gesture-bottomsheet-grabber-drag-trace
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
CONTENT_HEIGHT="$(inspect_value example.bottomSheet.scrollView node.uiKit.scrollView.contentSize.height)"
ruby -e '
  moved_up = ARGV.fetch(0).to_f < ARGV.fetch(1).to_f - 120
  grew = ARGV.fetch(2).to_f > ARGV.fetch(3).to_f + 120
  long_list = ARGV.fetch(4).to_f > ARGV.fetch(2).to_f + 400
  exit(moved_up && grew && long_list ? 0 : 1)
' "$EXPANDED_Y" "$COLLAPSED_Y" "$EXPANDED_HEIGHT" "$COLLAPSED_HEIGHT" "$CONTENT_HEIGHT"

BEFORE_OFFSET="$(inspect_value example.bottomSheet.scrollView node.uiKit.scrollView.contentOffset.y)"
read -r SCROLL_X SCROLL_FROM_Y SCROLL_TO_Y < <(.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.bottomSheet.scrollView |
  ruby -rjson -e '
    frame = JSON.parse(STDIN.read).fetch("node").fetch("frame")
    x = (frame.fetch("x") + frame.fetch("width") / 2.0).round
    from_y = (frame.fetch("y") + frame.fetch("height") - 36).round
    to_y = [(frame.fetch("y") + 72).round, from_y - 360].max
    puts [x, from_y, to_y].join(" ")
  ')
.build/debug/loupe act swipe --host "$HOST" --udid "$DEVICE" --from "$SCROLL_X,$SCROLL_FROM_Y" --to "$SCROLL_X,$SCROLL_TO_Y" --duration 0.5 --trace-dir "$TRACE_DIR"
fetch_snapshot
AFTER_OFFSET="$(inspect_value example.bottomSheet.scrollView node.uiKit.scrollView.contentOffset.y)"
ruby -e 'exit(ARGV.fetch(1).to_f > ARGV.fetch(0).to_f + 20 ? 0 : 1)' "$BEFORE_OFFSET" "$AFTER_OFFSET"

echo "gesture scenario passed"
echo "trace: $TRACE_DIR"
