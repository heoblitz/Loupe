#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh
export LOUPE_EXAMPLE_BUILD_ROOT="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-touch-e2e-build}"
DEVICE="${LOUPE_DEVICE:-$(xcrun simctl list devices available --json | python3 -c '
import json,sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group if d["name"] == "iPhone 17 Pro"]
booted = next((d for d in devices if d["state"] == "Booted"), None)
print((booted or devices[0])["udid"])
')}"
echo "touch E2E simulator: $DEVICE"
xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$DEVICE" -b >/tmp/loupe-touch-boot.log 2>&1
swift build --product loupe >/tmp/loupe-touch-cli-build.log 2>&1
build_loupe_example_simulator_artifacts "$ROOT_DIR" "platform=iOS Simulator,id=$DEVICE"
xcrun simctl terminate "$DEVICE" dev.loupe.example >/dev/null 2>&1 || true
xcrun simctl install "$DEVICE" "$APP_PATH"
launch_output="$(.build/debug/loupe app launch --device "$DEVICE" --bundle-id dev.loupe.example --inject --env LOUPE_EXAMPLE_ROUTE=touch --timeout 30)"
HOST="$(awk '/^loupe host: / { print $3 }' <<<"$launch_output" | tail -1)"
test -n "$HOST"
python3 - "$HOST" "$DEVICE" <<'PY'
import concurrent.futures, json, pathlib, subprocess, sys, time, urllib.request, urllib.error
host = sys.argv[1]
device = sys.argv[2] if len(sys.argv) > 2 else None
cli = str(pathlib.Path('.build/debug/loupe').resolve())
out = pathlib.Path('/tmp') / f'loupe-touch-evidence-{time.time_ns()}'
out.mkdir(exist_ok=True)
print(f'evidence: {out}', flush=True)

def snapshot():
    path = out / 'snapshot.json'
    result = subprocess.run([cli, 'ui', 'snapshot', '--host', host, '--output', str(path)], capture_output=True, text=True, timeout=15)
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)
    return json.loads(path.read_text())

def node(test_id):
    return next(n for n in snapshot()['nodes'].values() if n.get('testID') == test_id)

def expect(test_id, text):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        value = node(test_id).get('text', '')
        if value == text: return
        time.sleep(0.05)
    raise AssertionError((test_id, text, value))

def point(test_id, fraction_x=0.5, fraction_y=0.5):
    f = node(test_id)['frame']
    return f'{f["x"] + f["width"] * fraction_x},{f["y"] + f["height"] * fraction_y}'

def act(command, args, trace):
    trace_path = out / trace
    selection = ['--udid', device] if device else []
    result = subprocess.run([cli, 'act', command, '--host', host] + selection + ['--trace-dir', str(trace_path)] + args,
                            capture_output=True, text=True, timeout=15)
    (out / (trace + '.log')).write_text(result.stdout + result.stderr)
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)

def post(body):
    request = urllib.request.Request(host + '/input/touch', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    return urllib.request.urlopen(request, timeout=5).read()

def touch(command, start_id, end=None, duration=None, hold=0, start_fraction=(0.5, 0.5)):
    x, y = map(float, point(start_id, *start_fraction).split(','))
    body = {'command': command, 'start': {'x': x, 'y': y}, 'holdDuration': hold, 'screen': snapshot()['screen']['size']}
    if end is not None:
        x, y = map(float, end.split(','))
        body['end'] = {'x': x, 'y': y}
    if duration is not None: body['duration'] = duration
    response = json.loads(post(body))
    (out / f'internal-{command}.json').write_text(json.dumps(response, indent=2))

# Public input needs no platform-specific flags. Existing duration supports a held tap.
time.sleep(1)
act('tap', ['--test-id', 'touch.tap'], 'cli-tap')
expect('touch.tap.status', 'Taps 1')
act('tap', ['--test-id', 'touch.hold', '--duration', '0.6'], 'cli-long-press')
expect('touch.hold.status', 'Holds 1')
before = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
act('drag', ['--from', point('touch.scroll', 0.5, 0.8), '--to', point('touch.scroll', 0.5, 0.25), '--duration', '0.4'], 'cli-drag')
time.sleep(0.3)
after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
assert after > before + 40, ('CLI drag', before, after)
before = after
act('swipe', ['--from', point('touch.scroll', 0.5, 0.2), '--to', point('touch.scroll', 0.5, 0.8), '--duration', '0.4', '--no-verify-scroll'], 'cli-swipe')
time.sleep(0.3)
after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
assert before > after + 50, ('CLI swipe', before, after)
print('existing CLI: gesture tap, long press, drag, and scroll passed', flush=True)

# Exercise the internal device dispatcher in a simulator without adding public CLI options.
touch('tap', 'touch.tap')
expect('touch.tap.status', 'Taps 2')
touch('tap', 'touch.hold', hold=0.6)
expect('touch.hold.status', 'Holds 2')
touch('drag', 'touch.drag', end=point('touch.drag', 0.7), duration=0.4, hold=0.6, start_fraction=(0.2, 0.5))
result = node('touch.drag.status')['text']
assert result.startswith('Drag completed ') and int(result.rsplit(' ', 1)[1]) > 100, result
before = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
touch('swipe', 'touch.scroll', end=point('touch.scroll', 0.5, 0.15), duration=0.4, start_fraction=(0.5, 0.85))
time.sleep(0.2)
after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
assert after > before + 50, ('internal swipe', before, after)
print('internal touch: gesture tap, long press, held drag, and scroll passed', flush=True)

# Existing explicit accessibility activation must keep its meaning and never retry as touch.
failed = subprocess.run([cli, 'act', 'tap', '--host', host, '--backend', 'runtime', '--test-id', 'touch.tap'], capture_output=True, text=True)
assert failed.returncode != 0 and 'accessibility_action_not_handled' in failed.stderr, failed.stderr
expect('touch.tap.status', 'Taps 2')

# Reject stale geometry before emitting any touch, then prove a new CLI tap still works.
try:
    post({'command': 'tap', 'start': {'x': 50, 'y': 50}, 'holdDuration': 0, 'screen': {'width': 1, 'height': 1}})
    raise AssertionError('Invalid touch request succeeded')
except urllib.error.HTTPError as error:
    assert error.code == 400
act('tap', ['--test-id', 'touch.tap'], 'cli-after-failure')
expect('touch.tap.status', 'Taps 3')

screen = snapshot()['screen']['size']
x, y = map(float, point('touch.hold').split(','))
body = {'command': 'tap', 'start': {'x': x, 'y': y}, 'holdDuration': 2.0, 'screen': screen}
with concurrent.futures.ThreadPoolExecutor() as pool:
    active = pool.submit(post, body)
    expect('touch.hold.status', 'Holds 3')
    try:
        post(dict(body, holdDuration=0))
        raise AssertionError('Competing touch succeeded')
    except urllib.error.HTTPError as error:
        assert error.code == 409 and 'touch_in_progress' in error.read().decode()
    active.result(timeout=5)
act('tap', ['--test-id', 'touch.tap'], 'cli-after-concurrency')
expect('touch.tap.status', 'Taps 4')
subprocess.run([cli, 'ui', 'report', '--host', host, '--output', str(out / 'report')], check=True, capture_output=True)
print(f'touch E2E passed; evidence: {out}')
PY
