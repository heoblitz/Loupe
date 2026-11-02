import os
import subprocess
import sys
import time


def positive_setting(name, default):
    try:
        value = int(os.environ.get(name, default))
        return value if value > 0 else default
    except ValueError:
        return default


def list_devices(*arguments):
    timeout = positive_setting("LOUPE_SIMCTL_LIST_TIMEOUT", 120)
    attempts = positive_setting("LOUPE_CI_SIMCTL_LIST_ATTEMPTS", 3)
    command = ["xcrun", "simctl", "list", "devices", "available", *arguments]
    for attempt in range(1, attempts + 1):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            if result.returncode == 0:
                return result.stdout
            status = result.returncode if result.returncode > 0 else 1
            detail = result.stderr.strip() or result.stdout.strip()
        except subprocess.TimeoutExpired:
            status = 124
            detail = f"timed out after {timeout}s"
        print(f"simctl list attempt {attempt}/{attempts} failed ({status}): {detail}", file=sys.stderr)
        if attempt < attempts:
            time.sleep(5)
    raise SystemExit(status)


if __name__ == "__main__":
    sys.stdout.write(list_devices(*sys.argv[1:]))
