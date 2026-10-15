#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
archive="${1:?output archive is required}"
source Examples/LoupeExample/build-simulator-artifacts.sh
configure_loupe_ios_verification
if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: CI artifacts require a clean checkout for source provenance" >&2
  exit 1
fi
source_sha="$(git rev-parse HEAD)"

# Compile on a build host; the runtime job never needs compiler services.
build_root="$(mktemp -d /tmp/loupe-ci-ios-build.XXXXXX)"
stage="$(mktemp -d /tmp/loupe-ci-ios-stage.XXXXXX)"
trap 'rm -rf "$stage" "$build_root"' EXIT
swift build --product loupe > /tmp/loupe-ci-cli-build.log 2>&1
cli_dir="$(swift build --product loupe --show-bin-path)"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
args=(--scratch-path "$build_root/injector" --product LoupeInjector --sdk "$sdk" --triple arm64-apple-ios15.0-simulator)
swift build "${args[@]}" > /tmp/loupe-ci-injector-build.log 2>&1
injector_dir="$(swift build "${args[@]}" --show-bin-path)"
export LOUPE_EXAMPLE_PREBUILT_INJECTOR="$injector_dir/libLoupeInjector.dylib"
export LOUPE_EXAMPLE_BUILD_ROOT="$build_root/example"
unset LOUPE_EXAMPLE_PREBUILT_APP
build_loupe_example_simulator_artifacts "$ROOT_DIR" 'generic/platform=iOS Simulator'

cp "$cli_dir/loupe" "$stage/loupe"
cp "$LOUPE_INJECTOR_PATH" "$stage/LoupeInjector"
ditto "$APP_PATH" "$stage/LoupeExample.app"
test "$(git rev-parse HEAD)" = "$source_sha"
test -z "$(git status --porcelain)"
printf '%s\n' "$source_sha" > "$stage/source-sha"
xcodebuild -version > "$stage/toolchain.txt"
tar -C "$stage" -czf "$archive" .
echo "iOS artifacts: $archive (source $(cat "$stage/source-sha"))"
