#!/usr/bin/env python3
"""Verify CLI and internal touch results in the same simulator or linked device fixture."""
import concurrent.futures, json, os, pathlib, re, subprocess, sys, threading, time, urllib.request, urllib.error
host = sys.argv[1]
device = (sys.argv[2] or None) if len(sys.argv) > 2 else None
cli = str(pathlib.Path(os.environ.get('LOUPE_TOUCH_CLI', '.build/debug/loupe')).resolve())
out = pathlib.Path('/tmp') / f'loupe-touch-evidence-{time.time_ns()}'
out.mkdir(exist_ok=True)
print(f'evidence: {out}', flush=True)
with urllib.request.urlopen(host + '/status', timeout=5) as response:
    identity = json.load(response)['identity']
(out / 'runtime-identity.json').write_text(json.dumps(identity, indent=2))
expected_backend = 'auto' if identity.get('simulatorUDID') else 'touch'
if os.environ.get('LOUPE_TOUCH_OPEN_DEVICE_HUB') == '1':
    assert device, 'Device Hub verification requires an exact simulator device'
    state = subprocess.run(['xcrun', 'simctl', 'spawn', device, 'notifyutil', '-g',
                            'com.apple.coredevice.dtuhidd.active'],
                           capture_output=True, text=True, check=True, timeout=10)
    (out / 'device-hub-state.log').write_text(state.stdout + state.stderr)
    values = state.stdout.split()
    assert values and values[-1] == '1', ('Device Hub input route is not active', state.stdout)
    print('Device Hub input route is active', flush=True)

def snapshot():
    path = out / 'snapshot.json'
    result = subprocess.run([cli, 'ui', 'snapshot', '--host', host, '--output', str(path)], capture_output=True, text=True, timeout=15)
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)
    return json.loads(path.read_text())

def alias_tap(test_id, trace):
    result = subprocess.run([cli, 'act', 'targets', '--host', host, '--search', test_id],
                            capture_output=True, text=True, timeout=15)
    (out / (trace + '-targets.txt')).write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stderr
    aliases = re.findall(r'^#\d+\b', result.stdout, re.MULTILINE)
    assert len(aliases) == 1, result.stdout
    act('tap', [aliases[0]], trace)

def node(test_id):
    return next(n for n in snapshot()['nodes'].values() if n.get('testID') == test_id)

def expect(test_id, text):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        value = node(test_id).get('text', '')
        if value == text:
            (out / (test_id + '.json')).write_text(json.dumps(snapshot(), indent=2))
            return
        time.sleep(0.05)
    raise AssertionError((test_id, text, value))

def point(test_id, fraction_x=0.5, fraction_y=0.5):
    f = node(test_id)['frame']
    return f'{f["x"] + f["width"] * fraction_x},{f["y"] + f["height"] * fraction_y}'

def act(command, args, trace, expect_rejection=False):
    trace_path = out / trace
    selection = ['--udid', device] if device else []
    trace_arguments = [] if command == 'input' else ['--trace-dir', str(trace_path)]
    arguments = [cli, 'act', command] + args + ['--host', host] + selection + trace_arguments
    # Account for both existing 10s screenshot phases separately from the
    # original 15s input budget. CLI request/capture deadlines stay unchanged;
    # diagnostic capture errors are recorded; app-state checks remain mandatory.
    command_budget = 15 + (2 * 10 if trace_arguments else 0)
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=command_budget)
    except subprocess.TimeoutExpired as error:
        (out / (trace + '.log')).write_text(
            (error.stdout or b'').decode(errors='replace') + (error.stderr or b'').decode(errors='replace'))
        raise RuntimeError(f'Action and requested trace did not complete within {command_budget}s: {trace}') from error
    (out / (trace + '.log')).write_text(result.stdout + result.stderr)
    if expect_rejection:
        assert result.returncode != 0, result.stdout + result.stderr
        error = json.loads((trace_path / 'error.json').read_text())['message']
        assert any(reason in error for reason in (
            'accessibility_action_not_handled',
            'No native accessibility action matched selector',
            'Matched accessibility node does not expose a tap action')), error
        assert not (trace_path / 'action-after.json').exists()
        return
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)
    for line in result.stderr.splitlines():
        if line.startswith('warning: '):
            print(f'{trace}: {line}', flush=True)
    if command == 'tap':
        record = json.loads((trace_path / 'action-target.json').read_text())
        assert record['backend'] == expected_backend, record

def post(body, path='/input/touch'):
    request = urllib.request.Request(host + path, data=json.dumps(body).encode(), headers={'Content-Type': 'application/json'})
    return urllib.request.urlopen(request, timeout=5).read()

