#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
source Examples/LoupeExample/build-simulator-artifacts.sh
export LOUPE_EXAMPLE_BUILD_ROOT="${LOUPE_EXAMPLE_BUILD_ROOT:-/tmp/loupe-touch-e2e-build}"
DEVICE="${LOUPE_DEVICE:-$(xcrun simctl list devices available --json | python3 -c 'import json,sys; ds=json.load(sys.stdin)["devices"]; print(next(d["udid"] for group in ds.values() for d in group if d["name"] == "iPhone 17 Pro"))')}"
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
host, device = sys.argv[1:]
cli = str(pathlib.Path('.build/debug/loupe').resolve())
out = pathlib.Path('/tmp') / f'loupe-touch-evidence-{time.time_ns()}'
out.mkdir(exist_ok=True)

def snapshot():
    path = out / 'snapshot.json'
    subprocess.run([cli, 'ui', 'snapshot', '--host', host, '--output', str(path)], check=True, capture_output=True)
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

def act(backend, command, args, trace):
    trace_path = out / trace
    subprocess.run([cli, 'act', command, '--host', host, '--udid', device,
                    '--backend', backend, '--trace-dir', str(trace_path)] + args,
                   check=True, capture_output=True, text=True, timeout=15)

time.sleep(1)
for index, backend in enumerate(['native', 'touch'], 1):
    act(backend, 'tap', ['--test-id', 'touch.tap'], backend + '-tap')
    expect('touch.tap.status', f'Taps {index}')
    act(backend, 'tap', ['--test-id', 'touch.hold', '--hold-duration', '0.6'], backend + '-hold')
    expect('touch.hold.status', f'Holds {index}')
    act(backend, 'drag', ['--from', point('touch.drag', 0.2), '--to', point('touch.drag', 0.7),
                         '--hold-duration', '0.6', '--duration', '0.4'], backend + '-drag')
    result = node('touch.drag.status')['text']
    assert result.startswith('Drag completed ') and int(result.rsplit(' ', 1)[1]) > 100, result
    before = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    act(backend, 'swipe', ['--from', point('touch.scroll', 0.5, 0.85), '--to', point('touch.scroll', 0.5, 0.15),
                         '--duration', '0.4', '--no-verify-scroll'], backend + '-swipe')
    time.sleep(0.2)
    data = node('touch.scroll')
    after = data['uikit']['scrollView']['contentOffset']['y']
    assert after > before + 50, (backend, before, after)
    print(f'{backend}: gesture tap, long press, held drag, and scroll passed')

# Explicit accessibility activation must remain distinct from touch input.
failed = subprocess.run([cli, 'act', 'tap', '--host', host, '--backend', 'runtime', '--test-id', 'touch.tap'], capture_output=True, text=True)
assert failed.returncode != 0 and 'accessibility_action_not_handled' in failed.stderr, failed.stderr
expect('touch.tap.status', 'Taps 2')

# Reject stale geometry before emitting any touch, then prove a new tap still works.
request = urllib.request.Request(host + '/input/touch', data=json.dumps({
    'command': 'tap', 'start': {'x': 50, 'y': 50}, 'holdDuration': 0,
    'screen': {'width': 1, 'height': 1}
}).encode(), headers={'Content-Type': 'application/json'})
try:
    urllib.request.urlopen(request)
    raise AssertionError('Invalid touch request succeeded')
except urllib.error.HTTPError as error:
    assert error.code == 400
act('touch', 'tap', ['--test-id', 'touch.tap'], 'touch-after-failure')
expect('touch.tap.status', 'Taps 3')
# One ongoing touch must reject a competing touch without dispatching it.
screen = snapshot()['screen']['size']
x, y = map(float, point('touch.hold').split(','))
body = {'command': 'tap', 'start': {'x': x, 'y': y}, 'holdDuration': 2.0, 'screen': screen}
def post(body):
    request = urllib.request.Request(host + '/input/touch', data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    return urllib.request.urlopen(request, timeout=5).read()
with concurrent.futures.ThreadPoolExecutor() as pool:
    active = pool.submit(post, body)
    expect('touch.hold.status', 'Holds 3')
    competing = dict(body, holdDuration=0)
    try:
        post(competing)
        raise AssertionError('Competing touch succeeded')
    except urllib.error.HTTPError as error:
        assert error.code == 409 and 'touch_in_progress' in error.read().decode()
    active.result(timeout=5)
act('touch', 'tap', ['--test-id', 'touch.tap'], 'touch-after-concurrency')
expect('touch.tap.status', 'Taps 4')
subprocess.run([cli, 'ui', 'report', '--host', host, '--output', str(out / 'report')], check=True, capture_output=True)
print(f'touch E2E passed; evidence: {out}')
PY
