#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/loupe-ci-readiness.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"
cat >"$TEST_DIR/bin/swift" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cp "$TEST_DIR/bin/swift" "$TEST_DIR/bin/xcodebuild"
cat >"$TEST_DIR/bin/xcrun" <<'STUB'
#!/usr/bin/env bash
[[ "$*" == "simctl list devices available --json" ]] || exit 9
if [[ "${LOUPE_TEST_SIMCTL_FAIL:-0}" == 1 ]]; then exit 7; fi
printf '{"devices":{}}\n'
STUB
chmod +x "$TEST_DIR/bin/"*
export PATH="$TEST_DIR/bin:$PATH"
export LOUPE_CI_SIMCTL_LIST_ATTEMPTS=1
export LOUPE_SIMCTL_LIST_TIMEOUT=3
export LOUPE_CI_LOG_DIR="$TEST_DIR"
export LOUPE_TEST_SIMCTL_FAIL=1
if "$ROOT_DIR/scripts/ci-print-toolchain.sh" --simulators >"$TEST_DIR/failure.log" 2>&1; then
  echo 'error: simulator readiness accepted a failed simctl' >&2; exit 1
else
  status=$?
fi
[[ "$status" == 7 ]] || { echo "error: expected simctl exit 7, got $status" >&2; exit 1; }
grep -q 'failed after 1 attempts' "$TEST_DIR/failure.log"
export LOUPE_TEST_SIMCTL_FAIL=0
"$ROOT_DIR/scripts/ci-print-toolchain.sh" --simulators >"$TEST_DIR/success.log" 2>&1
grep -q '"devices"' "$TEST_DIR/success.log"
echo 'CI simulator readiness passed: exact JSON probe and failure propagation'
