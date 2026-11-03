#!/usr/bin/env python3
"""Check the scroll proof accepts the exact threshold and rejects no movement."""
import importlib.util
from pathlib import Path

path = Path(__file__).with_name('verify-devicehub-drag.py')
spec = importlib.util.spec_from_file_location('verify_devicehub_drag', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
assert not module.has_minimum_scroll(0, 0, 100)
assert not module.has_minimum_scroll(0, 29.9, 100)
assert module.has_minimum_scroll(0, 30, 100)
assert module.has_minimum_scroll(10, 40, 100)
print('Device Hub drag threshold passed: no movement rejected; exact 30 percent accepted')
