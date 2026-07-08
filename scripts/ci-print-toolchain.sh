#!/usr/bin/env bash
set -euo pipefail

INCLUDE_SIMULATORS=0
for argument in "$@"; do
  case "$argument" in
    --simulators)
      INCLUDE_SIMULATORS=1
      ;;
    *)
      echo "usage: $0 [--simulators]" >&2
      exit 64
      ;;
  esac
done

positive_int_or_default() {
  local value="$1"
  local fallback="$2"
  case "$value" in
    ''|*[!0-9]*)
      printf '%s\n' "$fallback"
      return
      ;;
  esac
  if [[ "$value" -le 0 ]]; then
    printf '%s\n' "$fallback"
  else
    printf '%s\n' "$value"
  fi
}

swift --version
xcodebuild -version

if [[ "$INCLUDE_SIMULATORS" -eq 0 ]]; then
  exit 0
fi

TIMEOUT="$(positive_int_or_default "${LOUPE_SIMCTL_LIST_TIMEOUT:-120}" 120)"
ATTEMPTS="$(positive_int_or_default "${LOUPE_CI_SIMCTL_LIST_ATTEMPTS:-3}" 3)"
STATUS=0

for attempt in $(seq 1 "$ATTEMPTS"); do
  LOG_PATH="/tmp/loupe-ci-simctl-list-devices-attempt-${attempt}.log"
  echo "simctl list devices available attempt ${attempt}/${ATTEMPTS} (timeout ${TIMEOUT}s)"
  if perl -e 'alarm shift @ARGV; exec @ARGV' "$TIMEOUT" xcrun simctl list devices available >"$LOG_PATH" 2>&1; then
    cat "$LOG_PATH"
    exit 0
  fi

  STATUS=$?
  echo "::warning title=simctl list attempt ${attempt} failed::xcrun simctl list devices available exited with ${STATUS}; see ${LOG_PATH}"
  tail -40 "$LOG_PATH" || true
  if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
    sleep 5
  fi
done

echo "::error title=simctl list failed::xcrun simctl list devices available failed after ${ATTEMPTS} attempts"
exit "$STATUS"
