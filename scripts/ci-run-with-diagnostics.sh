#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <name> <command> [args...]" >&2
  exit 64
fi

NAME="$1"
shift
TAIL_LINES="${LOUPE_CI_TAIL_LINES:-120}"
SUMMARY_BYTES="${LOUPE_CI_SUMMARY_BYTES:-1800}"
DIAGNOSTIC_GLOBS="${LOUPE_CI_DIAGNOSTICS:-/tmp/loupe-*}"
ATTEMPTS="${LOUPE_CI_ATTEMPTS:-1}"
RETRY_SLEEP="${LOUPE_CI_RETRY_SLEEP:-10}"
LOG_BASENAME="/tmp/loupe-ci-${NAME//[^[:alnum:]._-]/-}"

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

summarize_log() {
  local log_path="$1"
  local summary
  summary="$(
    tail -n 80 "$log_path" 2>/dev/null \
      | tail -c "$SUMMARY_BYTES" \
      | tr '\n' ' ' \
      | sed 's/%/%25/g; s/\r/%0D/g' \
      | cut -c 1-"$SUMMARY_BYTES"
  )"
  if [[ -z "$summary" ]]; then
    printf 'Command exited without captured output'
  else
    printf '%s' "$summary"
  fi
}

ATTEMPTS="$(positive_int_or_default "$ATTEMPTS" 1)"
RETRY_SLEEP="$(positive_int_or_default "$RETRY_SLEEP" 10)"
STATUS=0
OUTPUT_LOG="${LOG_BASENAME}.log"

for attempt in $(seq 1 "$ATTEMPTS"); do
  if [[ "$ATTEMPTS" -eq 1 ]]; then
    OUTPUT_LOG="${LOG_BASENAME}.log"
  else
    OUTPUT_LOG="${LOG_BASENAME}-attempt-${attempt}.log"
  fi

  echo "==> ${NAME} attempt ${attempt}/${ATTEMPTS}"
  set +e
  "$@" > >(tee "$OUTPUT_LOG") 2>&1
  STATUS=$?
  set -e
  STATUS="${STATUS:-0}"
  if [[ "$STATUS" -eq 0 ]]; then
    if [[ "$attempt" -gt 1 ]]; then
      echo "::notice title=${NAME} recovered::Attempt ${attempt}/${ATTEMPTS} passed after an earlier failure"
    fi
    exit 0
  fi

  if [[ "$attempt" -lt "$ATTEMPTS" ]]; then
    SUMMARY="$(summarize_log "$OUTPUT_LOG")"
    echo "::warning title=${NAME} attempt ${attempt} failed::Command exited with status ${STATUS}. Last output: ${SUMMARY}"
    sleep "$RETRY_SLEEP"
  fi
done

SUMMARY="$(
  summarize_log "$OUTPUT_LOG"
)"
if [[ -z "$SUMMARY" ]]; then
  SUMMARY="Command exited with status ${STATUS}"
else
  SUMMARY="Command exited with status ${STATUS}. Last output: ${SUMMARY}"
fi
echo "::error title=${NAME} failed::${SUMMARY}"
echo "::group::Loupe diagnostics"
for pattern in $DIAGNOSTIC_GLOBS; do
  matches=( $pattern )
  if [[ "${matches[0]}" == "$pattern" && ! -e "${matches[0]}" ]]; then
    continue
  fi

  for path in "${matches[@]}"; do
    if [[ -d "$path" ]]; then
      echo "--- $path/ ---"
      find "$path" -maxdepth 2 -type f | sort | head -50
      continue
    fi

    if [[ ! -f "$path" ]]; then
      continue
    fi

    byte_count="$(wc -c <"$path" | tr -d ' ')"
    echo "--- $path (${byte_count} bytes) ---"
    case "$path" in
      *.json|*.log|*.txt)
        tail -n "$TAIL_LINES" "$path" || true
        ;;
      *)
        echo "skipping binary or unsupported diagnostic preview"
        ;;
    esac
  done
done
echo "::endgroup::"

exit "$STATUS"
