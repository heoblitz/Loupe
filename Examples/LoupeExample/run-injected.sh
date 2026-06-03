#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PORT="${LOUPE_PORT:-}"
LAUNCH_TIMEOUT="${LOUPE_LAUNCH_TIMEOUT:-30}"

cd "$ROOT_DIR"

booted_udid() {
  xcrun simctl list devices booted --json | ruby -rjson -e '
    devices = JSON.parse(STDIN.read).fetch("devices").values.flatten
    booted = devices.find { |device| device["state"] == "Booted" && device["name"].include?("iPhone") }
    puts booted && booted["udid"]
  '
}

DEVICE="${LOUPE_DEVICE:-$(booted_udid)}"
if [[ -z "$DEVICE" ]]; then
  FIRST_DEVICE="$(xcrun simctl list devices available | awk -F '[()]' '/iPhone/ { print $2; exit }')"
  xcrun simctl boot "$FIRST_DEVICE"
  DEVICE="$FIRST_DEVICE"
fi

swift build

xcodebuild \
  -scheme LoupeInjector \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-injector-build.log

xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build >/tmp/loupe-example-build.log

export LOUPE_INJECTOR_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Debug-iphonesimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector' \
    -print0 | xargs -0 ls -t | head -1
)"

APP_PATH="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*Debug-iphonesimulator/LoupeExample.app' \
    -print0 | xargs -0 ls -td | head -1
)"

xcrun simctl install "$DEVICE" "$APP_PATH"
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true

LAUNCH_ARGUMENTS=(
  --device "$DEVICE"
  --bundle-id dev.loupe.example
  --inject
  --timeout "$LAUNCH_TIMEOUT"
)
if [[ -n "$PORT" ]]; then
  LAUNCH_ARGUMENTS+=(--env "LOUPE_PORT=$PORT")
fi
LAUNCH_OUTPUT="$(.build/debug/loupe app launch "${LAUNCH_ARGUMENTS[@]}")"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$LAUNCH_OUTPUT" | tail -1)"
if [[ -z "$HOST" ]]; then
  echo "error: loupe app launch did not report a runtime host" >&2
  echo "$LAUNCH_OUTPUT" >&2
  exit 1
fi

sleep 2

curl -sS "$HOST/health"
echo

SNAPSHOT_PATH="/tmp/loupe-example-snapshot.json"
DARK_SNAPSHOT_PATH="/tmp/loupe-example-dark-snapshot.json"
LOGS_PATH="/tmp/loupe-example-logs.json"
NETWORK_PATH="/tmp/loupe-example-network.json"
REFS_PATH="/tmp/loupe-example-refs.json"
FLAG_PATH="/tmp/loupe-example-flag.json"
FLAG_SET_PATH="/tmp/loupe-example-flag-set.json"
KEYCHAIN_PATH="/tmp/loupe-example-keychain.json"
HIT_TEST_PATH="/tmp/loupe-example-hit-test.json"
RESPONDER_PATH="/tmp/loupe-example-responder-chain.json"
ENV_PATH="/tmp/loupe-example-env.json"
ENV_READ_PATH="/tmp/loupe-example-env-read.json"
AUDIT_PATH="/tmp/loupe-example-audit.json"
PERF_PATH="/tmp/loupe-example-perf.json"
PERF_TRACE="/tmp/loupe-example-perf-trace"
INSPECT_PATH="/tmp/loupe-example-inspect.json"
rm -rf "$PERF_TRACE"
curl -sS "$HOST/snapshot" > "$SNAPSHOT_PATH"
.build/debug/loupe debug logs --host "$HOST" --output "$LOGS_PATH" >/dev/null
.build/debug/loupe debug network --host "$HOST" --output "$NETWORK_PATH" >/dev/null
.build/debug/loupe debug refs --host "$HOST" --output "$REFS_PATH" >/dev/null
.build/debug/loupe debug flags get new-nav --host "$HOST" --output "$FLAG_PATH" >/dev/null
.build/debug/loupe debug flags set new-nav --bool false --host "$HOST" --output "$FLAG_SET_PATH" >/dev/null
.build/debug/loupe debug keychain list --host "$HOST" --output "$KEYCHAIN_PATH" >/dev/null
.build/debug/loupe ui hit-test --host "$HOST" --point 201,437 --output "$HIT_TEST_PATH" >/dev/null
.build/debug/loupe ui responder-chain --host "$HOST" --test-id example.customerList --output "$RESPONDER_PATH" >/dev/null
.build/debug/loupe ui appearance --host "$HOST" --output "$ENV_READ_PATH" >/dev/null
.build/debug/loupe ui appearance dark --host "$HOST" --output "$ENV_PATH" >/dev/null
curl -sS "$HOST/snapshot" > "$DARK_SNAPSHOT_PATH"
.build/debug/loupe ui audit "$DARK_SNAPSHOT_PATH" --kind lowTextContrast > "$AUDIT_PATH"
.build/debug/loupe ui appearance system --host "$HOST" >/dev/null
.build/debug/loupe debug scroll --host "$HOST" --udid "$DEVICE" --from 201,740 --to 201,320 --trace-dir "$PERF_TRACE" --output "$PERF_PATH" >/dev/null

