#!/usr/bin/env python3
"""Launch, discover, touch, enter Unicode and verify with idb only; no Loupe SDK."""
import json
import os
import pathlib
import subprocess
import time

out = pathlib.Path(os.environ.get('IDB_EVIDENCE', '/tmp/loupe-idb-evidence')) / 'standalone'
out.mkdir(parents=True, exist_ok=True)
idb = [os.environ['IDB_CLI'], '--companion', os.environ['IDB_ADDRESS']]
commands = []
results = []


def run(args, env=None, timeout=15, check=True):
    record = {'argv': args}
    started = time.monotonic()
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=env)
        record.update(stdout=r.stdout, stderr=r.stderr, returncode=r.returncode)
        if r.returncode and check:
            raise RuntimeError((r.stdout + r.stderr)[-1600:])
        return r.stdout
    finally:
        record['seconds'] = round(time.monotonic() - started, 3)
        commands.append(record)
        (out / 'commands.json').write_text(json.dumps(commands, indent=2))


def tree():
    value = run(idb + ['ui', 'describe-all', '--api', 'axbridge', '--json'])
    (out / 'ax-tree.json').write_text(value)
    return json.loads(value)


def element(test_id):
    matches = [n for n in tree() if n.get('AXUniqueId') == test_id]
    assert len(matches) == 1, (test_id, len(matches))
    return matches[0]


def expect(test_id, value):
    deadline = time.monotonic() + 4
    while True:
        n = element(test_id)
        if value in (n.get('AXLabel'), n.get('AXValue')):
            return
        assert time.monotonic() < deadline, (test_id, value, n)
        time.sleep(.05)


def tap(test_id, duration=None):
    f = element(test_id)['frame']
    args = idb + ['ui', 'tap', str(round(f['x'] + f['width'] / 2)),
                  str(round(f['y'] + f['height'] / 2)), '--api', 'hid']
    if duration:
        args += ['--duration', str(duration)]
    run(args)


for route, kind in [('touch', 'uikit'), ('touch.swiftui', 'swiftui')]:
    record = {'route': route, 'passed': False, 'completed': []}
    try:
        run(idb + ['terminate', 'dev.loupe.example'], check=False)
        # idb forwards IDB_ prefixed environment variables without the prefix.
        env = {k: v for k, v in os.environ.items() if not k.startswith('IDB_')}
        env['IDB_LOUPE_EXAMPLE_ROUTE'] = route
        launch_deadline = time.monotonic() + 30
        run(idb + ['launch', 'dev.loupe.example'], env=env, timeout=30)
        # idb launch acknowledges process creation before the scene is ready.
        # Use idb's read-only readiness wait within the original launch budget.
        remaining = max(.1, launch_deadline - time.monotonic())
        run(idb + ['ui', 'wait', 'touch.' + kind + '.button', '--match-key', 'AXUniqueId',
                   '--api', 'axbridge', '--timeout', str(remaining)], timeout=remaining)
        prefix = 'touch.swiftui' if kind == 'swiftui' else 'touch'
        tap('touch.' + kind + '.button')
        expect('touch.' + kind + '.status', ('SwiftUI' if kind == 'swiftui' else 'UIKit') + ' taps 1')
        record['completed'].append('button HID + AX state')
        tap(prefix + '.tap')
        expect(prefix + '.tap.status', 'Taps 1')
        record['completed'].append('gesture HID + AX state')
        tap(prefix + '.hold', .6)
        expect(prefix + '.hold.status', 'Holds 1')
        record['completed'].append('long-press HID + AX state')
        tap(prefix + '.input')
        value = 'Hello Loupe 123! 한글 👋🏼'
        run(idb + ['ui', 'set-value', prefix + '.input', '--match-key', 'AXUniqueId',
                   '--value', value, '--api', 'axbridge'])
        expect(prefix + '.input', value)
        expect(prefix + '.input.status', 'Input changed: ' + value)
        record['completed'].append('Unicode AX value + change event')
        run(idb + ['screenshot', str(out / (route + '.png'))], timeout=10)
        record['completed'].append('screenshot')
        record['passed'] = True
    except Exception as e:
        record['error'] = str(e)
    results.append(record)
    (out / 'results.json').write_text(json.dumps(results, indent=2))
    print('standalone idb:', route, 'PASS' if record['passed'] else 'FAIL', flush=True)
raise SystemExit(any(not r['passed'] for r in results))
