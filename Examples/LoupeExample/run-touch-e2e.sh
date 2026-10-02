#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
CLI="${LOUPE_TOUCH_CLI:-.build/debug/loupe}"
if [[ -n "${LOUPE_TOUCH_HOST:-}" ]]; then
  if [[ -z "${LOUPE_TOUCH_CLI:-}" ]]; then swift build --product loupe >/tmp/loupe-touch-cli-build.log 2>&1; fi
  python3 Examples/LoupeExample/verify-touch-scenarios.py "$LOUPE_TOUCH_HOST" "${LOUPE_DEVICE:-}" "${LOUPE_TOUCH_MODE:-all}"
  exit 0
fi
source Examples/LoupeExample/build-simulator-artifacts.sh
export LOUPE_EXAMPLE_BUILD_ROOT="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-touch-e2e-build}"
DEVICE="${LOUPE_DEVICE:-$(xcrun simctl list devices available --json | python3 -c '
import json,sys
available = [d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"].startswith("iPhone")]
devices = [d for d in available if d["name"] == "iPhone 17 Pro"] or available
booted = next((d for d in devices if d["state"] == "Booted"), None)
print((booted or devices[0])["udid"])
')}"
echo "touch E2E simulator: $DEVICE"
if [[ "${LOUPE_TOUCH_PRECONFIGURED_INPUT:-0}" != "1" ]]; then
  xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$DEVICE" -b >/tmp/loupe-touch-boot.log 2>&1
fi
if [[ -z "${LOUPE_TOUCH_CLI:-}" ]]; then swift build --product loupe >/tmp/loupe-touch-cli-build.log 2>&1; fi
destination="platform=iOS Simulator,id=$DEVICE"
if [[ -n "${LOUPE_TOUCH_ARCHITECTURE:-}" ]]; then
  destination="$destination,arch=$LOUPE_TOUCH_ARCHITECTURE"
fi
build_loupe_example_simulator_artifacts "$ROOT_DIR" "$destination"
if [[ -n "${LOUPE_TOUCH_ARCHITECTURE:-}" ]]; then
  test "$(xcrun lipo -archs "$APP_PATH/LoupeExample")" = "$LOUPE_TOUCH_ARCHITECTURE"
fi
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH" || {
  install_status=$?
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    python3 - "$DEVICE" "$APP_PATH" <<'PY' || true
import json, pathlib, plistlib, subprocess, sys
try:
    info = plistlib.loads((pathlib.Path(sys.argv[2]) / 'Info.plist').read_bytes())
    keys = ['CFBundleIdentifier', 'CFBundleVersion', 'CFBundleExecutable', 'CFBundleSupportedPlatforms']
    pathlib.Path('/tmp/loupe-touch-install-metadata.json').write_text(
        json.dumps({key: info.get(key) for key in keys}, indent=2))
    with open('/tmp/loupe-touch-install-failure.log', 'w') as output:
        subprocess.run(['xcrun', 'simctl', 'spawn', sys.argv[1], 'log', 'show',
                        '--last', '2m', '--style', 'compact', '--info', '--debug',
                        '--predicate', 'process == "installd" OR process == "installcoordinationd"'],
                       stdout=output, stderr=subprocess.STDOUT, timeout=10)
except (OSError, subprocess.SubprocessError):
    pass
PY
  fi
  exit "$install_status"
}
if [[ "${LOUPE_TOUCH_PRECONFIGURED_INPUT:-0}" != "1" ]]; then
  KEYBOARD_BACKUP="$(mktemp /tmp/loupe-touch-keyboards.XXXXXX)"
  trap 'python3 Examples/LoupeExample/touch-keyboard.py "$DEVICE" restore "$KEYBOARD_BACKUP"; rm -f "$KEYBOARD_BACKUP"' EXIT
  python3 Examples/LoupeExample/touch-keyboard.py "$DEVICE" prepare "$KEYBOARD_BACKUP"
fi
capture_environment=()
if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
  capture_environment=(--env LOUPE_CAPTURE_DIAGNOSTICS=1)
fi
launch_output="$("$CLI" app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=touch ${capture_environment[@]+"${capture_environment[@]}"} --timeout 30)"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$launch_output" | tail -1)"
test -n "$HOST"
collect_capture_failure() {
  [[ "${GITHUB_ACTIONS:-}" == "true" ]] || return 0
  python3 - "$DEVICE" <<'PY' || true
import json, pathlib, shutil, subprocess, sys
try:
    container = subprocess.check_output(
        ['xcrun', 'simctl', 'get_app_container', sys.argv[1], 'dev.loupe.example', 'data'],
        text=True, timeout=10).strip()
    progress = pathlib.Path(container) / 'Library/Caches/loupe-capture-progress.txt'
    if progress.exists():
        shutil.copyfile(progress, '/tmp/loupe-touch-capture-progress.txt')
    # Use the identity already captured by this run, without another request
    # to a runtime whose observation request may be stalled.
    identities = sorted(pathlib.Path('/tmp').glob('loupe-touch-evidence*/runtime-identity.json'),
                        key=lambda path: path.stat().st_mtime, reverse=True)
    identity = next((value for path in identities
                     if (value := json.loads(path.read_text())).get('simulatorUDID') == sys.argv[1]), {})
    pid = identity.get('processIdentifier', 0)
    if pid > 0:
        subprocess.run(['/usr/bin/sample', str(pid), '1', '-file',
                        '/tmp/loupe-touch-runtime-failure-stack.txt'],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=5)
except (OSError, subprocess.SubprocessError):
    pass
PY
}
# Require the fixture's rendered frame after launch. SpringBoard's first-boot
# display is not the action surface being verified. Use the CLI screenshot's
# same deadline, and collect this evidence before emitting the first gesture.
"$CLI" act wait visible --host "$HOST" --test-id touch.uikit.button --timeout 15 \
  --output /tmp/loupe-touch-first-window.json || {
  collect_capture_failure
  exit 1
}
"$CLI" ui screenshot --udid "$DEVICE" --output /tmp/loupe-touch-app-ready.png || {
  collect_capture_failure
  exit 1
}
python3 Examples/LoupeExample/verify-touch-scenarios.py "$HOST" "$DEVICE" || {
  collect_capture_failure
  exit 1
}
# A fresh process must find SwiftUI controls before any UIKit action or
# `act targets` call has initialized native accessibility as a side effect.
launch_output="$("$CLI" app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=touch.swiftui ${capture_environment[@]+"${capture_environment[@]}"} --timeout 30)"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$launch_output" | tail -1)"
test -n "$HOST"
python3 Examples/LoupeExample/verify-touch-scenarios.py "$HOST" "$DEVICE" --swiftui-only || {
  collect_capture_failure
  exit 1
}
