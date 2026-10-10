# Action target and touch regression coverage

## Scope

`act targets` lists controls with an actual action contract, including UIKit
recognizers and SwiftUI gesture declarations outside the accessibility tree.
Decorative labels, disabled controls, unwired controls and uncertain geometry
are omitted. Accessibility remains the first source for selector resolution;
view geometry is a fallback. Coordinates can target an unlisted surface, but
Loupe does not infer an undiscovered handler from pixels.

The public interface stays the same except for the approved additions:
`act tap --count 2` and `act drag --hold-duration <seconds>`. A held drag keeps
one contact down before moving it; it is not a long press followed by a new drag.

| Runtime | Target discovery | Input delivery |
| --- | --- | --- |
| Simulator / UIKit | Accessibility, wired controls, enabled recognizers, scrollable content | Host SimulatorKit HID |
| Simulator / SwiftUI | Native accessibility, bounded debug gesture declarations with verified geometry | Host SimulatorKit HID |
| Physical iOS / UIKit | Same discovery rules | Linked Debug injector, UIKit touch dispatch |
| Physical iOS / SwiftUI | Same discovery rules; prepare accessibility before first observation | Linked Debug injector, UIKit touch dispatch |

The CLI selects the backend from runtime identity. Literal iOS text input uses
its focused `UIKeyInput` responder, preserving Korean and emoji independently
of keyboard layout. Physical injection is development-only. SwiftUI private
metadata may vary by OS; unsupported declarations are omitted. Pinch and
multitouch are outside this change.

## One local and CI entry point

```sh
Examples/LoupeExample/run-touch-e2e.sh
```

Both environments use this script for device selection, public `simctl bootstatus -b`, keyboard preparation/restoration, fixture build and launch,
and the same Python assertions. Keyboard preferences are prepared while the selected simulator is shut down,
then restored with its original boot state after verification. This follows [Fastlane’s pre-boot localization pattern](https://github.com/fastlane/fastlane/blob/master/snapshot/lib/snapshot/simulator_launchers/simulator_launcher_base.rb)
and avoids guest `defaults` processes during startup. The standard-library Python runner only orchestrates processes
and checks app state; product behavior remains in Swift/Objective-C. No CI-only native boot observer, host service
modification, action replay or extended diagnostic deadline is used.

All iOS E2E scripts share toolchain checks, device selection and a strict
180-second boot completion gate (without a launchd-only fallback) in
`build-simulator-artifacts.sh`: Xcode 26.3 on Apple Silicon, iOS 26.2/iPhone 17 Pro. Missing or mismatched runtimes fail before input;
`LOUPE_DEVICE` selects an exact device within that runtime. For additional OS
coverage, explicitly set `LOUPE_TOUCH_RUNTIME_VERSION` in either environment.
The local and hosted commands use the same launch and action deadlines.
Both use the Python interpreter shipped with the selected Xcode for the
standard-library harness, rather than a separately updated Homebrew Python.

Verify pins Xcode for every job. Bottle builds also select Xcode 26.3 through
`xcode-select`, because Homebrew sanitizes `DEVELOPER_DIR`, and check the version
recorded in bottle metadata. Apple Silicon bottles are built/poured on macOS 15; runtime
coverage uses macOS 26. Intel Macs are not supported.
A local comparison must use the CI-produced artifact, matching runtime and a
fresh fixture build directory; a locally rebuilt CLI is a different artifact.

For a poured Homebrew bottle, set `LOUPE_TOUCH_CLI` to its executable and
`LOUPE_EXAMPLE_PREBUILT_INJECTOR` to its injector framework binary. Only the
fixture app is rebuilt. The Apple Silicon job runs these same assertions with
the downloaded bottle. A source build cannot substitute for a bottle runtime pass.

For a foreground physical-device fixture, set `LOUPE_TOUCH_HOST` to its runtime
URL and optionally `LOUPE_DEVICE` to its device identity. Run again with a fresh
`touch.swiftui` launch and `LOUPE_TOUCH_MODE=--swiftui-only` to verify cold SwiftUI
discovery. Simulator setup is skipped; action assertions are shared.

## Assertions and evidence

Separate UIKit and SwiftUI screens verify button counters through selectors,
one-shot aliases, coordinates and saved refs; gesture-only taps, double taps,
long presses, immediate and held drags; scroll offsets; and exact mixed
English/Korean/emoji text with editing notifications. Negative cases verify
that a single tap cannot satisfy a double tap, immediate drag cannot satisfy
a held drag, decoration is absent from targets, invalid geometry is rejected,
and explicit accessibility failure does not retry as touch. Internal dispatcher
checks cover competing contacts and recovery after rejection.

Evidence is saved under the printed `/tmp/loupe-touch-evidence-*` directory:
runtime identity, target lists, action traces, snapshots and reports. A command
exit code alone is insufficient; each gesture must change its app-owned state.
Simulator screenshots read the main-display framebuffer in-process, following
[idb's IOSurface approach](https://github.com/facebook/idb/blob/main/FBSimulatorControl/Framebuffer/FramebufferSurface.swift).
Unsupported displays fall back to `simctl` within the same 10-second capture
budget. Late captures cannot overwrite output. Fixture logs record received
contacts so HID acknowledgements can be compared with actual UIKit delivery.
Boot has a 180-second deadline. The runner allows 15 seconds for an action plus
the existing 10-second deadline for each requested before/after screenshot
(35 seconds with a trace), equally on local and hosted runs. CLI request and
capture deadlines are unchanged. Before/after diagnostic screenshot failures are
recorded in the trace without aborting input or replaying an action. Target,
readiness and app-state verification failures still fail the command. Explicit
screenshot/report commands still require a successful capture.
Post-action `--expect-visible` checks native accessibility before requesting a
full view snapshot for unmatched targets. A slow style/layout capture therefore
does not block a screen already confirmed by accessibility. Compatibility
fallbacks share the remaining observation deadline.

## Release gate

Merge/release requires three consecutive complete successful Verify and
Homebrew bottle runs on the same final source, including the Apple Silicon bottle runtime
job. A source change restarts the count. Current-source local and hosted
results belong in the PR; older device passes do not validate changed code.
