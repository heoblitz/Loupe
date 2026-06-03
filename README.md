<p align="center">
  <img src="Docs/Assets/loupe-wordmark.svg" alt="Loupe" width="360">
</p>

A runtime diagnostic CLI that gives agents inspectable app state through small
primitives and skill-driven workflows.

Loupe lets LLM agents inspect, interact with, and verify behavior in running
Apple-platform apps through view hierarchies and properties, accessibility
metadata, screenshots, logs, network/state evidence, and host-visible input.

## Demo

<img width="1051" height="806" alt="loupe" src="https://github.com/user-attachments/assets/4a079742-996d-46ab-b5b4-7eedc618fa7e" />

<details>
<summary>Video</summary>

<video src="https://github.com/user-attachments/assets/8bdc57f4-f673-480c-b970-535cfc96012c" controls width="720"></video>

</details>

## Install

```bash
brew tap heoblitz/loupe https://github.com/heoblitz/Loupe.git
brew install loupe
```

Install the Loupe skill for agent workflows:

```bash
loupe skills install
```

## Environment

Loupe currently supports injected iOS Simulator apps plus linked LoupeKit
runtimes for macOS AppKit apps and tvOS Simulator apps. The command interface is
organized around targets and capabilities so platform support can expand without
turning every platform feature into a new top-level command.

Requirements:

- macOS 14 or later.
- Xcode with the needed iOS and tvOS Simulator runtimes installed.

Xcode and simulator versions can affect runtime injection, native HID input, and
platform-specific runtime behavior.

Loupe chooses an available localhost port for injected apps and records the
runtime. Use `--bundle-id`, `--udid`, or `loupe target use <bundle-id>` to
select the target app instead of hard-coding a host port.

## Quick Start

For agent workflows, start with this context:

```text
Use Loupe as the runtime context for this app. Inspect view and accessibility trees, collect runtime evidence, act through host-visible input when supported, and verify behavior with traces before editing code.
```

For direct CLI control:

```bash
loupe runtime start --bundle-id com.example.App --device <iPhone simulator UDID>
loupe target list
loupe target use com.example.App
loupe target current
```

Existing flat commands such as `loupe start`, `loupe tap`, and `loupe tree`
remain as compatibility aliases. New workflows should prefer the grouped
interface:

```text
target   Select the current runtime target.
runtime  Start, list, select, and query injected runtimes.
observe  Capture screenshots, trees, maps, and raw runtime data.
inspect  Query or inspect nodes and paint stacks.
act      Dispatch input and wait for UI state.
ui       Audit, mutate, and compare UI structure.
  trace    Explore, summarize, and diff action traces.
debug   Read logs, network events, and reference evidence.
state   Inspect defaults, flags, and keychain metadata.
env     Change runtime environment such as appearance.
perf    Run lightweight runtime performance probes.
skills   Install Loupe workflow skills.
```

## How Loupe Answers Runtime Questions

Loupe keeps the CLI small and lets skills compose commands into platform-aware
diagnostic loops. These are Loupe-native versions of common agent questions:

| Question | Loupe loop |
| --- | --- |
| Why is this list empty? | `observe` the screen, inspect the list node, fetch app-authored `debug network` and `debug console` evidence, then read relevant `state flags`. |
| What still references this service? | Run `debug object-graph DeviceActuationService` to summarize app-authored owner -> target evidence. Loupe does not claim private heap graph traversal. |
| Is dark mode hiding text? | Set `env appearance dark`, capture a fresh snapshot, and run `ui audit --kind lowTextContrast`. |
| Why does this button not respond? | Run `ui hit-test` at the point, inspect the `ui responder-chain`, then compare accessibility and visible view state. |
| Is this scroll hitching? | Run `perf scroll` with a trace directory for simulator gestures, or `--delta`/`--to-offset` for a runtime offset probe, then verify elapsed time and offset deltas. |
| Did logout clear secrets? | Use `state keychain list` before and after the app's logout flow and assert the expected items are gone. |
| Does the old feature-flag flow still work? | Change `state flags`, reload or relaunch the runtime, act through the old flow, and diff the resulting trace. |

The examples verify these primitives across iOS Simulator, macOS, and tvOS where
the platform backend supports them. iOS Simulator verifies native HID scroll
profiling; linked macOS and tvOS runtimes verify the runtime offset profiling
mode without claiming host HID scroll input.

Run the platform examples directly when checking this support:

```bash
scripts/verify-platform-builds.sh
Examples/MacLoupeExample/run-macos-e2e.sh
Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
```

## How Loupe Differs From Xcode MCP Tooling

