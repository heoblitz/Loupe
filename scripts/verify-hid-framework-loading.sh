#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP_ROOT="${TMPDIR:-/tmp}"
TEST_DIR="$(mktemp -d "${TEST_TMP_ROOT%/}/loupe-hid-frameworks.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT

# Include the production loader in a separate process for each fixture so
# NSBundle's loaded-bundle cache cannot hide a failed path lookup.
cat >"$TEST_DIR/probe.m" <<'EOF'
#import "LoupeHID.m"

int main(void) {
    @autoreleasepool {
        char *error = NULL;
        bool loaded = LoupeHIDLoadFrameworks(&error);
        if (error != NULL) {
            fprintf(stderr, "%s\n", error);
            LoupeHIDFreeCString(error);
        }
        return loaded ? 0 : 1;
    }
}
EOF

xcrun clang -fobjc-arc -framework AppKit -framework CoreImage -framework IOSurface -framework ImageIO \
  -I "$ROOT_DIR/Sources/LoupeHID" -I "$ROOT_DIR/Sources/LoupeHID/include" \
  "$TEST_DIR/probe.m" -o "$TEST_DIR/probe"
printf 'void LoupeFrameworkFixture(void) {}\n' | \
  xcrun clang -x c -dynamiclib -o "$TEST_DIR/fixture" -

make_framework() {
  local path="$1"
  mkdir -p "$path"
  cp "$TEST_DIR/fixture" "$path/SimulatorKit"
  cat >"$path/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.loupe.SimulatorKitFixture</string>
<key>CFBundleExecutable</key><string>SimulatorKit</string>
<key>CFBundlePackageType</key><string>FMWK</string>
</dict></plist>
EOF
}

legacy="$TEST_DIR/legacy/Xcode.app/Contents/Developer"
make_framework "$legacy/Library/PrivateFrameworks/SimulatorKit.framework"
DEVELOPER_DIR="$legacy" "$TEST_DIR/probe"

shared="$TEST_DIR/shared/Xcode.app/Contents/Developer"
mkdir -p "$shared"
make_framework "$(dirname "$shared")/SharedFrameworks/SimulatorKit.framework"
DEVELOPER_DIR="$shared" "$TEST_DIR/probe"
DEVELOPER_DIR="$shared/" "$TEST_DIR/probe"

# An existing but unloadable legacy bundle must not prevent the fallback.
make_framework "$shared/Library/PrivateFrameworks/SimulatorKit.framework"
printf 'invalid framework executable\n' >"$shared/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
DEVELOPER_DIR="$shared" "$TEST_DIR/probe" 2>"$TEST_DIR/fallback.log"

missing="$TEST_DIR/missing/Xcode.app/Contents/Developer"
mkdir -p "$missing"
if DEVELOPER_DIR="$missing" "$TEST_DIR/probe" 2>"$TEST_DIR/missing.log"; then
  echo "error: missing SimulatorKit unexpectedly loaded" >&2
  exit 1
fi
for expected in \
  'failed to load SimulatorKit; tried:' \
  '/missing/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework' \
  '/missing/Xcode.app/Contents/SharedFrameworks/SimulatorKit.framework'; do
  if ! grep -Fq "$expected" "$TEST_DIR/missing.log"; then
    echo "error: missing expected diagnostic: $expected" >&2
    cat "$TEST_DIR/missing.log" >&2
    exit 1
  fi
done

echo "HID framework loading passed: legacy, shared, trailing slash, unloadable fallback, missing diagnostics"