def touch(command, start_id, end=None, duration=None, hold=0, start_fraction=(0.5, 0.5)):
    x, y = map(float, point(start_id, *start_fraction).split(','))
    body = {'command': command, 'start': {'x': x, 'y': y}, 'holdDuration': hold, 'screen': snapshot()['screen']['size']}
    if end is not None:
        x, y = map(float, end.split(','))
        body['end'] = {'x': x, 'y': y}
    if duration is not None: body['duration'] = duration
    response = json.loads(post(body))
    (out / f'internal-{start_id}-{command}-{time.time_ns()}.json').write_text(json.dumps({'request': body, 'response': response}, indent=2))

def verify_button_routes(kind, starting_count):
    test_id = f'touch.{kind}.button'
    status_id = f'touch.{kind}.status'
    title = 'UIKit' if kind == 'uikit' else 'SwiftUI'
    alias_tap(test_id, 'cli-' + kind + '-alias')
    expect(status_id, f'{title} taps {starting_count + 1}')
    x, y = point(test_id).split(',')
    act('tap', ['--x', x, '--y', y], 'cli-' + kind + '-coordinates')
    expect(status_id, f'{title} taps {starting_count + 2}')
    current = snapshot()
    ref = next(n['ref'] for n in current['nodes'].values() if n.get('testID') == test_id)
    saved = out / (kind + '-ref-snapshot.json')
    saved.write_text(json.dumps(current))
    act('tap', ['--snapshot', str(saved), '--ref', ref], 'cli-' + kind + '-ref')
    expect(status_id, f'{title} taps {starting_count + 3}')
def verify_discovery_and_repeated_taps(kind):
    result = subprocess.run([cli, 'act', 'targets', '--host', host], capture_output=True, text=True, check=True, timeout=15)
    (out / (kind + '-meaningful-targets.txt')).write_text(result.stdout)
    for noise in ['UIKit taps', 'SwiftUI taps', 'Input changed:', 'Double taps', 'Taps ', 'Pan waiting']:
        assert noise not in result.stdout, ('Decoration leaked into targets', result.stdout)
    assert f'touch.{kind}.tap.status' not in result.stdout, ('Handler-free status leaked into targets', result.stdout)
    result = subprocess.run([cli, 'act', 'targets', '--host', host, '--search', f'touch.{kind}.double'], capture_output=True, text=True, check=True, timeout=15)
    (out / (kind + '-double-target.txt')).write_text(result.stdout)
    aliases = re.findall(r'^#\d+\b', result.stdout, re.MULTILINE)
    assert len(aliases) == 1 and '[double-tap]' in result.stdout, result.stdout
    invalid = subprocess.run([cli, 'act', 'tap', aliases[0], '--host', host], capture_output=True, text=True, timeout=15)
    assert invalid.returncode != 0 and 'requested tap' in invalid.stderr, invalid.stderr
    expect(f'touch.{kind}.double.status', 'Double taps 0')
    act('tap', [aliases[0], '--count', '2'], kind + '-double-alias')
    expect(f'touch.{kind}.double.status', 'Double taps 1')
    # A lone contact must not satisfy a double-tap recognizer.
    act('tap', ['--test-id', f'touch.{kind}.double'], kind + '-single-on-double')
    time.sleep(0.4)
    expect(f'touch.{kind}.double.status', 'Double taps 1')
    x, y = point(f'touch.{kind}.double').split(',')
    act('tap', ['--x', x, '--y', y, '--count', '2'], kind + '-double-coordinates')
    expect(f'touch.{kind}.double.status', 'Double taps 2')
    result = subprocess.run([cli, 'act', 'targets', '--host', host, '--search', f'touch.{kind}.pan'], capture_output=True, text=True, check=True, timeout=15)
    assert '[drag]' in result.stdout, result.stdout
    act('drag', ['--from', point(f'touch.{kind}.pan', 0.15), '--to', point(f'touch.{kind}.pan', 0.85), '--duration', '0.4'], kind + '-plain-pan')
    value = node(f'touch.{kind}.pan.status')['text']
    assert value.startswith('Pan completed ') and int(value.rsplit(' ', 1)[1]) > 70, value
    print(f'{kind}: non-accessibility double tap and drag targets changed app state', flush=True)

literal = 'Hello Loupe 123! 한글 👋🏼'

