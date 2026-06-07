#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE_NAME="${LOUPE_DEVICE_NAME:-iPhone 17 Pro}"
PORT="${LOUPE_PORT:-}"

cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh

swift build
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,name=$DEVICE_NAME"

xcrun simctl boot "$DEVICE_NAME" >/dev/null 2>&1 || true
xcrun simctl install booted "$APP_PATH"
xcrun simctl terminate booted dev.loupe.example >/dev/null 2>&1 || true

LAUNCH_ARGUMENTS=(
  --device booted
  --bundle-id dev.loupe.example
  --inject
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
PORT="$(ruby -ruri -e 'puts URI(ARGV.fetch(0)).port' "$HOST")"

sleep 2

LOUPE_PORT="$PORT" xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination "platform=iOS Simulator,name=$DEVICE_NAME" \
  -configuration Debug \
  -only-testing:LoupeExampleUITests/LoupeExampleUITests/testLoupeDrivenCoordinateActionsAgainstInjectedApp \
  test
