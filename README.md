<p align="center">
  <img src="Docs/Assets/loupe-wordmark.svg" alt="Loupe" width="360">
</p>

Loupe is a runtime inspection and action harness for iOS Simulator apps.

It gives agents and developers live evidence from a running app: UI and
accessibility trees, screenshots, logs, network activity, runtime state, input
traces, and focused UIKit/AppKit diagnostics.

iOS Simulator is the main path today, with additional checked support for tvOS
Simulator, macOS, watchOS Simulator, visionOS Simulator builds, and debug-linked
physical iOS device flows.

Use Loupe when you need to answer:

- What is actually on screen?
- Which view, accessibility element, or runtime state changed after an action?
- Why did this UI render, fail to update, or receive the wrong data?
- Did a runtime experiment really take effect?

## Install

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew install loupe
loupe skills install
```

## Quick Start

Launch an iOS Simulator app with Loupe injected:

```bash
loupe app launch --bundle-id <bundle-id> --device <simulator-udid> --inject
loupe ui report --bundle-id <bundle-id> --output loupe-report
loupe ui compact loupe-report/snapshot.json
loupe ui node loupe-report/snapshot.json --test-id checkout.payButton
```

Act on the app and keep a trace:

```bash
loupe act tap --udid <simulator-udid> --test-id checkout.payButton --trace-dir /tmp/loupe-tap
loupe debug trace summary /tmp/loupe-tap
loupe debug trace diff /tmp/loupe-tap/before-snapshot.json /tmp/loupe-tap/after-snapshot.json --changed-only
```

For agent workflows, a compact starting prompt is:

```text
Use Loupe as runtime evidence for this app. Inspect view and accessibility trees, collect logs/state/network evidence, act only through supported Loupe actions, and verify changes with traces before editing code.
```

## Demo

<img width="1051" height="806" alt="loupe" src="https://github.com/user-attachments/assets/4a079742-996d-46ab-b5b4-7eedc618fa7e" />

<details>
<summary>Video</summary>

<video src="https://github.com/user-attachments/assets/8bdc57f4-f673-480c-b970-535cfc96012c" controls width="720"></video>

</details>

## Supported Platforms

Loupe currently supports these surfaces:

- iOS Simulator: injection, UI snapshots, accessibility, native input, traces,
  diagnostics, and runtime mutation probes.
- tvOS Simulator: injection, UI snapshots, accessibility, remote input,
  diagnostics, and traces.
- macOS: linked runtime snapshots, actions, diagnostics, and mutation probes.
- watchOS Simulator: registered-probe runtime coverage.
- visionOS Simulator: LoupeKit and LoupeInjector build compatibility.
- Physical iOS devices: debug-only linked LoupeInjector runtime over HTTP.

The iOS Simulator path is the most complete one. Other platforms expose the
checked subset listed above.

Physical-device support is for development builds only. Do not include Loupe in
App Store release builds.

## Attachment Modes

Simulator apps do not need a Loupe dependency:

```bash
loupe app launch --bundle-id <bundle-id> --inject
```

Physical-device apps need a debug-only dependency:

1. Add the Swift package product `LoupeInjector` to the app's Debug target.
2. Keep it dynamic and set it to Embed & Sign.
3. Keep `LD_RUNPATH_SEARCH_PATHS` including `@executable_path/Frameworks`.
4. Exclude Loupe from release builds.

Do not call `LoupeServer.start()` from the app for this path. The dynamic
`LoupeInjector` library starts Loupe automatically when it loads.

For local-network inspection, launch with `--linked --bind-host 0.0.0.0 --host
http://<device-ip>:<port>`. `--inject` is simulator-only.

## CLI Shape

The main CLI groups are:

```text
app     Launch, select, list, and inspect app runtimes.
ui      Capture UI evidence, inspect nodes, audit layout, and run UI probes.
act     Dispatch input and wait for UI state.
debug   Read diagnostic evidence, state, traces, and scroll profiles.
skills  Install Loupe workflow skills.
```

Loupe chooses an available localhost port for injected apps and records the
runtime. Use `--bundle-id`, `--udid`, or `loupe app use <bundle-id>` instead of
hard-coding a host port.

## Inspect UI

Use `ui report` when you need a screenshot and UI structure together:

```bash
loupe ui report --bundle-id <bundle-id> --output loupe-report
loupe ui tree loupe-report/snapshot.json --accessibility --depth 3
loupe ui tree loupe-report/snapshot.json --view --depth 3
loupe ui query loupe-report/snapshot.json --test-id checkout.payButton
loupe ui node loupe-report/snapshot.json --test-id checkout.payButton
```

