"""Bound native boot observation by semantic completion, owning only our child."""
import json
import os
import pathlib
import subprocess
import sys
import time


if sys.platform == 'darwin':
    # Older Xcode Python versions subtract a process-local epoch from
    # time.monotonic(). Use the same public Mach clock as the native observer.
    import ctypes
    class _Timebase(ctypes.Structure):
        _fields_ = [('numer', ctypes.c_uint32), ('denom', ctypes.c_uint32)]
    _system = ctypes.CDLL(None)
    _system.mach_absolute_time.restype = ctypes.c_uint64
    _system.mach_absolute_time.argtypes = []
    _system.mach_timebase_info.argtypes = [ctypes.POINTER(_Timebase)]
    _system.mach_timebase_info.restype = ctypes.c_int
    _timebase = _Timebase()
    if _system.mach_timebase_info(ctypes.byref(_timebase)) != 0 or not _timebase.denom:
        raise OSError('Cannot read the shared Mach clock')
    def monotonic_ns():
        return _system.mach_absolute_time() * _timebase.numer // _timebase.denom
else:
    monotonic_ns = time.monotonic_ns


def reap(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=0.25)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=1)


def wait_for_record(command, device, receipt, log, timeout=180):
    receipt = pathlib.Path(receipt)
    assert not receipt.exists(), 'Boot observation must use a fresh receipt'
    started = monotonic_ns()
    deadline = started + int(timeout * 1_000_000_000)
    with pathlib.Path(log).open('w') as output:
        output.write(f'boot observation start_ns={started} deadline_ns={deadline}\n')
        output.flush()
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        pending = b''
        last_record = None
        try:
            os.set_blocking(process.stdout.fileno(), False)
            while True:
                code = process.poll()
                if code is not None and code != 0:
                    raise subprocess.CalledProcessError(code, command)
                # Drain before checking the parent deadline: a timely record
                # can already be in the pipe when a delayed parent wakes.
                ended = False
                while True:
                    try:
                        chunk = os.read(process.stdout.fileno(), 4096)
                    except BlockingIOError:
                        break
                    except InterruptedError:
                        continue
                    if not chunk:
                        ended = True
                        break
                    output.write(chunk.decode('utf-8', errors='replace'))
                    pending += chunk
                    if len(pending) > 16 * 1024:
                        raise RuntimeError('Oversized boot observer record')
                code = process.poll()
                if code is not None and code != 0:
                    raise subprocess.CalledProcessError(code, command)
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    try:
                        record = json.loads(line)
                    except (json.JSONDecodeError, UnicodeDecodeError):
                        continue
                    if not isinstance(record, dict) or 'udid' not in record:
                        continue
                    last_record = record
                    assert record['udid'] == device, 'Boot receipt belongs to a different simulator'
                    if record['status'] == 3:
                        raise RuntimeError('Simulator data migration failed')
                    if record.get('finished'):
                        assert record['state'] == 3 and record['status'] == 4294967295, 'Invalid boot completion'
                        observed = record.get('observedMonotonicNS')
                        assert type(observed) is int, 'Missing native boot observation timestamp'
                        assert observed >= started, 'Boot receipt predates this observation'
                        # A delayed parent must still read a timely native
                        # completion. A genuinely late completion stays a failure.
                        if observed <= deadline:
                            return record
                remaining = (deadline - monotonic_ns()) / 1_000_000_000
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, timeout)
                if code is not None or ended:
                    raise RuntimeError('Boot observer exited without successful boot completion')
                time.sleep(min(0.05, remaining))
        finally:
            reap(process)
            process.stdout.close()
            # Diagnostic persistence is outside completion detection. It must
            # never be the channel that publishes boot readiness to the parent.
            if last_record is not None:
                receipt.write_text(json.dumps(last_record))


def build_observer(manifest):
    root = pathlib.Path(__file__).resolve().parent.parent
    manifest = pathlib.Path(manifest)
    executable = manifest.with_suffix('.boot-observer')
    sources = root / 'Sources/LoupeHID'
    log = manifest.with_suffix('.observer-build.log')
    started = time.monotonic()
    print('build native boot observer before starting CoreSimulator', flush=True)
    try:
        with log.open('w') as output:
            subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-fblocks', '-I', str(sources / 'include'),
                            '-framework', 'Foundation', '-framework', 'AppKit',
                            '-framework', 'CoreImage', '-framework', 'IOSurface', '-framework', 'ImageIO',
                            str(sources / 'LoupeHID.m'), str(sources / 'LoupeSimulatorObservation.m'),
                            str(root / 'scripts/ci-simulator-boot-status.m'), '-o', str(executable)],
                           stdout=output, stderr=subprocess.STDOUT, check=True, timeout=60)
    except (subprocess.SubprocessError, OSError):
        if log.exists():
            print('\n'.join(log.read_text(errors='replace').splitlines()[-10:]), flush=True)
        raise
    print(f'boot observer built in {time.monotonic() - started:.3f}s', flush=True)
    return executable


def wait_for_boot(device, manifest, executable, timeout=180):
    manifest = pathlib.Path(manifest)
    assert pathlib.Path(executable).is_file(), 'Build boot observer before initiating boot'
    receipt = manifest.with_suffix('.native-boot-status.json')
    receipt.unlink(missing_ok=True)
    log = manifest.with_suffix('.bootstatus.log')
    try:
        record = wait_for_record([str(executable), device], device, receipt, log, timeout)
        print('native simulator boot completed: ' + json.dumps(record), flush=True)
    except (subprocess.SubprocessError, OSError, AssertionError, RuntimeError):
        if log.exists():
            print('\n'.join(log.read_text(errors='replace').splitlines()[-10:]), flush=True)
        raise
