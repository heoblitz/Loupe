#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d /tmp/loupe-preferences-lifecycle.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

verify_case() {
  local name="$1" actions="$2" runner="$3" should_restore="$4"
  local backup="$test_root/$name-backup" marker="$test_root/$name-restore"
  printf '{}\n' > "$backup"
  local result=0
  GITHUB_ACTIONS="$actions" RUNNER_ENVIRONMENT="$runner" \
    bash -c '
      set -euo pipefail
      ROOT_DIR="$1"
      source "$ROOT_DIR/Examples/LoupeExample/build-simulator-artifacts.sh"
      DEVICE=fixture-device
      KEYBOARD_BACKUP="$2"
      marker="$3"
      python3() {
        [[ "$2" == fixture-device && "$3" == restore && "$4" == "$KEYBOARD_BACKUP" ]]
        printf restored > "$marker"
      }
      trap restore_loupe_ios_preferences EXIT
      exit 37
    ' _ "$ROOT_DIR" "$backup" "$marker" || result=$?
  # Environment cleanup must never turn an original test failure into success.
  [[ "$result" == 37 ]]
  if [[ "$should_restore" == yes ]]; then
    [[ -f "$marker" && ! -e "$backup" ]]
  else
    [[ ! -e "$marker" && -f "$backup" ]]
  fi
}

verify_case local false github-hosted yes
verify_case self-hosted true self-hosted yes
verify_case hosted true github-hosted no
echo "Simulator preference lifecycle passed: local/self-hosted restore, hosted disposal, original failure preserved"
