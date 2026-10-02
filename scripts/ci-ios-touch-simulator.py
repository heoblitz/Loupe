#!/usr/bin/env python3
"""Own one CI simulator; configure input before its first boot, then delete it."""
import json
import os
import pathlib
import plistlib
import subprocess
import sys
import time
import uuid
from ci_simulator_readiness import build_observer, wait_for_boot

mode, manifest_path = sys.argv[1:]
manifest = pathlib.Path(manifest_path)

def simctl(*args, timeout=60, capture=False):
    print('simctl ' + ' '.join(args), flush=True)
    # Retain startup diagnostics even when the first inventory query fails,
    # before ownership can be recorded. JSON stdout stays separate from stderr.
    log = manifest.with_suffix('.' + args[0] + '.log')
    diagnostics = manifest.with_suffix('.' + args[0] + '.stderr.log')
    try:
        with log.open('w') as output, diagnostics.open('w') as errors:
            result = subprocess.run(['xcrun', 'simctl', *args], check=True,
                                    stdout=output, stderr=errors if capture else subprocess.STDOUT,
                                    timeout=timeout)
        if capture:
            result.stdout = log.read_text()
        return result
    except (subprocess.SubprocessError, OSError):
        for path in [log, diagnostics]:
            if path.exists():
                print('\n'.join(path.read_text(errors='replace').splitlines()[-10:]), flush=True)
        if os.environ.get('GITHUB_ACTIONS') == 'true':
            try:
                with manifest.with_suffix('.failure-processes.log').open('w') as output:
                    subprocess.run(['/bin/ps', '-r', '-axo', 'pid,ppid,pcpu,pmem,state,comm'],
                                   stdout=output, stderr=subprocess.STDOUT, timeout=10)
            except (subprocess.SubprocessError, OSError):
                pass
            try:
                pid = subprocess.check_output(['/usr/bin/pgrep', '-x', 'simdiskimaged'],
                                              text=True, timeout=5).splitlines()[0]
                assert pid.isdigit()
                sample = manifest.with_suffix('.' + args[0] + '.disk-image-sample.log')
                subprocess.run(['sudo', '-n', '/usr/bin/sample', pid, '1', '1',
                                '-file', str(sample)], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=10)
            except (subprocess.SubprocessError, OSError, IndexError):
                pass
        raise

def inventory(kind, search):
    return json.loads(simctl('list', kind, search, '--json', capture=True).stdout)

def device_record(device):
    identifier = str(uuid.UUID(device)).upper()
    path = pathlib.Path.home() / 'Library/Developer/CoreSimulator/Devices' / identifier / 'device.plist'
    if not path.exists():
        return None
    value = plistlib.loads(path.read_bytes())
    assert value['UDID'] == identifier, 'Owned fixture UUID does not match its metadata'
    return value

def hosted_fixture(device_type, requested_version):
    # The runner image already contains shutdown fixtures. Read their small
    # metadata records without starting CoreSimulator's all-runtime disk scan.
    # The first service request can then boot one exact UUID, rather than wait
    # for an inventory of unrelated runtime images before boot even begins.
    root = pathlib.Path.home() / 'Library/Developer/CoreSimulator/Devices'
    candidates = []
    for path in sorted(root.glob('*/device.plist')):
        value = plistlib.loads(path.read_bytes())
        runtime = value.get('runtime', '')
        if (value.get('deviceType') != device_type or value.get('state') != 1
                or not runtime.startswith('com.apple.CoreSimulator.SimRuntime.iOS-')):
            continue
        version = runtime.rsplit('iOS-', 1)[1].replace('-', '.')
        if requested_version and version != requested_version:
            continue
        device = str(uuid.UUID(value['UDID'])).upper()
        assert path.parent.name == device, 'CI fixture UUID does not match its directory'
        candidates.append((tuple(map(int, version.split('.'))), {
            'udid': device, 'name': value['name'], 'runtime': runtime,
            'dataPath': str(path.parent / 'data'),
        }))
    assert candidates, 'No shutdown CI fixture for the requested iOS runtime'
    return max(candidates, key=lambda candidate: candidate[0])[1]

def collect_boot_failure(device):
    if os.environ.get('GITHUB_ACTIONS') != 'true':
        return
    # Capture the host load and guest service state after the original boot
    # deadline has failed. These bounded diagnostics never change readiness.
    for name, command in [
        ('failure-processes', ['/bin/ps', '-r', '-axo', 'pid,ppid,pcpu,pmem,state,comm']),
        ('failure-memory', ['/usr/bin/vm_stat']),
        ('failure-guest-services', ['xcrun', 'simctl', 'spawn', device, 'launchctl', 'list']),
    ]:
        path = manifest.with_suffix('.' + name + '.log')
        try:
            with path.open('w') as output:
                subprocess.run(command, stdout=output, stderr=subprocess.STDOUT, timeout=5)
        except (subprocess.SubprocessError, OSError) as error:
            with path.open('a') as output:
                output.write('\nDiagnostic unavailable: ' + str(error) + '\n')