.build/debug/loupe ui query "$SNAPSHOT_PATH" --test-id example.customerList
.build/debug/loupe ui node "$SNAPSHOT_PATH" --test-id example.customerList > "$INSPECT_PATH"
ruby -rjson -e '
  logs = JSON.parse(File.read(ARGV.fetch(0)))
  log = logs.find { |entry| entry["message"] == "example_customers_visible" }
  abort "missing example_customers_visible log" unless log
  screen = log.dig("metadata", "screen", "value")
  abort "expected log screen=customers, got #{screen.inspect}" unless screen == "customers"
  background_log = logs.find { |entry| entry["message"] == "example_customers_background_visible" }
  abort "missing background example_customers_background_visible log" unless background_log
  background_screen = background_log.dig("metadata", "screen", "value")
  background_origin = background_log.dig("metadata", "origin", "value")
  abort "expected background log screen=customers, got #{background_screen.inspect}" unless background_screen == "customers"
  abort "expected background log origin=background, got #{background_origin.inspect}" unless background_origin == "background"
  network = JSON.parse(File.read(ARGV.fetch(2)))
  event = network.find { |entry| entry["url"] == "https://api.example.test/customers" }
  abort "missing customers network event" unless event
  abort "expected network status 200" unless event["statusCode"] == 200
  abort "expected GET method" unless event["method"] == "GET"
  abort "expected customers network metadata" unless event.dig("metadata", "screen", "value") == "customers"
  abort "expected customers response body" unless event["responseBody"]&.include?("Customer 1")
  refs = JSON.parse(File.read(ARGV.fetch(12)))
  abort "missing customer reference evidence" unless refs.any? { |entry| entry["owner"] == "CustomerListViewController" && entry["target"] == "DeviceActuationService" && entry["kind"] == "strong" }
  flag = JSON.parse(File.read(ARGV.fetch(3)))
  abort "expected new-nav=false" unless flag.dig("value", "value") == false
  flag_set = JSON.parse(File.read(ARGV.fetch(8)))
  abort "expected typed new-nav=false set" unless flag_set.dig("after", "value") == false
  keychain = JSON.parse(File.read(ARGV.fetch(4)))
  item = keychain.find { |entry| entry["service"] == "dev.loupe.example" && entry["account"] == "fixture" }
  abort "missing keychain fixture metadata" unless item
  hit = JSON.parse(File.read(ARGV.fetch(5)))
  abort "expected hit-test responder chain" unless hit.fetch("responderChain").any?
  responder = JSON.parse(File.read(ARGV.fetch(6)))
  abort "expected UITableView in responder chain" unless responder.fetch("responderChain").any? { |entry| entry["typeName"] == "UITableView" }
  env = JSON.parse(File.read(ARGV.fetch(7)))
  abort "expected dark appearance, got #{env["appearance"].inspect}" unless env["appearance"] == "dark"
  audit = JSON.parse(File.read(ARGV.fetch(13)))
  target_ids = ["example.customer.1.title", "example.customer.1.subtitle", "example.customer.1.status"]
  bad_contrast = audit.fetch("issues").select { |issue| issue["kind"] == "lowTextContrast" && target_ids.include?(issue["testID"]) }
  abort "unexpected dark contrast issues: #{bad_contrast.inspect}" unless bad_contrast.empty?
  env_read = JSON.parse(File.read(ARGV.fetch(9)))
  abort "expected env read appearance key" unless env_read.key?("appearance")
  perf = JSON.parse(File.read(ARGV.fetch(10)))
  abort "expected perf actionElapsed" unless perf["actionElapsed"].is_a?(Numeric) && perf["actionElapsed"] >= 0
  abort "expected perf traceDirectory" unless perf["traceDirectory"] == ARGV.fetch(11)
  abort "expected perf before offset" unless perf["beforeOffset"].is_a?(Hash)
  abort "expected perf after offset" unless perf["afterOffset"].is_a?(Hash)
  abort "expected perf delta" unless perf["delta"].is_a?(Hash)
  abort "expected changed scroll offset" unless perf["beforeOffset"] != perf["afterOffset"]
  delta_y = perf.dig("delta", "y").to_f
  abort "expected nonzero scroll delta" unless delta_y.abs > 1
  inspection = JSON.parse(File.read(ARGV.fetch(1)))
  custom = inspection.fetch("node").fetch("custom")
  abort "expected inspect screen=customers" unless custom.dig("screen", "value") == "customers"
  abort "expected inspect fixture=true" unless custom.dig("fixture", "value") == true
' "$LOGS_PATH" "$INSPECT_PATH" "$NETWORK_PATH" "$FLAG_PATH" "$KEYCHAIN_PATH" "$HIT_TEST_PATH" "$RESPONDER_PATH" "$ENV_PATH" "$FLAG_SET_PATH" "$ENV_READ_PATH" "$PERF_PATH" "$PERF_TRACE" "$REFS_PATH" "$AUDIT_PATH"
