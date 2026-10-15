#!/usr/bin/env python3
"""Check hosted-only guards and per-device override preservation without booting."""
import importlib.util
import json
import os
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('widgets', pathlib.Path(__file__).with_name('ci-simulator-widgets.py'))
widgets = importlib.util.module_from_spec(spec)
spec.loader.exec_module(widgets)
DEVICE = '00000000-1111-2222-3333-444444444444'


class WidgetProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='loupe-widget-profile-')
        self.addCleanup(self.temp.cleanup)
        root = pathlib.Path(self.temp.name)
        self.path = root / ('com.apple.CoreSimulator.SimDevice.' + DEVICE) / 'disabled.plist'
        for target, value in [('STORE_ROOT', root), ('EVIDENCE', root / 'profile.json')]:
            active = patch.object(widgets, target, value)
            active.start()
            self.addCleanup(active.stop)
        active = patch.dict(os.environ, GITHUB_ACTIONS='true', RUNNER_ENVIRONMENT='github-hosted')
        active.start()
        self.addCleanup(active.stop)

    def inventory(self, state='Shutdown'):
        return json.dumps({'devices': {'runtime': [{'udid': DEVICE, 'state': state}]}}).encode()

    def test_preserves_unrelated_and_explicit_enable_entries(self):
        self.path.parent.mkdir()
        self.path.write_bytes(plistlib.dumps({'unrelated.enabled': False, 'unrelated.disabled': True}))
        with patch.object(widgets.subprocess, 'check_output', return_value=self.inventory()):
            widgets.prepare(DEVICE)
            widgets.prepare(DEVICE)
        data = plistlib.loads(self.path.read_bytes())
        self.assertEqual(data, {'unrelated.enabled': False, 'unrelated.disabled': True,
                               **dict.fromkeys(widgets.LABELS, True)})

    def test_refuses_local_and_self_hosted_execution_before_io(self):
        for actions, runner in [('false', 'github-hosted'), ('true', 'self-hosted')]:
            with patch.dict(os.environ, GITHUB_ACTIONS=actions, RUNNER_ENVIRONMENT=runner):
                with patch.object(widgets.subprocess, 'check_output') as command:
                    with self.assertRaises(RuntimeError):
                        widgets.prepare(DEVICE)
                    command.assert_not_called()
        self.assertFalse(self.path.exists())

    def test_refuses_running_or_missing_device(self):
        for data in [self.inventory('Booted'), b'{"devices":{}}']:
            with patch.object(widgets.subprocess, 'check_output', return_value=data):
                with self.assertRaises(RuntimeError):
                    widgets.prepare(DEVICE)
        self.assertFalse(self.path.exists())

    def test_refuses_invalid_device_before_io(self):
        with patch.object(widgets.subprocess, 'check_output') as command:
            with self.assertRaises(ValueError):
                widgets.prepare('../another-device')
            command.assert_not_called()

    def test_refuses_unknown_store_values(self):
        self.path.parent.mkdir()
        original = plistlib.dumps({'unrelated': 'unknown'})
        self.path.write_bytes(original)
        with patch.object(widgets.subprocess, 'check_output', return_value=self.inventory()):
            with self.assertRaises(RuntimeError):
                widgets.prepare(DEVICE)
        self.assertEqual(self.path.read_bytes(), original)

    def test_accepts_both_launchctl_disabled_formats(self):
        for value in ['true', 'disabled']:
            output = '\n'.join('"' + name + '" => ' + value for name in widgets.LABELS)
            with patch.object(widgets.subprocess, 'check_output', return_value=output):
                widgets.verify(DEVICE)

    def test_rejects_missing_or_enabled_override(self):
        for value in ['false', 'enabled', '']:
            output = '\n'.join('"' + name + '" => ' + value for name in widgets.LABELS)
            with patch.object(widgets.subprocess, 'check_output', return_value=output):
                with self.assertRaises(RuntimeError):
                    widgets.verify(DEVICE)


if __name__ == '__main__':
    unittest.main()
