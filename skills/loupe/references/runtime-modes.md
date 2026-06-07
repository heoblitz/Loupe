# Runtime Modes

Use this when choosing how Loupe attaches, or when launch works but observation
does not.

## iOS/tvOS Simulator Injection

```bash
$LOUPE app launch --device <sim-udid> --bundle-id <bundle-id> --inject
```

- `app launch` prints the runtime host. Prefer that host for the scenario.
- External `.app` bundles must already be installed with
  `xcrun simctl install <udid> /path/App.app`; `app launch` launches and
  attaches, not installs.
- If the task explicitly provides a local CLI or injector path, use that path;
  otherwise use the installed Loupe CLI/injector.
- The injector must be built for the simulator runtime. Do not use the host
  SwiftPM product at `.build/debug/libLoupeInjector.dylib` for iOS/tvOS
  Simulator apps; that macOS dylib can start the app without making Loupe
  reachable. Build the `LoupeInjector` scheme for `generic/platform=iOS
  Simulator` or `generic/platform=tvOS Simulator`, then point
  `LOUPE_INJECTOR_PATH` at
  `DerivedData/Build/Products/Debug-iphonesimulator/PackageFrameworks/LoupeInjector.framework/LoupeInjector`
  or the matching tvOS simulator product.
- If multiple simulators are booted, pass the explicit UDID to action commands.
- Unsigned real-app builds may crash before observation because of CloudKit, app
  groups, widgets, or entitlements. A documented external-only env bypass is
  acceptable when crash evidence is preserved.

## Physical Device

Real-device launch injection is not available. Debug builds link/embed the
dynamic `LoupeInjector` product; it depends on `LoupeKit` internally and starts
Loupe automatically when loaded. Do not include it in App Store release builds.

Use `ui` and `debug` with the selected host. Simulator HID commands remain
simulator-only; runtime tap works only for supported activation targets.

## macOS Host Runtime

Inject at process launch, then address the runtime by host:

```bash
open -n -F --env LOUPE_PORT=28749 --env LOUPE_BIND_HOST=127.0.0.1 \
  --env DYLD_INSERT_LIBRARIES=/path/to/libLoupeInjector.dylib /path/to/App.app
$LOUPE app info --host http://127.0.0.1:28749
```

- Prefer `app info --host`; `app current` may point at a previous runtime.
- `/health` alone is not proof. Some apps exit before `/snapshot` or block the
  main thread while `/health` still responds.
- Non-simulator macOS reports may not include screenshots.
- Runtime tap is AppKit control activation, not general pointer input. Custom
  editor, terminal, canvas, outline/table, and SwiftUI host views can correctly
  fail with `unsupported_activation_target`.

## watchOS Simulator

watchOS can capture runtime state, screenshots, logs, defaults, and probes.
There is no UIKit/AppKit walker, so pure SwiftUI can legitimately show only
`WKApplication`. Use sparse `.loupeProbe(...)` or `dev.loupe.probe` anchors and
prove routes with fresh report, screenshot, probe, log, default, or trace
evidence.

## visionOS Simulator

Reports can include full compositor screenshots while snapshots use app-window
coordinates. SwiftUI/RealityKit content may be screenshot-visible but
query-sparse; use hit-test, responder-chain, geometry/style, probes, logs,
defaults, and fresh screenshots/reports for proof.

## Runtime Selection

```bash
$LOUPE app list
$LOUPE app use <bundle-id-or-host>
$LOUPE app current
$LOUPE app info --host <runtime-host>
```

Use the printed launch host when possible. `app list` is inventory, not proof
that a runtime is still current; use `app cleanup` when old records get noisy.
