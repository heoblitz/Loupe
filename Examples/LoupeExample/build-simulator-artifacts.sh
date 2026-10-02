#!/usr/bin/env bash

build_loupe_example_simulator_artifacts() {
  local root_dir="${1:?root dir is required}"
  local destination="${2:-${LOUPE_EXAMPLE_DESTINATION:-generic/platform=iOS Simulator}}"
  local build_root="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-example-build}"
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
