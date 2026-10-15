#!/usr/bin/env bash

# Keep local E2E and hosted source/bottle jobs on the same toolchain.
configure_loupe_ios_verification() {
  local version
  local expected_version="${LOUPE_TOUCH_XCODE_VERSION:-26.3}"
  version="$(xcodebuild -version | sed -n '1p')"
  if [[ "$version" != "Xcode $expected_version" ]]; then
    echo "error: iOS verification requires Xcode $expected_version; selected $version. Set DEVELOPER_DIR explicitly." >&2
    return 1
  fi
  # Use the interpreter shipped with the selected Xcode, not Homebrew's
  # independently updated Python on hosted runners.
  export PATH="$(dirname "$(xcrun --find python3)"):$PATH"
  python3 --version >&2
  export LOUPE_LAUNCH_TIMEOUT="${LOUPE_LAUNCH_TIMEOUT:-30}"
  export LOUPE_SIMCTL_TERMINATE_TIMEOUT="${LOUPE_SIMCTL_TERMINATE_TIMEOUT:-20}"
}

loupe_ios_verification_device() {
  python3 - "${1:-${LOUPE_DEVICE:-}}" <<'DEVICE_PY'
import json, os, platform, subprocess, sys
architecture = platform.machine()
expected = os.environ.get('LOUPE_TOUCH_ARCHITECTURE', 'arm64')
assert architecture == expected, f'Expected native {expected}, got {architecture}'
version = os.environ.get('LOUPE_TOUCH_RUNTIME_VERSION', '26.2')
runtime = 'com.apple.CoreSimulator.SimRuntime.iOS-' + version.replace('.', '-')
inventory = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], timeout=60))
requested = sys.argv[1]
model = 'iPhone 17 Pro' if version.startswith('26.') else 'iPhone 16 Pro'
candidates = [d for d in inventory['devices'].get(runtime, [])
              if d['udid'] == requested] if requested else [d for d in inventory['devices'].get(runtime, []) if d['name'] == model]
assert candidates, f'No {requested or model} for iOS {version}; install/select the required runtime explicitly'
device = next((d for d in candidates if d['state'] == 'Booted'), candidates[0])
print(f'iOS verification: Xcode={os.environ.get("LOUPE_TOUCH_XCODE_VERSION", "26.3")} runtime={version} architecture={architecture} device={device["name"]} ({device["udid"]})', file=sys.stderr)
print(device['udid'])
DEVICE_PY
}

boot_loupe_ios_verification_device() {
  # The same readiness gate applies to source and bottle scenarios. launchd
  # can respond before data migration finishes, so it is not a fallback.
  local log_path="/tmp/loupe-touch-boot.log"
  if python3 - "$DEVICE" <<'BOOT_PY' >"$log_path" 2>&1
import subprocess, sys
subprocess.run(['xcrun', 'simctl', 'bootstatus', sys.argv[1], '-b'], check=True, timeout=180)
BOOT_PY
  then
    return
  fi
  tail -10 "$log_path" >&2
  echo "error: simulator $DEVICE did not finish booting; see $log_path" >&2
  return 124
}

prepare_loupe_ios_preferences() {
  KEYBOARD_BACKUP="$(mktemp /tmp/loupe-touch-keyboards.XXXXXX)"
  trap restore_loupe_ios_preferences EXIT
  python3 "$ROOT_DIR/Examples/LoupeExample/touch-keyboard.py" "$DEVICE" prepare "$KEYBOARD_BACKUP"
}

restore_loupe_ios_preferences() {
  local result=$?
  if [[ -s "$KEYBOARD_BACKUP" ]]; then
    if ! python3 "$ROOT_DIR/Examples/LoupeExample/touch-keyboard.py" "$DEVICE" restore "$KEYBOARD_BACKUP"; then
      echo "Simulator preferences restore failed; saved preferences: $KEYBOARD_BACKUP" >&2
      exit 1
    fi
  fi
  rm -f "$KEYBOARD_BACKUP"
  exit "$result"
}

build_loupe_example_simulator_artifacts() {
  local root_dir="${1:?root dir is required}"
  local destination="${2:-${LOUPE_EXAMPLE_DESTINATION:-generic/platform=iOS Simulator}}"
  local build_root="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-example-build}"
  local build_architecture="${LOUPE_TOUCH_ARCHITECTURE:-$(uname -m)}"
  local injector_derived_data="$build_root/LoupeInjector"
  local app_derived_data="$build_root/LoupeExample"

  # Xcode invalidates changed sources and destinations. Keep its incremental
  # products so multiple scenarios on the same runner do not rebuild from zero.
  mkdir -p "$injector_derived_data" "$app_derived_data"

  if [[ -n "${LOUPE_EXAMPLE_PREBUILT_INJECTOR:-}" ]]; then
    LOUPE_INJECTOR_PATH="$LOUPE_EXAMPLE_PREBUILT_INJECTOR"
  else
    xcodebuild \
      -scheme LoupeInjector \
      -destination "$destination" \
      -configuration Debug \
      -derivedDataPath "$injector_derived_data" \
      ONLY_ACTIVE_ARCH=YES \
      ARCHS="$build_architecture" \
      build >/tmp/loupe-injector-build.log
    LOUPE_INJECTOR_PATH="$injector_derived_data/Build/Products/Debug-iphonesimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector"
  fi

  xcodebuild \
    -project "$root_dir/Examples/LoupeExample/LoupeExample.xcodeproj" \
    -scheme LoupeExample \
    -destination "$destination" \
    -configuration Debug \
    -derivedDataPath "$app_derived_data" \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS="$build_architecture" \
    build >/tmp/loupe-example-build.log

  APP_PATH="$app_derived_data/Build/Products/Debug-iphonesimulator/LoupeExample.app"

  if [[ ! -x "$LOUPE_INJECTOR_PATH" ]]; then
    echo "error: built LoupeInjector not found at $LOUPE_INJECTOR_PATH" >&2
    exit 1
  fi
  if [[ ! -d "$APP_PATH" ]]; then
    echo "error: built LoupeExample.app not found at $APP_PATH" >&2
    exit 1
  fi

  export LOUPE_INJECTOR_PATH
}
