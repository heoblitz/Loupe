#!/usr/bin/env bash
set -euo pipefail

HOST="${1:?runtime host required}"
DEVICE="${2:?simulator UDID required}"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
WEB_JSON="/tmp/loupe-web-accessibility.json"
TARGETS="/tmp/loupe-web-targets.txt"

# The view exists before WebContent has finished loading. Poll the actual
# accessibility result, and fail if the expected content never appears.
ready=false
for _ in {1..30}; do
  .build/debug/loupe ui web --host "$HOST" --udid "$DEVICE" --output "$WEB_JSON" >/dev/null
  if python3 - "$WEB_JSON" 2>/dev/null <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc['discovery'] == 'visible-point-grid' and doc['complete'] is False
nodes = doc['elements']
assert any(n.get('label') == 'Web Fixture' and n['role'] == 'heading' for n in nodes)
assert any(n.get('label') == 'Web action' and n['role'] == 'button' for n in nodes)
assert any(n.get('label') == 'Name' and n['role'] == 'textField' for n in nodes)
PY
  then ready=true; break; fi
  sleep 0.25
done
[[ "$ready" == true ]] || { echo 'error: web accessibility elements not observed' >&2; exit 1; }

.build/debug/loupe act targets --include-web --host "$HOST" --udid "$DEVICE" --search 'Web action' > "$TARGETS"
grep -Eq '^#1 button "Web action" \[tap\]$' "$TARGETS"
.build/debug/loupe act tap '#1' --host "$HOST" --udid "$DEVICE"
.build/debug/loupe ui web --host "$HOST" --udid "$DEVICE" --output "$WEB_JSON" >/dev/null
python3 - "$WEB_JSON" <<'PY'
import json, sys
nodes = json.load(open(sys.argv[1]))['elements']
assert any(n.get('label') == 'Web action activated' for n in nodes), 'web button did not change page state'
PY

.build/debug/loupe act targets --include-web --host "$HOST" --udid "$DEVICE" --search Name > "$TARGETS"
grep -Eq '^#1 textField "Name" \[tap\]$' "$TARGETS"
# Move the input after saving its alias. A real coordinate tap preserves that
# alias and verifies that revalidation finds the same moved web element.
read -r WEB_BUTTON_X WEB_BUTTON_Y < <(python3 - "$WEB_JSON" <<'PY'
import json, sys
button = next(n for n in json.load(open(sys.argv[1]))['elements'] if n.get('label') == 'Web action')
print(button['point']['x'], button['point']['y'])
PY
)
OLD_INPUT_Y="$(python3 - "$WEB_JSON" <<'PY'
import json, sys
print(next(n for n in json.load(open(sys.argv[1]))['elements'] if n.get('label') == 'Name' and n['role'] == 'textField')['point']['y'])
PY
)"
.build/debug/loupe act tap --host "$HOST" --udid "$DEVICE" --x "$WEB_BUTTON_X" --y "$WEB_BUTTON_Y"
.build/debug/loupe ui web --host "$HOST" --udid "$DEVICE" --output "$WEB_JSON" >/dev/null
python3 - "$WEB_JSON" "$OLD_INPUT_Y" <<'PY'
import json, sys
current = next(n for n in json.load(open(sys.argv[1]))['elements'] if n.get('label') == 'Name' and n['role'] == 'textField')
assert abs(current['point']['y'] - float(sys.argv[2])) > 25, 'web input did not move far enough to exercise revalidation'
PY
.build/debug/loupe act input '#1' Loupe --host "$HOST" --udid "$DEVICE"
.build/debug/loupe ui web --host "$HOST" --udid "$DEVICE" --output "$WEB_JSON" >/dev/null
python3 - "$WEB_JSON" <<'PY'
import json, sys
nodes = json.load(open(sys.argv[1]))['elements']
assert any(n.get('role') == 'textField' and n.get('label') == 'Name' and n.get('value') == 'Loupe' for n in nodes), 'web input value did not change'
PY
echo 'web accessibility discovery, tap, and input passed'