def verify_uikit():
    # Public input needs no platform-specific flags. Existing duration supports a held tap.
    time.sleep(1)
    # Verify the prepared input mode before the long touch suite. Failure is an
    # environment/setup error, not a reason to retry actions or weaken Unicode checks.
    act('tap', ['--test-id', 'touch.input'], 'keyboard-preflight')
    expect('touch.input.status', 'Input mode: ko-KR')
    act('tap', ['--test-id', 'touch.uikit.button'], 'cli-uikit-button')
    expect('touch.uikit.status', 'UIKit taps 1')
    print('CLI UIKit button changed application state', flush=True)
    act('tap', ['--test-id', 'touch.tap'], 'cli-tap')
    expect('touch.tap.status', 'Taps 1')
    act('tap', ['--test-id', 'touch.hold', '--duration', '0.6'], 'cli-long-press')
    expect('touch.hold.status', 'Holds 1')
    before = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    act('drag', ['--from', point('touch.scroll', 0.5, 0.8), '--to', point('touch.scroll', 0.5, 0.25), '--duration', '0.4'], 'cli-drag')
    time.sleep(0.3)
    after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    assert after > before + node('touch.scroll')['frame']['height'] * 0.3, ('CLI drag', before, after)
    before = after
    act('swipe', ['--from', point('touch.scroll', 0.5, 0.2), '--to', point('touch.scroll', 0.5, 0.8), '--duration', '0.4', '--no-verify-scroll'], 'cli-swipe')
    time.sleep(0.3)
    after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    assert before > after + node('touch.scroll')['frame']['height'] * 0.3, ('CLI swipe', before, after)
    print('existing CLI: gesture tap, long press, drag, and scroll passed', flush=True)

    # Exercise the internal device dispatcher in a simulator without adding public CLI options.
    touch('tap', 'touch.uikit.button')
    expect('touch.uikit.status', 'UIKit taps 2')
    print('internal UIKit button changed application state', flush=True)
    touch('tap', 'touch.tap')
    expect('touch.tap.status', 'Taps 2')
    touch('tap', 'touch.hold', hold=0.6)
    expect('touch.hold.status', 'Holds 2')
    # A regular CLI drag moves immediately. A held tap followed by a separate
    # drag cannot preserve the same contact, so it must not complete this gesture.
    act('drag', ['--from', point('touch.drag', 0.2), '--to', point('touch.drag', 0.7), '--duration', '0.4'], 'cli-immediate-drag')
    expect('touch.drag.status', 'Drag waiting')
    act('drag', ['--from', point('touch.drag', 0.2), '--to', point('touch.drag', 0.75), '--hold-duration', '0.6', '--duration', '0.4'], 'cli-held-drag')
    public_drag = node('touch.drag.status')['text']
    assert public_drag.startswith('Drag completed ') and int(public_drag.rsplit(' ', 1)[1]) > 100, public_drag
    touch('drag', 'touch.drag', end=point('touch.drag', 0.7), duration=0.4, hold=0.6, start_fraction=(0.2, 0.5))
    result = node('touch.drag.status')['text']
    assert result.startswith('Drag completed ') and int(result.rsplit(' ', 1)[1]) > 100, result
    assert result != public_drag, ('Internal held drag did not change state', result)
    before = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    touch('swipe', 'touch.scroll', end=point('touch.scroll', 0.5, 0.15), duration=0.4, start_fraction=(0.5, 0.85))
    time.sleep(0.2)
    after = node('touch.scroll')['uikit']['scrollView']['contentOffset']['y']
    assert after > before + node('touch.scroll')['frame']['height'] * 0.3, ('internal swipe', before, after)
    print('internal touch: gesture tap, long press, held drag, and scroll passed', flush=True)

    # Existing explicit accessibility activation must keep its meaning and never retry as touch.
    act('tap', ['--backend', 'runtime', '--test-id', 'touch.tap'],
        'cli-rejected-runtime', expect_rejection=True)
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
    # Send both requests before waiting for UI observations. A full snapshot
    # can outlast the held touch, so observing its counter first does not prove
    # that a later request actually competes with it.
    ready = threading.Barrier(2)
    def competing_touch():
        ready.wait(timeout=5)
        try:
            return 200, post(body)
        except urllib.error.HTTPError as error:
            return error.code, error.read()
    with concurrent.futures.ThreadPoolExecutor() as pool:
        attempts = [pool.submit(competing_touch) for _ in range(2)]
        responses = [attempt.result(timeout=5) for attempt in attempts]
    assert sorted(code for code, _ in responses) == [200, 409], responses
    assert any(code == 409 and b'touch_in_progress' in response
               for code, response in responses), responses
    expect('touch.hold.status', 'Holds 3')
    act('tap', ['--test-id', 'touch.tap'], 'cli-after-concurrency')
    expect('touch.tap.status', 'Taps 4')
    try:
        post({'text': 'must not be inserted'}, '/input/text')
        raise AssertionError('Unfocused text input succeeded')
    except urllib.error.HTTPError as error:
        assert error.code == 400 and 'text_input_not_focused' in error.read().decode()
    act('tap', ['--test-id', 'touch.input'], 'cli-focus-korean-input')
    expect('touch.input.status', 'Input mode: ko-KR')
    act('input', ['--test-id', 'touch.input', '--text', literal], 'cli-text-input')
    expect('touch.input', literal)
    expect('touch.input.status', 'Input changed: ' + literal)
    act('tap', ['--test-id', 'touch.uikit.button'], 'cli-dismiss-keyboard')
    expect('touch.uikit.status', 'UIKit taps 3')
    print('Korean keyboard: CLI input preserved English, Korean, emoji, and editingChanged', flush=True)
    # Exercise native action discovery and fresh alias resolution as well as
    # explicit coordinates. Each route must increment the app-owned counter once.
    verify_discovery_and_repeated_taps('uikit')
    verify_button_routes('uikit', 3)
    subprocess.run([cli, 'ui', 'report', '--host', host, '--output', str(out / 'uikit-report')], check=True, capture_output=True, timeout=30)
    act('tap', ['--test-id', 'touch.open.swiftui'], 'cli-open-swiftui')

