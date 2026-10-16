#!/usr/bin/env python3
"""PoC only: compare real idb/native input, with Loupe as the common observer."""
import argparse
import json
import os
import pathlib
import subprocess
import time

p = argparse.ArgumentParser()
p.add_argument('--host', required=True)
p.add_argument('--udid', required=True)
p.add_argument('--backend', choices=['native', 'idb'], required=True)
p.add_argument('--route', choices=['touch', 'touch.swiftui'], required=True)
p.add_argument('--output', required=True)
a = p.parse_args()
out = pathlib.Path(a.output)
out.mkdir(parents=True, exist_ok=True)
cli = os.environ['LOUPE_TOUCH_CLI']
idb = [os.environ['IDB_CLI'], '--companion', os.environ['IDB_ADDRESS']]
results = []
commands = []


def run(args, label, timeout=15):
    started = time.monotonic()
    record = {'label': label, 'argv': args}
    try:
        r = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
        record.update(returncode=r.returncode, stdout=r.stdout, stderr=r.stderr)
        if r.returncode:
            raise RuntimeError((r.stdout + r.stderr)[-1600:])
        return r.stdout
    except subprocess.TimeoutExpired as e:
        record['error'] = str(e)
        raise
    finally:
        record['seconds'] = round(time.monotonic() - started, 3)
        commands.append(record)
        (out / 'commands.json').write_text(json.dumps(commands, indent=2))


def snapshot():
    path = out / 'snapshot.json'
    run([cli, 'ui', 'snapshot', '--host', a.host, '--output', str(path)], 'observe')
    return json.loads(path.read_text())


def node(test_id):
    matches = [n for n in snapshot()['nodes'].values() if n.get('testID') == test_id]
    assert len(matches) == 1, (test_id, len(matches))
    return matches[0]


def point(test_id, x=.5, y=.5):
    f = node(test_id)['frame']
    return [round(f['x'] + x * f['width']), round(f['y'] + y * f['height'])]


def expect(test_id, expected):
    deadline = time.monotonic() + 4
    while True:
        actual = node(test_id).get('text', '')
        if actual == expected:
            return actual
        if time.monotonic() >= deadline:
            raise AssertionError({'id': test_id, 'expected': expected, 'actual': actual})
        time.sleep(.05)


def tap(test_id, duration=None):
    x, y = map(str, point(test_id))
    if a.backend == 'idb':
        args = idb + ['ui', 'tap', x, y, '--api', 'hid']
    else:
        args = [cli, 'act', 'tap', '--x', x, '--y', y, '--host', a.host, '--udid', a.udid]
    if duration is not None:
        args += ['--duration', str(duration)]
    run(args, 'tap:' + test_id)


def swipe(test_id, start, end, hold=0):
    coords = [*point(test_id, *start), *point(test_id, *end)]
    if a.backend == 'idb':
        args = idb + ['ui', 'drag-and-drop' if hold else 'swipe'] + list(map(str, coords))
        if hold:
            args += ['--press-duration', str(hold), '--release-duration', '0']
        args += ['--duration', '.4']
    else:
        args = [cli, 'act', 'drag', '--from', f'{coords[0]},{coords[1]}',
                '--to', f'{coords[2]},{coords[3]}', '--duration', '.4',
                '--host', a.host, '--udid', a.udid]
        if hold:
            args += ['--hold-duration', str(hold)]
    run(args, 'swipe:' + test_id)


def case(name, body):
    started = time.monotonic()
    record = {'name': name}
    try:
        record['evidence'] = body()
        record['passed'] = True
    except Exception as e:
        record.update(passed=False, error=str(e))
    record['seconds'] = round(time.monotonic() - started, 3)
    results.append(record)
    print(f"{a.backend}/{a.route}: {name}: {'PASS' if record['passed'] else 'FAIL'}", flush=True)
    (out / 'results.json').write_text(json.dumps({
        'backend': a.backend, 'route': a.route, 'udid': a.udid,
        'idb_version': '1.7.3', 'tests': results,
    }, indent=2))


kind = 'swiftui' if a.route == 'touch.swiftui' else 'uikit'
prefix = 'touch.swiftui' if kind == 'swiftui' else 'touch'
button = 'touch.' + kind + '.button'


def press_and_check(target, status, expected, duration=None):
    tap(target, duration)
    return expect(status, expected)


def scroll(reverse=False):
    target = prefix + '.scroll'
    n = node(target)
    before = n['uikit']['scrollView']['contentOffset']['y']
    start, end = ((.5, .2), (.5, .8)) if reverse else ((.5, .8), (.5, .2))
    swipe(target, start, end)
    minimum = 20 if kind == 'swiftui' else n['frame']['height'] * .3
    deadline = time.monotonic() + 4
    while True:
        after = node(target)['uikit']['scrollView']['contentOffset']['y']
        if (before - after if reverse else after - before) > minimum:
            return {'before': before, 'after': after, 'minimum': minimum}
        if time.monotonic() >= deadline:
            raise AssertionError((before, after, minimum))
        time.sleep(.05)


def held_drag():
    swipe(prefix + '.drag', (.2, .5), (.75, .5), hold=.6)
    actual = node(prefix + '.drag.status')['text']
    assert actual.startswith('Drag completed ') and int(actual.rsplit(' ', 1)[1]) > 100, actual
    return actual


def text(value):
    # Focus once before both insertions. Retapping a nonempty field would move
    # its insertion point and invalidate the common append assertion.
    before = node(prefix + '.input').get('text', '') or ''
    if a.backend == 'idb':
        run(idb + ['ui', 'text', value], 'text')
    else:
        run([cli, 'act', 'input', '--test-id', prefix + '.input', '--text', value,
             '--host', a.host, '--udid', a.udid], 'text')
    expect(prefix + '.input', before + value)
    return expect(prefix + '.input.status', 'Input changed: ' + before + value)


def ax_set_value():
    # A distinct capability probe, never an automatic fallback for HID text.
    value = 'Hello Loupe 123! 한글 👋🏼'
    run(idb + ['ui', 'set-value', prefix + '.input', '--match-key', 'AXUniqueId',
               '--value', value, '--api', 'axbridge'], 'ax-set-value')
    expect(prefix + '.input', value)
    return expect(prefix + '.input.status', 'Input changed: ' + value)


case('button', lambda: press_and_check(button, 'touch.' + kind + '.status',
                                      ('SwiftUI' if kind == 'swiftui' else 'UIKit') + ' taps 1'))
case('gesture-tap', lambda: press_and_check(prefix + '.tap', prefix + '.tap.status', 'Taps 1'))
case('long-press', lambda: press_and_check(prefix + '.hold', prefix + '.hold.status', 'Holds 1', .6))
case('scroll-forward', scroll)
case('scroll-back', lambda: scroll(True))
case('held-drag', held_drag)
if kind == 'uikit':
    case('korean-keyboard-focus', lambda: press_and_check('touch.input', 'touch.input.status', 'Input mode: ko-KR'))
else:
    case('input-focus', lambda: tap(prefix + '.input'))
case('ascii-input', lambda: text('Hello Loupe 123!'))
case('unicode-input', lambda: text('Hello Loupe 123! 한글 👋🏼'))
if a.backend == 'idb':
    case('ax-unicode-set-value-and-change-event', ax_set_value)
    case('ax-tree', lambda: (out / 'idb-ax.json').write_text(
        run(idb + ['ui', 'describe-all', '--json'], 'ax-tree')))
    case('screenshot', lambda: run(idb + ['screenshot', str(out / 'idb.png')], 'screenshot', 10))
raise SystemExit(any(not r['passed'] for r in results))
