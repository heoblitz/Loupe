#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

run_step() {
  local name="$1"
  shift
  echo "==> $name"
  "$@"
}

run_step "swift test" swift test
run_step "native work with one cooperative thread" env DISPATCH_COOPERATIVE_POOL_STRICT=1 swift test --filter SimulatorNativeWorkTests
run_step "HID framework loading" bash scripts/verify-hid-framework-loading.sh
run_step "HID touch messages" bash scripts/verify-hid-touch-messages.sh
run_step "simulator preference lifecycle" scripts/verify-simulator-preferences-lifecycle.sh
run_step "hosted Simulator widget safeguards" python3 scripts/verify-ci-simulator-widgets.py
run_step "release CLI build" swift build --configuration release --disable-sandbox --product loupe
run_step "CLI contracts" xcrun python3 scripts/verify-cli-contracts.py .build/release/loupe
run_step "platform builds" scripts/verify-platform-builds.sh
run_step "macOS example E2E" Examples/MacLoupeExample/run-macos-e2e.sh
run_step "tvOS example E2E" Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
run_step "watchOS example E2E" Examples/LoupeWatchExample/run-watchos-runtime-e2e.sh
run_step "injected log E2E" Examples/LoupeExample/run-injected.sh
run_step "runtime E2E" Examples/LoupeExample/run-runtime-e2e.sh
run_step "native scenario E2E" Examples/LoupeExample/run-native-scenarios.sh
run_step "touch gesture E2E" Examples/LoupeExample/run-touch-e2e.sh
run_step "bookmark E2E" Examples/LoupeExample/run-bookmark-e2e.sh

echo "agent work verification passed"
