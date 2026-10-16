# idb input PoC

Read the [measured results and recommendation](RESULTS.md) first.

Experimental branch only. The production Loupe backend and PR #24 are preserved.
Do not merge the replacement `.github/workflows/verify.yml`: it is a manual-only
experiment using the existing workflow ID, not the release verification gate.

Compare official idb **1.7.3** (commit
`aaa7e7ab784df3c7027b16f2c21196119ae5adb4`) against Loupe's existing native input.
Use the same UIKit/SwiftUI app, frames, observer, 15-second action/process cap,
and four-second app-state assertion budget. Each backend gets fresh app processes.
No input is replayed after a failure. This is a capability check, not a reliability
study or the three-cycle release gate.

`IDB_POC_MODE=standalone` runs a second proof using only idb: launch the app
without Loupe injection, discover frames through idb AX, send HID taps/long
presses, set Unicode with AX, verify app state/change events through idb AX,
and take screenshots. It never invokes a Loupe observation/action command.
The companion uses `--only simulator` to avoid initializing physical-device
discovery on a simulator-only host. Launch readiness stays within 30 seconds.

Tests cover buttons, gesture taps, long press, scrolling in both directions,
held drag, ASCII and Korean/emoji input, plus separate idb accessibility tree,
accessibility value-setting/change-event and screenshot probes. Coordinate taps
explicitly use HID. idb's held-drag command resolves coordinates through its
accessibility API; that distinction is preserved in `commands.json`.

The common observer remains Loupe. The additional idb AX tree and screenshot
probes only assess whether idb can independently observe the screen; they do not
claim parity with Loupe's view/style/layout diagnostics.

Install without changing Homebrew kegs or global Python packages:

```sh
swift build --product loupe
IDB_PYTHON=python3.12 bash poc/idb/install.sh /tmp/loupe-idb
export IDB_COMPANION=/tmp/loupe-idb/bin/idb_companion
export IDB_CLI=/tmp/loupe-idb/venv/bin/idb
export DEVELOPER_DIR=/Applications/Xcode-26.3.app/Contents/Developer
bash poc/idb/run.sh
```

Select an exact device with `LOUPE_DEVICE`. Existing fixture binaries can be
provided through `LOUPE_EXAMPLE_PREBUILT_APP` and
`LOUPE_EXAMPLE_PREBUILT_INJECTOR`. Local keyboard preferences and original boot
state are restored, and only the PoC's companion process is terminated.

CI compares stock Xcode 26.3/iOS 26.2, stock Xcode 27.0/iOS 27.0 with Device Hub,
and Xcode 27 with the existing CI-only widget profile. Each host tests both
backends. CI reuses pinned prebuilt Loupe artifacts from source
`3b08aac8e73830e822da3ea872949defdf402357` without compiling on the input host.
The current production sources have not changed since those artifacts.

Raw evidence: `/tmp/loupe-idb-evidence` or `IDB_EVIDENCE`. A failed capability
produces a failing exit code and is preserved in `results.json`.
