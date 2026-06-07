# Platform Runtime Handoff

Last updated: 2026-06-04.

This document captures the current in-progress state for continuing platform
runtime support work on another machine. Do not treat this as a completed
release note.

Update: Loupe usage should be described as attachment mode. iOS/tvOS Simulator
and macOS development flows use injection paths when possible. Physical-device
support still requires the target app to link and embed the dynamic
`LoupeInjector` product in a debug-only target; launch-time
`DYLD_INSERT_LIBRARIES` injection is simulator-only.
`loupe app launch --linked` now uses CoreDevice `devicectl`, so devices that are
visible only through legacy Xcode device services still need manual app launch
plus `loupe app use --host`.

## Branch And Scope

- Branch: `feature/platform-runtime-support`
- User requested no release work.
- User previously asked not to commit arbitrarily; keep the working tree
  uncommitted unless explicitly asked.
- There are unrelated/user-touched signing changes in Xcode project files.
  Do not revert them without checking with the user.

## Current Dirty Tree Highlights

Major in-progress areas:

- Runtime diagnostics:
  - `Sources/LoupeCore/Diagnostics.swift`
  - `Sources/LoupeKit/LoupeRuntime.swift`
  - `Sources/LoupeKit/LoupeServer.swift`
  - `Sources/LoupeKit/LoupeRuntimeObjects.swift` (new)
  - `Sources/LoupeCLI/DiagnosticCommands.swift`
  - `Sources/LoupeCLI/LoupeCLIUsage.swift`
  - CLI/platform tests
- Platform examples:
  - `Examples/MacLoupeExample/main.swift`
  - `Examples/MacLoupeExample/MacLoupeExample.xcodeproj`
  - `Examples/MacLoupeExample/run-macos-e2e.sh`
  - `Examples/LoupeTVExample/LoupeTVExample/TVViewController.swift`
  - `Examples/LoupeTVExample/run-tvos-runtime-e2e.sh`
  - `Examples/LoupeExample/LoupeExample/ViewController.swift`
  - `Examples/LoupeExample/run-native-scenarios.sh`
- SwiftUI probe work:
  - `Sources/LoupeKit/LoupeSwiftUIProbe.swift` (new)
  - `README.md`
  - `skills/loupe/SKILL.md`

## SwiftUI Probe State

The desired shape is:

- Apps that import `LoupeKit` can use a public SwiftUI modifier:

  ```swift
  import LoupeKit
  import SwiftUI

  VStack {
      // ...
  }
  .accessibilityIdentifier("checkout.form")
  .loupeProbe("checkout.form.probe", label: "Checkout form")
  ```

- Apps that do not import `LoupeKit` should use a zero-dependency helper with a
  local name such as `.localLoupeProbe(...)`. The helper creates a background
  `UIViewRepresentable` or `NSViewRepresentable` with only standard
  accessibility identifiers. Because it is attached with `background`, the
  platform probe follows the SwiftUI region bounds.
- When a view-backed helper is not practical, a no-import helper can post
  measured `dev.loupe.probe` bounds. Loupe registers those as synthetic
  `LoupeRegisteredProbe` nodes. They are queryable by `testID` and role, but
  are not backed by a platform view, so runtime activation and mutation should
  be proved separately.

Current implementation:

- Added `Sources/LoupeKit/LoupeSwiftUIProbe.swift`.
- It exposes `View.loupeProbe(_ id: String, label: String? = nil)`.
- The modifier uses `background` to attach a platform probe view that follows
  the SwiftUI region bounds:
  - iOS/tvOS: `UIViewRepresentable`
  - macOS: `NSViewRepresentable`
- The platform view sets:
  - test/accessibility identifier
  - accessibility label
  - `loupe.probe=true` metadata when `LoupeKit` is linked

Resolved distinction:

- `import LoupeKit` apps use public `.loupeProbe(...)`.
- Injected/no-import examples use local `.localLoupeProbe(...)` helpers so the
  fallback path is not confused with the public LoupeKit API.

Chosen fixes:

1. Keep injected examples dependency-free and use local zero-dependency probe
   helpers when a SwiftUI region frame is needed.
