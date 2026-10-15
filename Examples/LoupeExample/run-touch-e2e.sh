#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh
configure_loupe_ios_verification
export LOUPE_HID_DIAGNOSTICS="${LOUPE_HID_DIAGNOSTICS:-1}"
CLI="${LOUPE_TOUCH_CLI:-.build/debug/loupe}"
if [[ -z "${LOUPE_TOUCH_CLI:-}" ]]; then
  swift build --product loupe >/tmp/loupe-touch-cli-build.log 2>&1
fi
if [[ -n "${LOUPE_TOUCH_HOST:-}" ]]; then
  python3 Examples/LoupeExample/verify-touch-scenarios.py "$LOUPE_TOUCH_HOST" "${LOUPE_DEVICE:-}" "${LOUPE_TOUCH_MODE:-all}"
  exit 0
fi
export LOUPE_EXAMPLE_BUILD_ROOT="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-touch-e2e-build}"
# Local and CI runs select and boot through the same public simctl commands.
# Explicit runtime/device requests must match; never silently pick another one.
DEVICE="$(loupe_ios_verification_device)"
echo "touch E2E: device=$DEVICE architecture=$(uname -m) CLI=$CLI"
xcodebuild -version
prepare_loupe_ios_preferences
# Keep compilation from competing with the guest's first-boot services.
destination="${LOUPE_EXAMPLE_DESTINATION:-platform=iOS Simulator,id=$DEVICE}"
if [[ -n "${LOUPE_TOUCH_ARCHITECTURE:-}" && "$destination" != generic/* ]]; then
  destination="$destination,arch=$LOUPE_TOUCH_ARCHITECTURE"
fi
build_loupe_example_simulator_artifacts "$ROOT_DIR" "$destination"
if [[ -n "${LOUPE_TOUCH_ARCHITECTURE:-}" ]]; then
  test "$(xcrun lipo -archs "$APP_PATH/LoupeExample")" = "$LOUPE_TOUCH_ARCHITECTURE"
fi
boot_loupe_ios_verification_device
if [[ "${LOUPE_TOUCH_OPEN_DEVICE_HUB:-0}" == "1" ]]; then
  frontend="${DEVELOPER_DIR%/Developer}/Applications/DeviceHub.app"
  if [[ ! -d "$frontend" ]]; then
    echo "error: Device Hub not found at $frontend" >&2
    exit 1
  fi
  /usr/bin/open -a "$frontend" "devices://device/open?id=$DEVICE"
fi
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
for route in touch touch.swiftui; do
  launch_output="$("$CLI" app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env "LOUPE_EXAMPLE_ROUTE=$route" --timeout 30)"
  HOST="$(awk '/^loupe host: / { print $3 }' <<<"$launch_output" | tail -1)"
  test -n "$HOST"
  # SwiftUI must also work in a fresh process, before UIKit or act targets has
  # initialized native accessibility. Use identical assertions on both paths.
  mode=all
  if [[ "$route" == touch.swiftui ]]; then mode=--swiftui-only; fi
  python3 Examples/LoupeExample/verify-touch-scenarios.py "$HOST" "$DEVICE" "$mode"
done
