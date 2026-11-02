#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh

DEVICE="${LOUPE_DEVICE:-$(xcrun simctl list devices available --json | python3 -c '
import json, sys
inventory = json.load(sys.stdin)["devices"]
devices = [d for runtime, items in inventory.items() if "iOS-27" in runtime for d in items if d["name"].startswith("iPhone")]
if not devices: raise SystemExit("no available iOS 27 iPhone simulator")
print(next((d for d in devices if d["state"] == "Booted"), devices[0])["udid"])
')}"
if [[ "${LOUPE_OPEN_DEVICE_HUB:-0}" == "1" ]]; then
  frontend="$(xcode-select -p)"
  frontend="${frontend%/Developer}/Applications/DeviceHub.app"
  [[ -d "$frontend" ]] || { echo "error: Device Hub not found at $frontend" >&2; exit 1; }
  if xcrun simctl list devices booted | grep -Fq "$DEVICE"; then
    xcrun simctl shutdown "$DEVICE"
  fi
  /usr/bin/open -a "$frontend"
fi
xcrun simctl bootstatus "$DEVICE" -b
if [[ "${LOUPE_OPEN_DEVICE_HUB:-0}" == "1" ]]; then
  /usr/bin/open -a "$frontend" "devices://device/open?id=$DEVICE"
fi
swift build --product loupe
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,id=$DEVICE"
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
launch="$(.build/debug/loupe app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=fixtures.swiftui --timeout 30)"
host="$(awk '/^loupe host: / { print $3 }' <<<"$launch" | tail -1)"
[[ -n "$host" ]] || { echo "error: launch did not return a host" >&2; exit 1; }
.build/debug/loupe act wait visible --host "$host" --test-id example.fixtures.swiftui.probe --timeout 15
.build/debug/loupe ui snapshot --host "$host" --timeout 15 --output /tmp/loupe-xcode27-observation.json
python3 - /tmp/loupe-xcode27-observation.json <<'PY'
import json, sys
snapshot = json.load(open(sys.argv[1]))
ids = {node.get('testID') for node in snapshot['nodes'].values()}
assert 'example.fixtures.swiftui.host' in ids
assert 'example.fixtures.swiftui.probe' in ids
PY
echo "Xcode 27 SwiftUI observation passed"
xcrun simctl terminate "$DEVICE" dev.loupe.example
launch="$(.build/debug/loupe app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=fixtures.web --timeout 30)"
host="$(awk '/^loupe host: / { print $3 }' <<<"$launch" | tail -1)"
[[ -n "$host" ]] || { echo "error: web launch did not return a host" >&2; exit 1; }
Examples/LoupeExample/verify-web-accessibility.sh "$host" "$DEVICE"
xcrun simctl terminate "$DEVICE" dev.loupe.example
launch="$(.build/debug/loupe app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=touch --timeout 30)"
host="$(awk '/^loupe host: / { print $3 }' <<<"$launch" | tail -1)"
[[ -n "$host" ]] || { echo "error: touch launch did not return a host" >&2; exit 1; }
python3 Examples/LoupeExample/verify-devicehub-drag.py "$host" "$DEVICE"
