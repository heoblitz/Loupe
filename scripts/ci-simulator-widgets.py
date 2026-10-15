#!/usr/bin/env python3
"""Limit background widget work on disposable hosted Simulator test machines."""
import argparse
import json
import os
import pathlib
import plistlib
import re
import subprocess
import uuid

STORE_ROOT = pathlib.Path('/private/var/tmp')
EVIDENCE = pathlib.Path('/tmp/loupe-touch-widget-profile.json')
LABELS = ('com.apple.PosterBoard', 'com.apple.chronod',
          'com.apple.liveactivitiesd', 'com.apple.navd')
# Per-device override format and widget labels: SimSlim, reviewed at
# https://github.com/MobAI-App/simslim/tree/6518ba7eab1123d7e1d7797b0e05f51043b42a5b


def hosted_device(device):
    if (os.environ.get('GITHUB_ACTIONS'), os.environ.get('RUNNER_ENVIRONMENT')) != ('true', 'github-hosted'):
        raise RuntimeError('Widget configuration is limited to disposable GitHub-hosted VMs')
    return str(uuid.UUID(device)).upper()


def prepare(device):
    device = hosted_device(device)
    inventory = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', '--json'], timeout=30))
    selected = [d for devices in inventory['devices'].values() for d in devices if d['udid'] == device]
    if len(selected) != 1 or selected[0]['state'] != 'Shutdown':
        raise RuntimeError('The exact selected Simulator must be shut down before widget configuration')
    path = STORE_ROOT / ('com.apple.CoreSimulator.SimDevice.' + device) / 'disabled.plist'
    entries = plistlib.loads(path.read_bytes()) if path.exists() else {}
    if not isinstance(entries, dict) or not all(isinstance(v, bool) for v in entries.values()):
        raise RuntimeError('Unexpected Simulator disable-store format')
    before = dict(entries)
    entries.update(dict.fromkeys(LABELS, True))
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_suffix('.loupe-widgets.tmp')
    temporary.write_bytes(plistlib.dumps(entries))
    temporary.chmod(0o644)
    temporary.replace(path)
    EVIDENCE.write_text(json.dumps({'device': device, 'before': before, 'after': entries}, indent=2))
    print('Configured four background widget services on hosted Simulator', device, flush=True)


def verify(device):
    device = hosted_device(device)
    output = subprocess.check_output(
        ['xcrun', 'simctl', 'spawn', device, 'launchctl', 'print-disabled', 'system'],
        text=True, timeout=10)
    EVIDENCE.with_name('loupe-touch-widget-disabled.log').write_text(output)
    for label in LABELS:
        if not re.search(r'"' + re.escape(label) + r'"\s*=>\s*(?:true|disabled)\b', output):
            raise RuntimeError('Hosted Simulator widget override missing: ' + label)
    print('Verified four hosted Simulator widget overrides', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('device')
    parser.add_argument('phase', choices=('prepare', 'verify'))
    arguments = parser.parse_args()
    (prepare if arguments.phase == 'prepare' else verify)(arguments.device)