def verify_swiftui():
    act('tap', ['--test-id', 'touch.swiftui.button'], 'cli-swiftui-button')
    expect('touch.swiftui.status', 'SwiftUI taps 1')
    expect('touch.swiftui.title', 'SwiftUI touch fixtures')
    touch('tap', 'touch.swiftui.button')
    expect('touch.swiftui.status', 'SwiftUI taps 2')
    act('tap', ['--test-id', 'touch.swiftui.tap'], 'cli-swiftui-gesture-tap')
    expect('touch.swiftui.tap.status', 'Taps 1')
    act('tap', ['--test-id', 'touch.swiftui.hold', '--duration', '0.6'], 'cli-swiftui-long-press')
    expect('touch.swiftui.hold.status', 'Holds 1')
    touch('tap', 'touch.swiftui.tap')
    expect('touch.swiftui.tap.status', 'Taps 2')
    touch('tap', 'touch.swiftui.hold', hold=0.6)
    expect('touch.swiftui.hold.status', 'Holds 2')
    act('drag', ['--from', point('touch.swiftui.drag', 0.2), '--to', point('touch.swiftui.drag', 0.8), '--duration', '0.4'], 'cli-swiftui-immediate-drag')
    assert not node('touch.swiftui.drag.status')['text'].startswith('Drag completed '), 'Immediate drag completed the held gesture'
    act('drag', ['--from', point('touch.swiftui.drag', 0.2), '--to', point('touch.swiftui.drag', 0.75), '--hold-duration', '0.6', '--duration', '0.4'], 'cli-swiftui-held-drag')
    public_drag = node('touch.swiftui.drag.status')['text']
    assert public_drag.startswith('Drag completed ') and int(public_drag.rsplit(' ', 1)[1]) > 100, public_drag
    touch('drag', 'touch.swiftui.drag', end=point('touch.swiftui.drag', 0.8), duration=0.4, hold=0.6, start_fraction=(0.2, 0.5))
    result = node('touch.swiftui.drag.status')['text']
    assert result.startswith('Drag completed ') and int(result.rsplit(' ', 1)[1]) > 100, result
    assert result != public_drag, ('Internal SwiftUI held drag did not change state', result)
    before = node('touch.swiftui.scroll')['uikit']['scrollView']['contentOffset']['y']
    act('drag', ['--from', point('touch.swiftui.scroll', 0.5, 0.8), '--to', point('touch.swiftui.scroll', 0.5, 0.2), '--duration', '0.4'], 'cli-swiftui-scroll-drag')
    time.sleep(0.3)
    after = node('touch.swiftui.scroll')['uikit']['scrollView']['contentOffset']['y']
    assert after > before + 20, ('SwiftUI drag', before, after)
    act('swipe', ['--from', point('touch.swiftui.scroll', 0.5, 0.2), '--to', point('touch.swiftui.scroll', 0.5, 0.8), '--duration', '0.4', '--no-verify-scroll'], 'cli-swiftui-scroll-swipe')
    time.sleep(0.3)
    restored = node('touch.swiftui.scroll')['uikit']['scrollView']['contentOffset']['y']
    assert after > restored + 20, ('SwiftUI swipe', after, restored)
    act('input', ['--test-id', 'touch.swiftui.input', '--text', literal], 'cli-swiftui-text-input')
    expect('touch.swiftui.input', literal)
    expect('touch.swiftui.input.status', 'Input changed: ' + literal)
    act('tap', ['--test-id', 'touch.swiftui.button'], 'cli-swiftui-dismiss-keyboard')
    expect('touch.swiftui.status', 'SwiftUI taps 3')
    verify_discovery_and_repeated_taps('swiftui')
    verify_button_routes('swiftui', 3)

if '--swiftui-only' not in sys.argv:
    verify_uikit()
verify_swiftui()
print('Separate UIKit and SwiftUI screens: buttons, gestures, input, aliases, coordinates, and saved refs passed', flush=True)
subprocess.run([cli, 'ui', 'report', '--host', host, '--output', str(out / 'report')], check=True, capture_output=True, timeout=30)
print(f'touch E2E passed; evidence: {out}')
