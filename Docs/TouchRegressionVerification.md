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
| Simulator / UIKit | Accessibility, wired controls, enabled recognizers, scrollable content | Host DTUHID when available; legacy SimulatorKit otherwise |
| Simulator / SwiftUI | Native accessibility, bounded debug gesture declarations with verified geometry | Host DTUHID when available; legacy SimulatorKit otherwise |
| Physical iOS / UIKit | Same discovery rules | Linked Debug injector, UIKit touch dispatch |
| Physical iOS / SwiftUI | Same discovery rules; prepare accessibility before first observation | Linked Debug injector, UIKit touch dispatch |

The CLI selects the backend from runtime identity. Literal iOS text input uses
its focused `UIKeyInput` responder, preserving Korean and emoji independently
of keyboard layout. Physical injection is development-only. SwiftUI private
metadata may vary by OS; unsupported declarations are omitted. Pinch and
multitouch are outside this change.

Modern CoreSimulator supplies `com.apple.coredevice.feature.remote.hid.digitizer`
through `dtuhidd`. Loupe looks this service up on the selected, booted device and
confirms a live peer before sending input. A separate no-event barrier confirms
that the daemon consumed preceding events before the connection is released.
Only a known unsupported-service response permits the legacy transport; a dead
or unresponsive modern service is reported as an error. No action is replayed.
This follows the transport and simulator-XPC protocol documented by
[idb](https://github.com/facebook/idb/tree/main/FBSimulatorControl/HID).

The previous Xcode 27 screen-class check selected a manually registered virtual
digitizer for older guests too. Real tests with Xcode 27.1 / iOS 26.3 showed
successful send acknowledgements without application-state changes; legacy
input could also stop working after the guest's modern service activated.
The DTUHID path passes the same complete UIKit/SwiftUI input suite with Device
Hub active, including a fresh-process SwiftUI launch. Byte-format fixtures alone
cannot verify input delivery.

New SDKs can store an uninitialized `@State` value as a `LazyState` closure.
Reflection never calls that closure. Such a property retains its name and type,
has no value, and reports `valueUnavailableReason: "deferredInitializer"`;
compact trees show `<unavailable:deferredInitializer>`. Explicitly initialized
state remains readable; opaque state values report `unsupportedStateValue`
without calling them. The macOS fixture initializes the state checked by its
existing E2E assertion explicitly, while platform tests cover both forms and
verify that observation does not execute the deferred initializer.

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
`build-simulator-artifacts.sh`: Xcode 26.6 on Apple Silicon, iOS 26.2/iPhone 17 Pro. Missing or mismatched runtimes fail before input;
`LOUPE_DEVICE` selects an exact device within that runtime. For additional OS
coverage, explicitly set `LOUPE_TOUCH_RUNTIME_VERSION` in either environment.
An additional Xcode 27.1 / iOS 27.0 job verifies the modern input service. Select it
locally with `LOUPE_TOUCH_XCODE_VERSION=27.1` and
`LOUPE_TOUCH_RUNTIME_VERSION=27.0`, plus `DEVELOPER_DIR` for that Xcode.
The iOS 27 jobs use the image's existing iPhone 17. A separate build job
produces the CLI, injector, and fixture without booting a device. Runtime jobs
verify the artifact source commit and reuse its binaries on fresh hosts.
Both iOS bottle runtime jobs use a fixture compiled on a separate host with
their matching SDK. Their CLI and injector must still come from the installed
bottle. Local builds finish before boot.
The source job opens Device Hub after boot and verifies its active input route;
set `LOUPE_TOUCH_OPEN_DEVICE_HUB=1` to exercise that path locally. Bottle jobs
verify headless input.
The local and hosted commands use the same launch and action deadlines.
Local and self-hosted runs restore the selected device's saved preferences and
state. GitHub-hosted VMs are discarded after the job; their live guest is left
available for diagnostics rather than shut down solely to restore temporary
preferences. Cleanup preserves the original test exit status.
The three hosted touch jobs also suppress four background widget services on
their disposable selected Simulator: PosterBoard, chronod, liveactivitiesd,
and navd. Prepare while that device is shut down; preserve unrelated launchd
overrides, and verify the four overrides after the full input suite. Local and
self-hosted execution is refused. This follows the per-device override format
and widget-only subset reviewed in [SimSlim](https://github.com/MobAI-App/simslim/tree/6518ba7eab1123d7e1d7797b0e05f51043b42a5b).
With identical source artifacts and deadlines, stock iOS 26.2 and 27.0 guests
failed keyboard/status or snapshot checks in the four-host comparison, while
both widget profiles passed the complete suite. The iOS 26.2 comparison reduced
peak compressed-memory occupancy by approximately 317 MiB. The iOS 27.0 hosts'
peak wired memory was 4,191 MiB stock versus 1,648 MiB with the widget profile.
App input, keyboard, HID, and accessibility services retain their defaults.
Scroll assertions observe the required directional movement within the same
four-second state-check budget as label assertions, instead of assuming a
fixed 200–300 ms animation delay. Input is sent once; offset samples are saved.
The iOS simulator launcher waits for an initial native action observation within
its existing launch deadline, preparing accessibility before input begins.
Both use the Python interpreter shipped with the selected Xcode for the
standard-library harness, rather than a separately updated Homebrew Python.

Verify tests SwiftPM, loader discovery and both transport contracts on Xcode
26.6 and 27.1. Bottle builds retain Xcode 26.3 through
`xcode-select`, because Homebrew sanitizes `DEVELOPER_DIR`, and check the version
recorded in bottle metadata. Apple Silicon bottles are built/poured on macOS 15; runtime
coverage uses macOS 26. Intel Macs are not supported.
A local comparison must use the CI-produced artifact, matching runtime and a
fresh fixture build directory; a locally rebuilt CLI is a different artifact.

For a poured Homebrew bottle, set `LOUPE_TOUCH_CLI` to its executable and
`LOUPE_EXAMPLE_PREBUILT_INJECTOR` to its injector framework binary. Only the
fixture app is rebuilt locally. CI can supply the same-source app archive with
`LOUPE_EXAMPLE_PREBUILT_APP`. The Apple Silicon job runs these same assertions with
the downloaded bottle. A source build cannot substitute for a bottle runtime pass.
Poured artifacts run on both the Xcode 26.3 / iOS 26.2 and
Xcode 27.0 / iOS 27.0 hosts.

For a foreground physical-device fixture, set `LOUPE_TOUCH_HOST` to its runtime
URL and optionally `LOUPE_DEVICE` to its device identity. Run again with a fresh
`touch.swiftui` launch and `LOUPE_TOUCH_MODE=--swiftui-only` to verify cold SwiftUI
discovery. Simulator setup is skipped; action assertions are shared.

## Assertions and evidence

SimulatorKit's Xcode 27 screen input uses a separate virtual digitizer target
derived from the actual main screen ID and bound to its display UID. Loupe
registers that digitizer before input, waits for its acknowledgement,
and sends the native touch allocation without repacking its contacts or timestamp.
Older SimulatorKit retains its main-digitizer envelope with the native payload
stride and complete event bytes. `scripts/verify-hid-touch-messages.sh` checks
144–192 byte payloads, full native-message preservation, legacy contact layout,
screen registration offsets and invalid registration data.
The Xcode 27 registration includes its external-input flag (`isBuiltIn = 0`) at
wire offset `0x44` and the display UID at `0x45`. A separate external target
stays connected while Device Hub manages the built-in digitizer.
The Xcode 27 fixture compiles for a generic arm64 simulator destination and is
installed and exercised on the explicitly selected runtime/device.
Host HID dispatch and framebuffer captures use Dispatch workers while the CLI
task suspends. Blocking SimulatorKit calls must not occupy Swift's cooperative
executor; a detached Swift task still uses that executor.

SwiftUI debug-graph traversal holds SwiftUI's update scope while evaluating
graph attributes; main-actor isolation alone does not satisfy the iOS 27 graph
precondition. Resolve iOS 27's `ViewGraphHostUpdate` entry points and the earlier
`Update` entry points as complete begin/end pairs. Missing entry points omit
private touch declarations.
Gesture declarations merge with matching native semantic nodes throughout the
same host subtree, preserving unique selectors across iOS container layouts.
Distinct semantic elements sharing an identifier remain ambiguous.

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