2. Use bridge notifications for app-authored logs, metadata, reference
   evidence, lifetime probes, and no-import synthetic probe registration.
3. For physical-device debug apps, link and embed dynamic `LoupeInjector`
   instead of importing `LoupeKit` and starting `LoupeServer` from app code.

## watchOS And visionOS State

- `Package.swift` declares watchOS and visionOS platforms.
- visionOS Simulator builds now pass for `LoupeKit` and `LoupeInjector` after
  avoiding `UIScreen.main` and using `UIWindowScene` bounds where needed.
- watchOS Simulator builds now pass for `LoupeKit` and `LoupeInjector`, and
  `LoupeInjectorStart` starts `LoupeServer` on watchOS.
- watchOS runtime snapshots use a registered-probe backend instead of the
  UIKit/AppKit view-tree walker. Apps can expose SwiftUI `.loupeProbe(...)`,
  `Loupe.registerProbe(...)`, or no-import `dev.loupe.probe` nodes plus logs,
  metadata, defaults/flags, and runtime identity.
- `Examples/LoupeWatchExample/run-watchos-runtime-e2e.sh` verifies a
  dependency-free SwiftUI watch app launched with injection. It captures
  meaningful session-dashboard probes, accessibility export, view/accessibility
  tree output, app-authored logs, network evidence, references, lifetime
  probes, and defaults/flags. Broad automatic WatchKit/SwiftUI element
  discovery and runtime input actions are still not implemented.

## Verification Already Completed Before SwiftUI Modifier Change

These passed before adding the dedicated local fallback probe helpers:

```bash
swift test
swift build --product loupe
xcodebuild \
  -project Examples/MacLoupeExample/MacLoupeExample.xcodeproj \
  -scheme MacLoupeExample \
  -destination 'platform=macOS' \
  -configuration Debug \
  build
git diff --check
Examples/LoupeExample/run-native-scenarios.sh
Examples/MacLoupeExample/run-macos-e2e.sh
Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
scripts/verify-agent-work.sh
```

After adding `LoupeSwiftUIProbe.swift`, these passed:

```bash
swift build --product loupe --product LoupeInjector
xcodebuild \
  -project Examples/MacLoupeExample/MacLoupeExample.xcodeproj \
  -scheme MacLoupeExample \
  -destination 'platform=macOS' \
  -configuration Debug \
  build
git diff --check
```

These have not yet been rerun after the modifier change:

```bash
swift test
Examples/LoupeExample/run-native-scenarios.sh
Examples/MacLoupeExample/run-macos-e2e.sh
Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
scripts/verify-agent-work.sh
```

## Physical Device Checks

### iPhone X, iOS 16.7.16, 2026-06-04

Connected device was detected by legacy Xcode device services:

```text
Name: won의 iPhone
Hardware UDID: 8f27590f4a1b239f0f7c6d4f90090291243a213e
Model: iPhone X / iPhone10,6
iOS: 16.7.16
xcdevice: available=true
xctrace: online
```

CoreDevice detected a related device record but could not use it:

```text
CoreDevice identifier: 0299A737-9A98-5D0A-A431-B0E98532B121
devicectl state: unavailable
pairingState: unsupported
tunnelState: unavailable
ddiServicesAvailable: false
```

Observed results:

- `xcrun devicectl device process launch --device
  0299A737-9A98-5D0A-A431-B0E98532B121 ...` failed with CoreDevice error 1011.
- `xcrun devicectl device process launch --device
  8f27590f4a1b239f0f7c6d4f90090291243a213e ...` failed because CoreDevice did
  not know the legacy UDID.
- `xcodebuild` could target the legacy UDID, but device build failed because the
  current provisioning profile does not include this device and local Xcode
  account credentials are unavailable for automatic provisioning.

Conclusion: this iPhone X is useful for proving the unsupported-device branch,
but not for a full Loupe physical-device E2E until provisioning is fixed and the
linked app is launched outside `devicectl`.

### iPhone 15 Pro, iOS 26.5, 2026-06-04

Connected device was detected:

