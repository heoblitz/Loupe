#!/usr/bin/env bash

build_loupe_example_simulator_artifacts() {
  local root_dir="${1:?root dir is required}"
  local destination="${2:-${LOUPE_EXAMPLE_DESTINATION:-generic/platform=iOS Simulator}}"
  local build_root="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-example-build}"
  local injector_derived_data="$build_root/LoupeInjector"
  local app_derived_data="$build_root/LoupeExample"

  rm -rf "$build_root"
  mkdir -p "$injector_derived_data" "$app_derived_data"

  xcodebuild \
    -scheme LoupeInjector \
    -destination "$destination" \
    -configuration Debug \
    -derivedDataPath "$injector_derived_data" \
    ONLY_ACTIVE_ARCH=YES \
    build >/tmp/loupe-injector-build.log

  xcodebuild \
    -project "$root_dir/Examples/LoupeExample/LoupeExample.xcodeproj" \
    -scheme LoupeExample \
    -destination "$destination" \
    -configuration Debug \
    -derivedDataPath "$app_derived_data" \
    ONLY_ACTIVE_ARCH=YES \
    build >/tmp/loupe-example-build.log

  LOUPE_INJECTOR_PATH="$injector_derived_data/Build/Products/Debug-iphonesimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector"
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
