#!/usr/bin/env python3
"""Enable a Korean input mode in an English simulator and restore touched keys."""
import json
import pathlib
import plistlib
import subprocess
import sys

device, mode, backup = sys.argv[1:]
command = ['xcrun', 'simctl', 'spawn', device, 'defaults']
backup = pathlib.Path(backup)
keys = ['AppleKeyboards', 'AppleLanguages', 'AppleKeyboardsExpanded']
preferences = plistlib.loads(subprocess.check_output(command + ['export', 'NSGlobalDomain', '-'], timeout=30))
current = {key: preferences.get(key) for key in keys}
if mode == 'prepare':
    backup.write_text(json.dumps(current))
    target = dict(current)
    keyboards = list(target['AppleKeyboards'] or ['en_US@sw=QWERTY;hw=Automatic'])
    if not any(keyboard.startswith('ko_') for keyboard in keyboards):
        keyboards.append('ko_KR@sw=Korean;hw=Automatic')
    languages = list(target['AppleLanguages'] or ['en-US'])
    if not any(language.startswith('ko') for language in languages):
        languages.append('ko-KR')
    target.update(AppleKeyboards=keyboards, AppleLanguages=languages, AppleKeyboardsExpanded=1)
elif mode == 'restore':
    target = json.loads(backup.read_text())
else:
    raise ValueError(mode)

changed = False
for key in keys:
    value = target[key]
    if value == current[key]:
        continue
    changed = True
    if value is None:
        subprocess.run(command + ['delete', 'NSGlobalDomain', key], check=True, timeout=30)
    elif isinstance(value, list):
        subprocess.run(command + ['write', 'NSGlobalDomain', key, '-array'] + value, check=True, timeout=30)
    else:
        subprocess.run(command + ['write', 'NSGlobalDomain', key, '-int', str(value)], check=True, timeout=30)
if changed:
    subprocess.run(['xcrun', 'simctl', 'shutdown', device], check=True, timeout=30)
    subprocess.run(['xcrun', 'simctl', 'boot', device], check=True, timeout=30)
    subprocess.run(['xcrun', 'simctl', 'bootstatus', device, '-b'], check=True, timeout=180)
# Preserve narrow setup diagnostics in CI artifacts, including restore results.
actual = plistlib.loads(subprocess.check_output(command + ['export', 'NSGlobalDomain', '-'], timeout=30))
backup.with_name(backup.name + '-' + mode + '.json').write_text(json.dumps({
    'device': device, 'before': current, 'requested': target,
    'actual': {key: actual.get(key) for key in keys},
}, indent=2))
if mode == 'prepare':
    assert any(k.startswith('ko_') for k in actual.get('AppleKeyboards', [])), 'Korean keyboard preference was not applied'
    assert any(k.startswith('ko') for k in actual.get('AppleLanguages', [])), 'Korean language preference was not applied'
    # Booted state and readable preferences do not prove that the UI services
    # can render after a restart. Require a real frame before launching the
    # gesture fixture, and retain it for startup diagnostics.
    subprocess.run([
        'xcrun', 'simctl', 'io', device, 'screenshot',
        str(backup.with_name(backup.name + '-prepared-screen.png')),
    ], check=True, timeout=30)
