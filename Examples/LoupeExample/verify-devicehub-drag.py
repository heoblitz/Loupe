#!/usr/bin/env python3
"""Verify a real host-side drag changes the fixture's scroll offset."""
import json
import pathlib
import subprocess
import sys
import time

def has_minimum_scroll(before, after, height):
    # Exactly 30% is sufficient, but an unchanged offset never counts.
    return after > before and after - before >= height * 0.3


def main():
    host, device = sys.argv[1:]
    cli = str(pathlib.Path('.build/debug/loupe').resolve())
    path = '/tmp/loupe-devicehub-drag-snapshot.json'


    def scroll_node():
        subprocess.run([cli, 'ui', 'snapshot', '--host', host, '--output', path], check=True, stdout=subprocess.DEVNULL)
        with open(path) as source:
            snapshot = json.load(source)
        return next(n for n in snapshot['nodes'].values() if n.get('testID') == 'touch.scroll')


    before = scroll_node()
    frame = before['frame']
    x = frame['x'] + frame['width'] * 0.5
    start = frame['y'] + frame['height'] * 0.8
    end = frame['y'] + frame['height'] * 0.2
    initial = before['uikit']['scrollView']['contentOffset']['y']
    subprocess.run([cli, 'act', 'drag', '--host', host, '--udid', device,
                    '--from', f'{x},{start}', '--to', f'{x},{end}', '--duration', '0.4'], check=True)
    deadline = time.monotonic() + 4
    while True:
        after = scroll_node()['uikit']['scrollView']['contentOffset']['y']
        if has_minimum_scroll(initial, after, frame['height']):
            print('Device Hub drag changed the scroll offset')
            break
        if time.monotonic() >= deadline:
            raise AssertionError(f'drag did not scroll: before={initial}, after={after}')
        time.sleep(0.1)


if __name__ == '__main__':
    main()