[Apple's Xcode MCP bridge](https://developer.apple.com/documentation/xcode/giving-external-agents-access-to-xcode)
and tools such as [XcodeBuildMCP](https://www.xcodebuildmcp.com/docs) help
agents operate the Apple development toolchain: discover projects, build, test,
launch, manage simulators, inspect build output, and access Xcode or Apple
documentation context.

Loupe sits inside the running app. It captures runtime UI structure, framework
properties, accessibility state, screenshots, logs, app-authored network events,
defaults/flags/keychain metadata, reference evidence, and action traces. Use
Xcode tooling to build and launch the app; use Loupe to answer what is actually
on screen, what runtime state the app exposed, what changed after an action, and
why a visible behavior failed.

## Inspect Runtime UI

Use `observe capture` when you need a screenshot and UI structure together:

```bash
loupe observe capture --bundle-id com.example.App --output loupe-report
loupe observe compact loupe-report/snapshot.json
loupe observe screen loupe-report/snapshot.json --limit 80
loupe observe tree loupe-report/snapshot.json --accessibility --depth 3
loupe observe tree loupe-report/snapshot.json --view --depth 3
loupe inspect node loupe-report/snapshot.json --test-id checkout.payButton
```

Use the accessibility tree for text discovery and action targets. Use the view
tree for layout, UIKit properties, style, mutation refs, and design checks. Use
`inspect paint` when a visual change appears hidden by a same-frame child or
overlay:

```bash
loupe inspect paint loupe-report/snapshot.json --point 201,319
```

## Act and Explore

```bash
loupe act tap --udid <UDID> --test-id checkout.payButton --trace-dir /tmp/loupe-tap --expect-visible checkout.confirmation
loupe act tap --udid <UDID> --snapshot loupe-report/snapshot.json --ref n83
loupe act tap --udid <UDID> --x 201 --y 274 --width 438 --height 954
loupe act swipe --udid <UDID> --from 220,760 --to 220,190 --trace-dir /tmp/loupe-swipe
loupe act tap --udid <UDID> --test-id checkout.nameField
loupe act type "Ada" --udid <UDID>
```

A swipe verifies scroll offset changes when Loupe can identify a scrollable
target. For quick route discovery:

```bash
loupe trace explore --bundle-id com.example.App --limit 5 --trace-dir /tmp/loupe-routes --output /tmp/loupe-routes.json --json
```

Review action evidence:

```bash
loupe trace summary /tmp/loupe-tap
loupe trace diff /tmp/loupe-tap/before-snapshot.json /tmp/loupe-tap/after-snapshot.json --changed-only
```

## Debug Runtime State

Keep higher-level diagnosis in skills, but compose it from a small command
surface. For an empty list, gather UI state, app logs, network evidence, and
feature flags:

```bash
loupe observe fetch /snapshot --host <runtime-host> --output /tmp/loupe-snapshot.json
loupe debug network --host <runtime-host> --output /tmp/loupe-network.json
loupe debug console --host <runtime-host> --output /tmp/loupe-logs.json
loupe inspect query /tmp/loupe-snapshot.json --test-id customers.list
loupe state flags get new-nav --host <runtime-host>
```

For visual, responder, storage, and regression checks:

```bash
loupe env appearance dark --host <runtime-host>
loupe ui audit /tmp/loupe-snapshot.json --json
loupe ui hit-test --point 201,437 --host <runtime-host>
loupe ui responder-chain --test-id login.button --host <runtime-host>
loupe state keychain list --host <runtime-host>
loupe state flags set new-nav --bool false --host <runtime-host>
```

For scroll investigation:

```bash
loupe perf scroll --from 220,760 --to 220,190 --udid <UDID> --host <runtime-host> --trace-dir /tmp/loupe-scroll --output /tmp/loupe-scroll.json
loupe trace summary /tmp/loupe-scroll
```

`debug network` records app-authored network events, so apps should call
`Loupe.recordNetwork(...)` or post the `dev.loupe.network` bridge notification
where automatic URL loading interception is not available. `debug refs` records
app-authored ownership evidence through `Loupe.recordReference(...)` or the
`dev.loupe.reference` bridge notification; `debug object-graph <target>`
summarizes those records into `owners`, `nodes`, and `edges`. Graph `edges` and
`owners` include the original `evidenceID`, `kind`, `label`, `metadata`, and
`timestamp` so a leak/debug answer can point back to the exact app-authored
record. `debug heap --target` uses the same app-authored evidence summary; it
is not private heap traversal.
`perf scroll` records elapsed time and scroll offset deltas;
frame-level hitch classification still requires deeper instrumentation.

## Runtime Diagnostic Experiments

Runtime mutation is optional. Use it for quick design/debug experiments on
supported UIKit properties, not as the guaranteed path for every UI change.
Text, colors, alpha, hidden state, layer styling, and common control values are
usually better targets than layout-owned frame changes.

```bash
loupe ui mutations --udid <UDID> --test-id checkout.card
loupe ui set --udid <UDID> --test-id checkout.title text "Runtime title" --output mutation.json
loupe ui set --udid <UDID> --test-id checkout.card backgroundColor --color '#ff3366' --output mutation.json
loupe ui set --udid <UDID> --test-id checkout.card frame --rect 20,120,220,80 --no-animate --output mutation.json
loupe ui reflect mutation.json --source ./Sources
```

Runtime property mutations animate by default. Pass `--no-animate` when you need
immediate state for verification. Treat frame and constraint changes as
diagnostic probes unless the effective value confirms UIKit kept the change.

For Auto Layout:

```bash
loupe ui constraints --udid <UDID> --test-id checkout.card --json
loupe ui set-constraint --udid <UDID> --id c0x123 constant 120
loupe ui deactivate-constraint --udid <UDID> --id c0x123
```

Loupe reports requested and effective values so layout-owned changes are visible
instead of silently accepted.

## Documentation

- [Goal](Docs/Goal.md)
- [Status](Docs/Status.md)
- [Test Plan](Docs/TestPlan.md)
- [Runtime Communication](Docs/RuntimeCommunication.md)
- [Architecture Notes](Docs/LoupePlan.md)
- [Figma Comparison](Docs/FigmaComparison.md)
- [Homebrew Distribution](Docs/Homebrew.md)
- [Development Homebrew Overlay](Docs/DevHomebrewOverlay.md)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for local verification and pull request
checks.

## Inspiration

Loupe's simulator inspection and action direction is inspired by
[AXe](https://github.com/cameroncooke/AXe),
[Baguette](https://github.com/tddworks/baguette), and
[Pepper](https://github.com/skwallace36/Pepper). Loupe treats those projects as
related work, not as an API template: its workflows stay skill-driven and its
CLI is built around stable observe, act, inspect, UI, trace, and runtime
primitives.
