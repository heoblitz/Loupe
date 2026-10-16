#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh
configure_loupe_ios_verification
DEVICE="$(loupe_ios_verification_device)"
export LOUPE_TOUCH_CLI="${LOUPE_TOUCH_CLI:-$ROOT_DIR/.build/debug/loupe}"
export LOUPE_EXAMPLE_BUILD_ROOT="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-touch-e2e-build}"
evidence="${IDB_EVIDENCE:-/tmp/loupe-idb-evidence}"
mkdir -p "$evidence"
prepare_loupe_ios_preferences
build_loupe_example_simulator_artifacts "$ROOT_DIR" "${LOUPE_EXAMPLE_DESTINATION:-generic/platform=iOS Simulator}"
boot_loupe_ios_verification_device
if [[ "${LOUPE_TOUCH_OPEN_DEVICE_HUB:-0}" == 1 ]]; then
  /usr/bin/open -a "${DEVELOPER_DIR%/Developer}/Applications/DeviceHub.app" "devices://device/open?id=$DEVICE"
fi
xcrun simctl install "$DEVICE" "$APP_PATH"
# Exact simulator PoC: do not initialize unrelated physical-device discovery.
"${IDB_COMPANION:?}" --only simulator --udid "$DEVICE" --grpc-port 0 --log-level debug --log-hid-details true > "$evidence/companion.jsonl" 2> "$evidence/companion.log" &
companion_pid=$!
cleanup() {
  local result=$?
  set +e
  kill "$companion_pid" 2>/dev/null || true
  wait "$companion_pid" 2>/dev/null || true
  # The shared preference lifecycle restores original keys and boot state locally.
  (exit "$result")
  restore_loupe_ios_preferences
}
trap cleanup EXIT
export IDB_ADDRESS
IDB_ADDRESS="$(python3 - "$evidence/companion.jsonl" <<'PY'
import json,pathlib,sys,time
p=pathlib.Path(sys.argv[1]); deadline=time.monotonic()+30
while time.monotonic()<deadline:
    for line in p.read_text().splitlines():
        try: d=json.loads(line)
        except ValueError: continue
        if d.get('grpc_port'):
            print('localhost:'+str(d['grpc_port']));sys.exit(0)
    time.sleep(.1)
raise SystemExit('Companion did not publish a gRPC port within 30s')
PY
)"
result=0
if [[ "${IDB_POC_MODE:-compare}" == standalone ]]; then
  python3 poc/idb/standalone.py
  exit 0
fi
for backend in native idb; do
  for route in touch touch.swiftui; do
    output="$evidence/$backend-$route"
    mkdir -p "$output"
    if "$LOUPE_TOUCH_CLI" app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env "LOUPE_EXAMPLE_ROUTE=$route" --timeout 30 > "$output/launch.log" 2>&1; then
      host="$(awk '/^loupe host: / { print $3 }' "$output/launch.log" | tail -1)"
      python3 poc/idb/verify.py --host "$host" --udid "$DEVICE" --backend "$backend" --route "$route" --output "$output" || result=1
    else
      tail -n 8 "$output/launch.log"
      result=1
    fi
  done
done
exit "$result"
