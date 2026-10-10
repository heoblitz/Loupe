#!/usr/bin/env python3
"""Prepare keyboard preferences while the selected simulator is shut down."""
import json
import pathlib
import plistlib
import subprocess
import sys

device, mode, backup = sys.argv[1:]
assert mode in ('prepare', 'restore'), mode
backup = pathlib.Path(backup)
inventory = json.loads(subprocess.check_output(
    ['xcrun', 'simctl', 'list', 'devices', '--json'], timeout=30))
selected = next(d for group in inventory['devices'].values() for d in group if d['udid'] == device)
assert selected['state'] in ('Booted', 'Shutdown'), selected['state']
if selected['state'] == 'Booted':
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True, timeout=30)
# Like Fastlane's simulator localization, prepare the plist before boot so
# guest preferences services cannot race the write or block setup.
path = pathlib.Path(selected['dataPath']) / 'Library/Preferences/.GlobalPreferences.plist'
preferences = plistlib.loads(path.read_bytes()) if path.exists() else {}
keys = ['AppleLocale', 'AppleKeyboards', 'AppleLanguages', 'AppleKeyboardsExpanded']
current = {key: preferences.get(key) for key in keys}
if mode == 'prepare':
    backup.write_text(json.dumps({'state': selected['state'], 'preferences': current}))
    # Use the same English-default input environment on every host; restore
    # these keys afterward instead of inheriting local language/keyboard order.
    target = {
        'AppleLocale': 'en_US', 'AppleLanguages': ['en-US', 'ko-KR'],
        'AppleKeyboards': ['en_US@sw=QWERTY;hw=Automatic', 'ko_KR@sw=Korean;hw=Automatic'],
        'AppleKeyboardsExpanded': 1,
    }
else:
    saved = json.loads(backup.read_text())
    target = saved['preferences']
for key, value in target.items():
    if value is None:
        preferences.pop(key, None)
    else:
        preferences[key] = value
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(plistlib.dumps(preferences, fmt=plistlib.FMT_BINARY))
actual = plistlib.loads(path.read_bytes())
assert {key: actual.get(key) for key in keys} == target
backup.with_name(backup.name + '-' + mode + '.json').write_text(json.dumps({
    'device': device, 'before': current, 'requested': target,
    'actual': {key: actual.get(key) for key in keys},
}, indent=2))
if mode == 'restore' and saved['state'] == 'Booted':
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=180)