```text
Name: 허원의 iPhone 15 pro
CoreDevice identifier: DA221F6B-B7C8-5DD5-AB36-1C59CDD720E4
Hardware UDID: 00008130-00121D312204001C
Model: iPhone 15 Pro
iOS: 26.5
Developer Mode: enabled
Transport: wired
Tunnel: connected
```

Commands run:

```bash
xcrun devicectl list devices
xcrun devicectl device info details --device DA221F6B-B7C8-5DD5-AB36-1C59CDD720E4
xcodebuild -project /tmp/loupe-device-fixture/ReadingNowApp/ReadingNowApp.xcodeproj -scheme ReadingNowApp -destination 'id=00008130-00121D312204001C' -configuration Debug -derivedDataPath /tmp/loupe-device-fixture/DerivedData build
xcrun devicectl device install app --device DA221F6B-B7C8-5DD5-AB36-1C59CDD720E4 /tmp/loupe-device-fixture/DerivedData/Build/Products/Debug-iphoneos/ReadingNowApp.app
.build/debug/loupe app launch --bundle-id dev.loupe.readingnow --device DA221F6B-B7C8-5DD5-AB36-1C59CDD720E4 --linked --host 'http://[fdc2:95e8:dd9e::1]:8765' --port 8765 --bind-host 0.0.0.0 --timeout 20
.build/debug/loupe app info --host 'http://[fdc2:95e8:dd9e::1]:8765'
.build/debug/loupe ui snapshot --host 'http://[fdc2:95e8:dd9e::1]:8765' --timeout 10 --output /tmp/loupe-device-injector-snapshot.json
.build/debug/loupe ui query /tmp/loupe-device-injector-snapshot.json --test-id readingNow.title --max-results 1
```

Observed results:

- `devicectl` sees the physical device and reports developer mode/tunnel
  available.
- `LoupeInjector` is a dynamic Swift package product and was linked, embedded,
  signed, and loaded by the debug app.
- The debug app did not import `LoupeKit` and did not call
  `LoupeServer.start()` from app code.
- `loupe app launch --linked` passed `LOUPE_PORT=8765` and
  `LOUPE_BIND_HOST=0.0.0.0` through CoreDevice and stored the runtime host.
- `loupe app info` returned a live iOS runtime with device identifier
  `DA221F6B-B7C8-5DD5-AB36-1C59CDD720E4`.
- `loupe ui snapshot` and `loupe ui query --test-id readingNow.title` succeeded;
  the queried text was `Reading Now`.

Current physical-device support conclusion:

- Injection launch is simulator-only today because Loupe uses `simctl launch`
  plus `DYLD_INSERT_LIBRARIES`.
- A debug app that links and embeds dynamic `LoupeInjector` is the intended
  device path. `LoupeInjector` depends on `LoupeKit` internally and starts
  `LoupeServer` automatically when the library loads. The current host CLI can
  launch CoreDevice-compatible devices with `--linked`, but older devices that
  are unavailable to `devicectl` need manual Xcode launch plus
  `loupe app use --host`.
- `LoupeServer` binds to `127.0.0.1` by default. Real-device local-network
  inspection needs an intentional device-reachable bind, such as
  `LOUPE_BIND_HOST=0.0.0.0`, plus Mac/device network reachability.

## Recommended Next Steps

1. Re-run the verification matrix after any further runtime or example changes:

   ```bash
   swift build --product loupe --product LoupeInjector
   xcodebuild \
     -project Examples/MacLoupeExample/MacLoupeExample.xcodeproj \
     -scheme MacLoupeExample \
     -destination 'platform=macOS' \
     -configuration Debug \
     build
   swift test
   Examples/LoupeExample/run-native-scenarios.sh
   Examples/MacLoupeExample/run-macos-e2e.sh
   Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
   Examples/LoupeWatchExample/run-watchos-runtime-e2e.sh
   git diff --check
   ```

2. For real-device support, keep the separate linked-runtime path instead of
   trying to stretch simulator injection:
   - CoreDevice-compatible `devicectl` install/launch support
   - clear unsupported-device fallback for legacy Xcode-only devices
   - linked and embedded `LoupeInjector` runtime on device
   - host-to-device transport
   - device screenshots/input strategy
   - tests that distinguish simulator-only from physical-device support
