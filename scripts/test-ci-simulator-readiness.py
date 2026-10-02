#!/usr/bin/env python3
"""Exercise boot receipts without requiring a running simulator."""
import json
import pathlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

from ci_simulator_readiness import wait_for_record


class ReadinessTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='loupe-boot-contract-')
        self.addCleanup(self.directory.cleanup)
        root = pathlib.Path(self.directory.name)
        self.receipt = root / 'receipt.json'
        self.log = root / 'observer.log'
        self.pid = root / 'pid'

    def command(self, record, stall=False, delay=0, stamp=True):
        script = ('import json,os,pathlib,signal,time; '
                  'signal.signal(signal.SIGTERM, signal.SIG_IGN); '
                  'pathlib.Path(__import__("sys").argv[2]).write_text(str(os.getpid())); ')
        if record is not None:
            script += ('__import__("sys").path.insert(0,' + repr(str(pathlib.Path(__file__).resolve().parent)) + '); '
                       'from ci_simulator_readiness import monotonic_ns; '
                       'time.sleep(' + repr(delay) + '); '
                       'record=json.loads(' + repr(json.dumps(record)) + '); ')
            if stamp:
                script += 'record["observedMonotonicNS"]=monotonic_ns(); '
            script += 'print(json.dumps(record),flush=True); '
        if stall:
            script += 'time.sleep(30)'
        return [sys.executable, '-c', script, str(self.receipt), str(self.pid)]

    def check_reaped(self):
        # A completed waiter must have collected its exact child, including
        # observers that ignore SIGTERM after recording semantic completion.
        if self.pid.exists():
            with self.assertRaises(ChildProcessError):
                __import__('os').waitpid(int(self.pid.read_text()), __import__('os').WNOHANG)

    def test_finished_stream_does_not_wait_for_observer_exit(self):
        record = dict(udid='owned', state=3, status=4294967295, finished=True)
        result = wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 2)
        self.assertEqual({key:result[key] for key in record}, record)
        self.check_reaped()

    def test_timely_completion_survives_delayed_parent_wakeup(self):
        record = dict(udid='owned', state=3, status=4294967295, finished=True)
        real_sleep = time.sleep
        with patch('ci_simulator_readiness.time.sleep', side_effect=lambda _: real_sleep(0.4)):
            result = wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 0.2)
        self.assertTrue(result['finished'])
        self.check_reaped()

    def test_late_completion_is_rejected_after_delayed_parent_wakeup(self):
        record = dict(udid='owned', state=3, status=4294967295, finished=True)
        real_sleep = time.sleep
        with patch('ci_simulator_readiness.time.sleep', side_effect=lambda _: real_sleep(0.5)):
            with self.assertRaises(subprocess.TimeoutExpired):
                wait_for_record(self.command(record, True, delay=0.3), 'owned', self.receipt, self.log, 0.2)
        self.assertTrue(json.loads(self.receipt.read_text())['finished'])
        self.check_reaped()

    def test_completion_without_native_time_is_rejected(self):
        record = dict(udid='owned', state=3, status=4294967295, finished=True)
        with self.assertRaisesRegex(AssertionError, 'observation timestamp'):
            wait_for_record(self.command(record, True, stamp=False), 'owned', self.receipt, self.log, 2)
        self.check_reaped()

    def test_completion_timestamp_before_launch_is_rejected(self):
        record = dict(udid='owned', state=3, status=4294967295, finished=True, observedMonotonicNS=1)
        with self.assertRaisesRegex(AssertionError, 'predates'):
            wait_for_record(self.command(record, True, stamp=False), 'owned', self.receipt, self.log, 2)
        self.check_reaped()

    def test_incomplete_observation_times_out_and_reaps(self):
        record = dict(udid='owned', state=3, status=0, finished=False)
        with self.assertRaises(subprocess.TimeoutExpired):
            wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 0.3)
        self.check_reaped()

    def test_terminal_migration_failure_is_not_success(self):
        record = dict(udid='owned', state=3, status=3, finished=False)
        with self.assertRaisesRegex(RuntimeError, 'migration failed'):
            wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 2)
        self.check_reaped()

    def test_completion_requires_finished_status_and_booted_device(self):
        for state, status in [(2, 4294967295), (3, 0)]:
            with self.subTest(state=state, status=status):
                self.receipt.unlink(missing_ok=True)
                record = dict(udid='owned', state=state, status=status, finished=True)
                with self.assertRaisesRegex(AssertionError, 'Invalid boot completion'):
                    wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 2)
                self.check_reaped()

    def test_other_device_receipt_is_rejected(self):
        record = dict(udid='user-device', state=3, status=4294967295, finished=True)
        with self.assertRaisesRegex(AssertionError, 'different simulator'):
            wait_for_record(self.command(record, True), 'owned', self.receipt, self.log, 2)
        self.check_reaped()

    def test_successful_exit_without_readiness_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'without successful boot completion'):
            wait_for_record(self.command(None), 'owned', self.receipt, self.log, 2)
        self.check_reaped()

    def test_truncated_stream_is_not_completion(self):
        command = [sys.executable, '-c', 'print(\'{"udid":"owned","finished":\',flush=True)']
        with self.assertRaisesRegex(RuntimeError, 'without successful boot completion'):
            wait_for_record(command, 'owned', self.receipt, self.log, 2)
        self.assertFalse(self.receipt.exists())

    def test_failed_observer_is_not_completion(self):
        command = [sys.executable, '-c', 'raise SystemExit(1)']
        with self.assertRaises(subprocess.CalledProcessError):
            wait_for_record(command, 'owned', self.receipt, self.log, 2)

    def test_old_receipt_is_rejected_before_launch(self):
        self.receipt.write_text('{"finished":true}')
        with self.assertRaisesRegex(AssertionError, 'fresh receipt'):
            wait_for_record(self.command(None), 'owned', self.receipt, self.log, 2)
        self.assertFalse(self.pid.exists())

    def test_setup_builds_observer_before_any_simulator_request(self):
        # Exercise the real setup entry point. Stop at its first service call
        # after checking that the helper was already built on the idle host.
        import runpy
        import ci_simulator_readiness
        script = pathlib.Path(__file__).with_name('ci-ios-touch-simulator.py')
        events = []
        def build(_):
            events.append('build')
            return pathlib.Path(self.directory.name) / 'observer'
        def service(*args, **kwargs):
            self.assertEqual(events, ['build'])
            raise StopIteration('first simulator request')
        with patch.object(ci_simulator_readiness, 'build_observer', build), \
             patch.object(subprocess, 'run', service), \
             patch.object(sys, 'argv', [str(script), 'create', str(self.receipt)]), \
             patch.dict(__import__('os').environ, {'GITHUB_ACTIONS':'false'}, clear=True):
            with self.assertRaisesRegex(StopIteration, 'first simulator request'):
                runpy.run_path(str(script), run_name='__main__')


if __name__ == '__main__':
    unittest.main()
