#!/usr/bin/env python3
"""Use generic host icons only for the known disposable Intel image crash."""
import json
import os
import pathlib
import platform
import re
import subprocess
import sys


def known_icon_crash(text):
    try:
        report = json.loads(text.split('\n', 1)[1])
        thread = report['threads'][report['faultingThread']]
        return (report['procName'] == 'iconservicesagent'
                and report['exception']['signal'] == 'SIGABRT'
                and thread.get('queue') == 'com.apple.RenderBox.Device'
                and any('MTLLoader sliceIDForDevice:' in frame.get('symbol', '')
                        for frame in thread['frames']))
    except (ValueError, KeyError, IndexError, TypeError):
        return False


def main():
    assert os.environ.get('GITHUB_ACTIONS') == 'true', 'Disposable GitHub runner only'
    assert platform.system() == 'Darwin' and platform.machine() == 'x86_64'
    version = subprocess.check_output(['sw_vers', '-productVersion'], text=True, timeout=5).strip()
    assert version.startswith('26.'), 'Workaround is scoped to the Intel macOS26 image'
    manifest = pathlib.Path(sys.argv[1])
    reports = list((pathlib.Path.home() / 'Library/Logs/DiagnosticReports').glob('iconservicesagent*.ips'))
    if not reports:
        print('No host icon crash report; no workaround applied', flush=True)
        return
    latest = max(reports, key=lambda path: path.stat().st_mtime_ns)
    with latest.open('rb') as source:
        raw = source.read(2 * 1024 * 1024)
    text = raw.decode('utf-8', errors='replace')
    if not known_icon_crash(text):
        print('Host icon report does not match the known Metal assertion; no workaround applied', flush=True)
        return
    manifest.with_suffix('.host-icon-crash.ips').write_bytes(raw)
    target = f'gui/{os.getuid()}/com.apple.iconservices.iconservicesagent'
    # actions/runner-images#14751: prevent a crashing host icon renderer from
    # leaving IconServices clients in endless retries. Guest rendering and HID
    # are untouched. The disposable runner owns this GUI service and setting.
    with manifest.with_suffix('.host-icon-service.log').open('w') as output:
        for args in [('print', target), ('disable', target), ('bootout', target)]:
            subprocess.run(['launchctl', *args], check=True, stdout=output,
                           stderr=subprocess.STDOUT, timeout=10)
        disabled = subprocess.check_output(['launchctl', 'print-disabled', f'gui/{os.getuid()}'],
                                           text=True, timeout=5)
        output.write(disabled)
        assert re.search(r'"com\.apple\.iconservices\.iconservicesagent"\s*=>\s*(?:true|disabled)\b', disabled)
    print('Known host Metal icon crash: generic host icons enabled on this disposable Intel runner', flush=True)


if __name__ == '__main__':
    main()
