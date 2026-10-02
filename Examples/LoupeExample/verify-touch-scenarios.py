#!/usr/bin/env python3
"""Verify CLI and internal touch results in the same simulator or linked device fixture."""
import concurrent.futures, json, os, pathlib, re, subprocess, sys, time, urllib.request, urllib.error
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
    started = time.time()
    def completed_state():
        phase = 'failure' if expect_rejection else 'after'
        record_path = trace_path / ('action-' + phase + '.json')
        if not trace_arguments or not record_path.exists() or not started <= record_path.stat().st_mtime <= started + 15:
            return False
        record = json.loads(record_path.read_text())
        if record.get('phase') != phase:
            return False
        if expect_rejection:
            error_path = trace_path / 'error.json'
            if not error_path.exists():
                return False
            message = json.loads(error_path.read_text()).get('message', '')
            return (record.get('command') == 'tap' and record.get('host') == host
                    and record.get('backend') == 'runtime' and record.get('selector') == 'testID:touch.tap'
                    and any(reason in message for reason in (
                        'accessibility_action_not_handled',
                        'No native accessibility action matched selector',
                        'Matched accessibility node does not expose a tap action')))
        return True
    with subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as process:
        try:
            stdout, stderr = process.communicate(timeout=15)
        except subprocess.TimeoutExpired:
            # State must finish within 15s: either verified dispatch/after-state
            # or the expected semantic rejection. Failure diagnostics, like
            # post-action diagnostics, have a separate bounded 15s completion.
            # A transport error or a late rejection cannot extend this deadline.
            if not completed_state():
                sample_failed_cli(process.pid, trace)
                process.kill()
                stdout, stderr = process.communicate()
                (out / (trace + '.log')).write_text(stdout + stderr)
                raise RuntimeError('Action/state phase exceeded 15s: ' + trace)
            try:
                stdout, stderr = process.communicate(timeout=15)
            except subprocess.TimeoutExpired:
                sample_failed_cli(process.pid, trace)
                process.kill()
                stdout, stderr = process.communicate()
                (out / (trace + '.log')).write_text(stdout + stderr)
                raise RuntimeError('Post-action diagnostics exceeded 15s: ' + trace)
    result = subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
    (out / (trace + '.log')).write_text(result.stdout + result.stderr)
    if expect_rejection:
        assert result.returncode != 0 and completed_state(), result.stdout + result.stderr
        assert not (trace_path / 'action-after.json').exists()
        assert 'loupe.hid.gesture' not in result.stderr, result.stderr
        return
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)
    if (expected_backend == 'auto' and command in ('tap', 'drag', 'swipe')
            and os.environ.get('LOUPE_HID_DIAGNOSTICS') == '1'):
        assert re.findall(r'^loupe.hid.gesture qos=(\d+)$', result.stderr, re.MULTILINE) == ['33'], result.stderr
        assert re.findall(r'^loupe.hid.prepare qos=(\d+)$', result.stderr, re.MULTILINE) == ['33'], result.stderr
    screenshot_error = trace_path / 'after.screenshot-error.json'
    if screenshot_error.exists():
        assert json.loads(screenshot_error.read_text())['message']
        assert 'warning: action completed; after screenshot unavailable:' in result.stderr
        assert not (trace_path / 'after.png').exists()
        assert not (trace_path / 'action-failure.json').exists()
    if command == 'tap':
        record = json.loads((trace_path / 'action-target.json').read_text())
        assert record['backend'] == expected_backend, record

def sample_failed_cli(pid, trace):
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return
    try:
        with (out / (trace + '-host-sample.log')).open('w') as diagnostics:
            subprocess.run(['/usr/bin/sample', str(pid), '1', '-file',
                            str(out / (trace + '-host-stack.txt'))],
                           stdout=diagnostics, stderr=subprocess.STDOUT, timeout=3)
    except (OSError, subprocess.SubprocessError):
        pass

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
