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
run_step "release CLI build" swift build --configuration release --disable-sandbox --product loupe
run_step "platform builds" scripts/verify-platform-builds.sh
run_step "macOS example E2E" Examples/MacLoupeExample/run-macos-e2e.sh
run_step "tvOS example E2E" Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
run_step "injected log E2E" Examples/LoupeExample/run-injected.sh
run_step "runtime E2E" Examples/LoupeExample/run-runtime-e2e.sh
run_step "native scenario E2E" Examples/LoupeExample/run-native-scenarios.sh
run_step "bookmark E2E" Examples/LoupeExample/run-bookmark-e2e.sh

echo "agent work verification passed"
