import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import simctl_inventory


def workflow_step(name):
    workflow = (ROOT / ".github/workflows/homebrew-bottles.yml").read_text()
    step = workflow.split(f"      - name: {name}\n", 1)[1].split("\n      - name:", 1)[0]
    return textwrap.dedent(step.split("        run: |\n", 1)[1])


class SimulatorInventoryTests(unittest.TestCase):
    def setUp(self):
        self.environment = patch.dict(os.environ, {
            "LOUPE_SIMCTL_LIST_TIMEOUT": "120",
            "LOUPE_CI_SIMCTL_LIST_ATTEMPTS": "3",
        })
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.sleep = patch("time.sleep").start()
        self.addCleanup(patch.stopall)

    def test_device_selection_recovers_from_initial_timeout(self):
        inventory = json.dumps({"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-26-2": [
            {"udid": "selected-device", "name": "iPhone 17 Pro", "state": "Shutdown"},
        ]}})
        source = (ROOT / "Examples/LoupeExample/build-simulator-artifacts.sh").read_text()
        selector = source.split("<<'DEVICE_PY'\n", 1)[1].split("\nDEVICE_PY", 1)[0]
        output = io.StringIO()
        with patch.dict(os.environ, {"LOUPE_TOUCH_RUNTIME_VERSION": "26.2", "LOUPE_TOUCH_ARCHITECTURE": "arm64"}), \
             patch("platform.machine", return_value="arm64"), \
             patch.object(sys, "argv", ["-", "", str(ROOT / "scripts")]), \
             patch("subprocess.run", side_effect=[
                 subprocess.TimeoutExpired("simctl", 120),
                 subprocess.CompletedProcess([], 0, inventory, ""),
             ]) as run, contextlib.redirect_stdout(output):
            exec(compile(selector, "device-selector", "exec"), {})
        self.assertEqual(output.getvalue(), "selected-device\n")
        self.assertEqual(run.call_args.kwargs["timeout"], 120)

    def test_timeout_exhaustion_fails_with_bounded_attempts(self):
        with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("simctl", 120)) as run:
            with self.assertRaises(SystemExit) as failure:
                simctl_inventory.list_devices("--json")
        self.assertEqual(failure.exception.code, 124)
        self.assertEqual(run.call_count, 3)
        self.assertEqual(self.sleep.call_count, 2)

    def test_nonzero_exit_can_recover(self):
        with patch("subprocess.run", side_effect=[
            subprocess.CompletedProcess([], 7, "", "service unavailable"),
            subprocess.CompletedProcess([], 0, "available devices\n", ""),
        ]):
            self.assertEqual(simctl_inventory.list_devices(), "available devices\n")

    def test_invalid_settings_use_defaults(self):
        for value in ["", "invalid", "0", "-1"]:
            with self.subTest(value=value), patch.dict(os.environ, {
                "LOUPE_SIMCTL_LIST_TIMEOUT": value, "LOUPE_CI_SIMCTL_LIST_ATTEMPTS": value,
            }), patch("subprocess.run", return_value=subprocess.CompletedProcess([], 9, "", "failed")) as run:
                with self.assertRaises(SystemExit) as failure:
                    simctl_inventory.list_devices()
                self.assertEqual(failure.exception.code, 9)
                self.assertEqual(run.call_count, 3)
                self.assertEqual(run.call_args.kwargs["timeout"], 120)


class ShellWorkflowTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory(prefix="loupe-ci-tests-")
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.bin = self.directory / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                        LOUPE_CI_SIMCTL_LIST_ATTEMPTS="1", TAG="v0.6.0",
                        GITHUB_REPOSITORY="heoblitz/Loupe", TMPDIR=str(self.directory))

    def command(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        path.chmod(0o755)

    def shell(self, script):
        return subprocess.run(["/bin/bash", "-c", script], cwd=self.directory,
                              env=self.env, capture_output=True, text=True)

    def test_preflight_propagates_simulator_failure(self):
        self.command("swift", "exit 0")
        self.command("xcodebuild", "exit 0")
        self.command("xcrun", "echo service-unavailable >&2\nexit 7")
        result = self.shell(f'bash "{ROOT}/scripts/ci-print-toolchain.sh" --simulators')
        self.assertEqual(result.returncode, 7, result.stdout + result.stderr)
        self.assertIn("service-unavailable", result.stderr)

    def test_only_matching_public_release_can_receive_bottles(self):
        formula = self.directory / "Formula"
        formula.mkdir()
        self.env["SOURCE_CHECKSUM"] = "0" * 64
        (formula / "loupe.rb").write_text(
            '  url "https://github.com/heoblitz/Loupe/archive/refs/tags/v0.6.0.tar.gz"\n'
            '  sha256 "' + "0" * 64 + '"\n'
        )
        for draft, tag, allowed in [(True, "v0.6.0", False), (False, "v0.5.1", False), (False, "v0.6.0", True)]:
            with self.subTest(draft=draft, tag=tag):
                self.command("gh", "echo '" + json.dumps({"isDraft": draft, "tagName": tag}) + "'")
                result = self.shell(workflow_step("Revalidate publication target"))
                self.assertEqual(result.returncode == 0, allowed, result.stdout + result.stderr)

    def test_public_download_requires_matching_bytes(self):
        output = self.directory / "bottle-output"
        output.mkdir()
        (output / "loupe.bottle.json").write_text(json.dumps({"loupe": {"bottle": {"tags": {
            "arm64_sequoia": {"filename": "loupe-0.6.0.arm64_sequoia.bottle.tar.gz",
                               "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"},
        }}}}))
        script = workflow_step("Verify public bottle downloads")
        for body, expected in [
            ("exit 22", False),
            ('printf corrupt > "${@: -1}"', False),
            ('printf abc > "${@: -1}"', True),
        ]:
            with self.subTest(body=body):
                self.command("curl", body)
                result = self.shell(script)
                self.assertEqual(result.returncode == 0, expected, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