if mode == 'create':
    assert not manifest.exists(), 'An owned simulator manifest already exists'
    # Compile on the idle host before any simulator service request. Guest
    # first-boot migration must not compete with the observation helper build.
    observer = build_observer(manifest)
    requested_version = os.environ.get('LOUPE_TOUCH_RUNTIME_VERSION')
    architecture = os.environ.get('LOUPE_TOUCH_ARCHITECTURE')
    if architecture:
        assert architecture in ('arm64', 'x86_64')
    device_type = os.environ.get('LOUPE_TOUCH_DEVICE_TYPE',
                                'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro')
    name = 'Loupe CI Touch ' + str(uuid.uuid4())
    hosted = os.environ.get('GITHUB_ACTIONS') == 'true'
    if hosted:
        state = hosted_fixture(device_type, requested_version)
        device, runtime_id = state['udid'], state['runtime']
        owned = {'device': device, 'name': state['name'], 'runtime': runtime_id,
                 'ownership_name': name, 'hosted': True}
    else:
        # Local runs own only a newly created fixture, never a user's simulator.
        available = inventory('runtimes', 'iOS')
        runtimes = [r for r in available['runtimes'] if r.get('isAvailable')
                    and r['identifier'].startswith('com.apple.CoreSimulator.SimRuntime.iOS-')]
        if requested_version:
            runtimes = [r for r in runtimes if r['version'] == requested_version]
            assert runtimes, 'Requested iOS runtime is unavailable: ' + requested_version
        runtime = max(runtimes, key=lambda r: tuple(map(int, r['version'].split('.'))))
        if architecture and runtime.get('supportedArchitectures'):
            assert architecture in runtime['supportedArchitectures'], 'Runtime does not support ' + architecture
        runtime_id = runtime['identifier']
        device = simctl('create', name, device_type, runtime_id, capture=True).stdout.strip()
        state = next(d for group in inventory('devices', device)['devices'].values() for d in group if d['udid'] == device)
        assert state['state'] == 'Shutdown'
        owned = {'device': device, 'name': name, 'runtime': runtime_id}
    # Save ownership immediately, so failure during setup can still be cleaned.
    manifest.write_text(json.dumps(owned))
    preferences = pathlib.Path(state['dataPath']) / 'Library/Preferences/.GlobalPreferences.plist'
    values = plistlib.loads(preferences.read_bytes()) if preferences.exists() else {}
    values.update(AppleKeyboards=['en_US@sw=QWERTY;hw=Automatic', 'ko_KR@sw=Korean;hw=Automatic'],
                  AppleLanguages=['en-US', 'ko-KR'], AppleKeyboardsExpanded=1)
    preferences.parent.mkdir(parents=True, exist_ok=True)
    preferences.write_bytes(plistlib.dumps(values))
    if hosted:
        # Apple documents first-boot failures while dyld caches are generated.
        # Image builders prepare caches with their latest stable Xcode; ensure
        # the selected runtime is ready under this job's pinned Xcode too.
        # Never force/recreate an existing cache or update unrelated runtimes.
        cache_started = time.monotonic()
        simctl('runtime', 'dyld_shared_cache', 'update', runtime_id, timeout=60)
        print('selected runtime dyld cache preparation seconds=' +
              format(time.monotonic() - cache_started, '.3f'), flush=True)
    # Native HID talks directly to SimDevice. Keep CI headless, as the existing
    # native scenarios do; opening Simulator adds a GUI display startup to boot.
    # Only one command initiates boot, avoiding bootstatus -b's second boot race.
    boot_options = ['--arch=' + architecture] if architecture else []
    try:
        simctl('boot', device, *boot_options, timeout=180)
        wait_for_boot(device, manifest, observer, timeout=180)
    except (subprocess.SubprocessError, OSError, AssertionError, RuntimeError):
        collect_boot_failure(device)
        raise
    if hosted:
        # Validate the service's authoritative identity after the single boot.
        # Keep the image's original name: renaming a booted device can block on
        # its startup services and is unnecessary for UUID-based ownership.
        state = device_record(device)
        assert state is not None and state['name'] == owned['name'] and state['state'] == 3
        assert state['deviceType'] == device_type and state['runtime'] == runtime_id
    print('owned touch simulator: ' + device, flush=True)
elif mode == 'delete':
    if manifest.exists():
        owned = json.loads(manifest.read_text())
        state = device_record(owned['device'])
        if state is not None:
            if owned.get('hosted'):
                assert os.environ.get('GITHUB_ACTIONS') == 'true'
                assert owned['ownership_name'].startswith('Loupe CI Touch ')
            else:
                assert owned['name'].startswith('Loupe CI Touch ')
            assert state['name'] == owned['name'] and state['runtime'] == owned['runtime']
            if state['state'] != 1:
                simctl('shutdown', owned['device'], timeout=30)
            simctl('delete', owned['device'], timeout=30)
        manifest.unlink()
else:
    raise ValueError(mode)
