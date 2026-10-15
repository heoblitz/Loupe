#!/usr/bin/env python3
"""Verify CLI and internal touch results in the same simulator or linked device fixture."""
import concurrent.futures, json, os, pathlib, re, signal, subprocess, sys, threading, time, urllib.request, urllib.error
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
    trace_arguments = [] if command == 'input' or os.environ.get('LOUPE_PROBE_NO_TRACE') == '1' else ['--trace-dir', str(trace_path)]
    arguments = [cli, 'act', command] + args + ['--host', host] + selection + trace_arguments
    # Account for both existing 10s screenshot phases separately from the
    # original 15s input budget. CLI request/capture deadlines stay unchanged;
    # diagnostic capture errors are recorded; app-state checks remain mandatory.
    command_budget = 15 + (2 * 10 if trace_arguments else 0)
    started = time.time()
    process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        stdout, stderr = process.communicate(timeout=command_budget)
        result = subprocess.CompletedProcess(arguments, process.returncode, stdout, stderr)
    except subprocess.TimeoutExpired as error:
        def decoded(value): return value.decode(errors='replace') if isinstance(value, bytes) else (value or '')
        (out / (trace + '.log')).write_text(f'started={started} pid={process.pid} failed_at={time.time()} poll={process.poll()}\n' + decoded(error.stdout) + decoded(error.stderr))
        try:
            if process.poll() is None:
                process.send_signal(signal.SIGSTOP)
                with (out / (trace + '-sample.log')).open('w') as stream:
                    try: subprocess.run(['/usr/bin/sudo', '/usr/bin/sample', str(process.pid), '1', '10', '-file', str(out / (trace + '-host-stack.txt'))], stdout=stream, stderr=stream, timeout=55)
                    except Exception as capture_error: stream.write(repr(capture_error))
            with (out / (trace + '-processes.txt')).open('w') as stream:
                subprocess.run(['/bin/ps', '-axo', 'pid,ppid,pcpu,rss,command'], stdout=stream, stderr=stream, timeout=10)
            with (out / (trace + '-vm.txt')).open('w') as stream:
                subprocess.run(['/usr/bin/vm_stat'], stdout=stream, stderr=stream, timeout=10)
        finally:
            if process.poll() is None:
                process.send_signal(signal.SIGCONT)
                process.kill()
            try: process.wait(timeout=5)
            except subprocess.TimeoutExpired: pass
            process.stdout.close(); process.stderr.close()
        raise RuntimeError(f'Action and requested trace failed at original {command_budget}s deadline; captured CLI stack: {trace}') from error
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
    if command == 'tap' and trace_arguments:
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


x, y = point('touch.uikit.double').split(',')
expected = 0
results = []
for index in range(100):
    modes = ['trace', 'no-trace'] if index % 2 == 0 else ['no-trace', 'trace']
    for mode in modes:
        os.environ['LOUPE_PROBE_NO_TRACE'] = '1' if mode == 'no-trace' else '0'
        name = f'{index:03d}-{mode}'
        started = time.monotonic()
        act('tap', ['--x', x, '--y', y, '--count', '2'], name)
        expected += 1
        expect('touch.uikit.double.status', f'Double taps {expected}')
        results.append({'name': name, 'elapsed': time.monotonic() - started, 'expected': expected})
        (out / 'results.json').write_text(json.dumps(results, indent=2))
        if index % 10 == 0: print(results[-1], flush=True)
print('All traced and untraced double taps changed application state', len(results), flush=True)
