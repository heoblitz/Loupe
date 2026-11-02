#!/usr/bin/env bash
set -euo pipefail

INCLUDE_SIMULATORS=0
for argument in "$@"; do
  case "$argument" in
    --simulators)
      INCLUDE_SIMULATORS=1
      ;;
    *)
      echo "usage: $0 [--simulators]" >&2
      exit 64
      ;;
  esac
done

swift --version
xcodebuild -version

if [[ "$INCLUDE_SIMULATORS" -eq 0 ]]; then
  exit 0
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT_DIR/scripts/simctl_inventory.py"