Use the accessibility tree for text discovery and action targets. Use the view
tree for layout, UIKit/AppKit properties, style, mutation refs, and design
checks.

SwiftUI support is intentionally explicit. Loupe does not synthesize selectors
from private SwiftUI internals. Use accessibility identifiers for actions, and
use probes when an agent needs a durable region target:

- Apps that import `LoupeKit` can use the public `.loupeProbe(...)` modifier.
- Injected or no-import apps should use a local helper with a different name,
  such as `.localLoupeProbe(...)`, so it is not confused with the public API.
- No-import helpers can use a view-backed probe for UIKit/AppKit-style trees, or
  post measured `dev.loupe.probe` bounds when a synthetic probe is enough.
  Synthetic probes are queryable evidence, not runtime activation targets.

## Act And Trace

```bash
loupe act tap --udid <simulator-udid> --test-id checkout.payButton --trace-dir /tmp/loupe-tap --expect-visible checkout.confirmation
loupe act tap --udid <simulator-udid> --snapshot loupe-report/snapshot.json --ref n83
loupe act swipe --udid <simulator-udid> --from 220,760 --to 220,190 --trace-dir /tmp/loupe-swipe
loupe act type "Ada" --udid <simulator-udid>
```

Action traces include before/after snapshots, accessibility trees, logs,
screenshots, action records, diffs, and target crops when available.

For quick route discovery:

```bash
loupe debug trace explore --bundle-id <bundle-id> --limit 5 --trace-dir /tmp/loupe-routes --output /tmp/loupe-routes.json --json
```

## Debug Runtime State

Loupe can collect app-authored and runtime evidence for common failure modes:

```bash
loupe debug logs --host <runtime-host> --output /tmp/loupe-logs.json
loupe debug network --host <runtime-host> --output /tmp/loupe-network.json
loupe debug flags get new-nav --host <runtime-host>
loupe debug keychain list --host <runtime-host>
loupe ui audit loupe-report/snapshot.json
loupe ui hit-test --point 201,437 --host <runtime-host>
loupe ui responder-chain --test-id login.button --host <runtime-host>
```

Network evidence comes from LoupeKit fixture URLProtocol hooks plus explicit
app-authored events. It is not a general packet sniffer. Reference,
object-graph, leak, flag, defaults, keychain, appearance, and scroll
diagnostics are intended for development builds.

## Runtime Mutation Probes

Runtime mutation is optional. Use it for quick design and debugging
experiments, then verify the effective state before changing source.

```bash
loupe ui mutations --udid <simulator-udid>
loupe ui set --udid <simulator-udid> --test-id checkout.title text "Runtime title" --output mutation.json
loupe ui set --udid <simulator-udid> --test-id checkout.card backgroundColor --color '#ff3366' --output mutation.json
loupe ui reflect mutation.json --source ./Sources
```

Frame, constraint, and list self-sizing edits are diagnostic probes unless the
after snapshot confirms UIKit kept the effective value. For iOS 16+
collection/table cells, `--try-self-sizing` only attempts UIKit self-sizing
invalidation when Loupe can identify a supported sizing context. If the response
reports `already-enabled` or a skip reason, do not retry the same container.

## Loupe And Xcode Tooling

Xcode tooling builds, tests, launches, manages devices, and surfaces compiler or
project state. Loupe answers runtime questions from inside the app process:
what rendered, what app state was exposed, what changed after input, and which
evidence explains a visible behavior.

They are complementary. Use Xcode tooling to prepare and launch the app; use
Loupe to inspect and verify the running UI.

## Documentation

- [Goal](Docs/Goal.md)
- [Status](Docs/Status.md)
- [Test Plan](Docs/TestPlan.md)
- [Runtime Communication](Docs/RuntimeCommunication.md)
- [Architecture Notes](Docs/LoupePlan.md)
- [Figma Comparison](Docs/FigmaComparison.md)
- [Open-Source App Validation](Docs/OpenSourceAppValidation.md)
- [Homebrew Distribution](Docs/Homebrew.md)
- [Development Homebrew Overlay](Docs/DevHomebrewOverlay.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local verification and pull request
checks.

## Inspiration

Loupe's simulator inspection and action direction is inspired by
[AXe](https://github.com/cameroncooke/AXe),
[Baguette](https://github.com/tddworks/baguette), and
[Pepper](https://github.com/skwallace36/Pepper).

<details>
<summary>Special thanks to Pepper</summary>

Loupe started with a UI-focused runtime inspection and interaction direction.
Pepper was especially helpful in shaping how Loupe expands that workflow into
debug diagnostics such as network evidence, runtime state, storage, traces, and
platform-specific runtimes.

</details>
