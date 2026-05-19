# Loupe Status

Last verified: 2026-05-18.

## Goal

Loupe is intended to become a Playwright-like harness for iOS Simulator apps:

1. Launch an app with observation enabled.
2. Capture a structured app-side view tree with stable selectors and custom
   metadata.
3. Give agents compact screen context instead of the entire tree.
4. Resolve specific nodes on demand.
5. Execute real simulator interactions such as tap, scroll, drag, swipe, and
   type.
6. Record enough traces, screenshots, snapshots, and logs to make failures
   reproducible.

`Docs/Goal.md` is the current goal contract for runtime E2E work.
`Docs/TestPlan.md` tracks implemented scenario coverage and known gaps.

Figma API integration is intentionally out of scope for the current phase. The
near-term visual goal is to support screenshot, layout, and style assertions
against known expectations or baselines.

## Harness Engineering Principles

The project direction follows the OpenAI harness engineering guidance from
`https://openai.com/index/harness-engineering/`:

- Build an environment where agents can inspect, act, and validate with normal
  engineering tools.
- Keep repository knowledge as the system of record. `AGENTS.md` should be a
  map, with deeper details stored in focused docs.
- Make the application legible to agents with stable structure, selectors,
  observations, traces, and mechanical feedback.
- Enforce boundaries and invariants in code and tests instead of relying only on
  prose instructions.
- Prefer short feedback loops that reproduce failures, apply changes, and verify
  outcomes.

For Loupe, this means the SDK captures high-quality app context, the host owns
actions and traces, and the CLI exposes small deterministic tools that agents can
compose.

## Verified

- SwiftPM package builds and tests pass. Core unit tests use Swift Testing.
- `LoupeKit` can expose `/health`, `/snapshot`, and `/observation` over
  localhost.
- `LoupeKit` can expose `/inspect?testID=...` for a full node with parent,
  sibling, and child summaries, `/subtree?testID=...&depth=...` for bounded
  subtree inspection, `/accessibility` for a view-derived accessibility tree,
  and `/audit` for machine-readable layout issues.
- `LoupeInjector` can be built as a simulator-only injected library.
- `loupe launch --inject` can launch the example app with
  `DYLD_INSERT_LIBRARIES` through `simctl`.
- `loupe query` can resolve nodes from a full snapshot by `testID`, text, role,
  or ref.
- `loupe accessibility` can print a view-derived accessibility tree, and
  `loupe query --tree accessibility` can resolve selector matches from it.
- `loupe inspect` can print a full node on demand so compact observations only
  need to carry object identity and refs.
- `loupe subtree` can print a bounded subtree rooted at a selector match.
- `loupe wait-for-visible` can poll `/snapshot` until a visible selector match
  appears.
- `loupe audit` can report sibling overlap, child-outside-parent, duplicate
  test IDs, missing public interactive test IDs, small interactive targets, and
  low text contrast from the captured view tree.
- `LoupeKit` snapshots now include structured UIKit and accessibility properties
  per node, including component-specific fields for labels, text fields,
  switches, sliders, steppers, segmented controls, date pickers, page controls,
  progress views, activity indicators, image views, picker views, and tab bars.
  `uiKit` keeps common `UIView` fields at the top level and nests object-specific
  fields under keys such as `control`, `textField`, `stepper`, `tabBar`, and
  `webView`.
- `LoupeKit` snapshots synthesize `UIBarButtonItem` nodes from navigation items
  so bar button identifiers such as `example.openComponents` are selectable
  even when UIKit does not expose the item as a normal view node.
- `LoupeKit` snapshots synthesize `UITabBarItem` nodes from actual tab bar
  control frames, so tab identifiers such as `example.fixtures.tab.web` are
  selectable without relying on private class-name string matching.
- `LoupeKit` exposes runtime endpoints for logs and identity:
  `/logs` and `/runtime`.
- `/runtime` includes a launch identity with bundle id, process id,
  `SIMULATOR_UDID`, simulator name, and a Loupe launch id.
- Injected apps can send logs and extra view metadata without importing
  `LoupeKit` by posting `dev.loupe.log` and `dev.loupe.viewMetadata`
  notifications. See `Docs/RuntimeCommunication.md`.
- `loupe tap`, `swipe`, `drag`, `pinch`, `type`, `screenshot`, and `logs` are
  available as CLI commands.
- `loupe runtime` and `logs` accept
  `--udid` and validate that the connected Loupe host belongs to that simulator
  before reading runtime state.
- `loupe start` / `loupe launch --inject` assigns an available localhost port
  when `LOUPE_PORT` is not provided, records the UDID+bundle mapping under
  `~/.loupe/runtimes`, and waits for the injected runtime before returning.
  Later CLI commands can resolve the host from `--udid` or `--bundle-id`.
- `loupe fetch`, runtime fetches, screenshots, and native HID actions have
  bounded timeouts.
- `loupe runtimes` / `loupe apps` lists known injected runtime hosts from
  `~/.loupe/runtimes` and probes live runtime state when available.
- `loupe tree` prints a human-readable view-tree or accessibility-tree prefix
  from either a saved snapshot or a live injected runtime.
- `loupe diff` summarizes appeared, disappeared, changed text/value/state, and
  moved nodes between two full snapshots.
- `loupe trace-summary` turns a trace bundle into a short action timeline with
  target, error, logs, target crop path, and before/after snapshot diff.
- `loupe compare-design` compares a snapshot with an exported Figma-style JSON
  by `testID`, role/text, then geometry, and reports missing, unexpected, frame,
  color, corner radius, and font deltas.
- `loupe skills install` upserts `skills/loupe` into existing Codex or Claude
  Code skill folders.
- `loupe start` wraps `loupe launch --inject` and starts the in-app Loupe
  runtime server without requiring users to think about `DYLD_INSERT_LIBRARIES`.
- `loupe cleanup` removes stale runtime host records and old trace bundles.
- `loupe set` posts to the injected `/mutate` endpoint and can update
  allowlisted UIKit view properties such as frame, alpha, colors, text,
  accessibility fields, layer styling, and common control values.
- `loupe constraints`, `set-constraint`, and `deactivate-constraint` expose
  captured Auto Layout constraints and verify the effective constant, priority,
  or active state after runtime mutation.
- `loupe set --list` and `/mutations` list the runtime mutation registry.
  Mutation support is grouped by UIKit family so new components can be added
  without expanding a single hard-coded switch.
- `loupe reflect <mutation-response.json> --source <dir>` converts a verified
  runtime mutation into before/after summaries, target hierarchy context, and
  source candidates. This supports the intended view -> runtime edit -> verify
  -> code change loop without directly editing app code.
- Runtime actions dispatch tap, drag, swipe, and type through Loupe's native
  host-side HID backend.
- Selector-based runtime actions resolve through the accessibility tree first,
  using a valid accessibility activation point when it lies inside the element
  frame, then falling back to the accessibility frame center, then to the view
  tree only if no accessibility match exists.
- Runtime selector resolution, waits, and action traces fetch `/accessibility`
  first, so they can use native accessibility elements when LoupeKit can see
  them and fall back to the snapshot-derived tree when it cannot.
- `--trace-dir` writes `action-target.json` before dispatch and includes the
  resolved target query result in action records, making selector choice,
  coordinates, ref, role, text, visibility, and source tree auditable.
- `--trace-dir` also captures `before-logs.json` and `after-logs.json` from the
  injected SDK `/logs` endpoint.
- Failed runtime actions now auto-save a trace under `/tmp/loupe-traces` even
  when `--trace-dir` was not provided.
- Successful action traces save `target-crop.png` when Loupe resolved a framed
  target node.
- `loupe wait-for-gone` and `loupe wait-for-value` cover disappearance and
  nested property checks in addition to `wait-for-visible`.
- `Examples/LoupeExample/run-runtime-e2e.sh` verifies the XCTest-free runtime
  smoke path.
- `Examples/LoupeExample/run-native-scenarios.sh` repeats native HID tap, gesture,
  accessibility-tree, UIKit component inspection, and layout audit scenarios.
- `Examples/LoupeExample/run-bookmark-e2e.sh` verifies a bookmark app-style
  tabbed list/detail/favorites/search/add flow with text-tap rejection,
  automatic failure trace, `testID` tap, `ref` tap, type, wait-for-value,
  wait-for-gone, inspect, observation, and audit checks.
- `Examples/LoupeExample/run-injected.sh` verifies injection, health, snapshot,
  and query.
- `Examples/LoupeExample` now includes `UILaunchStoryboardName` and
  `LaunchScreen.storyboard`, so it runs at modern simulator size instead of
  the legacy 320x480 compatibility viewport.
- The example app now includes navigation, a large table view, a detail screen,
  a pan gesture target, a UIKit component screen with scroll, collection,
  picker, tab, alert, and design fixtures, a mixed fixture tab controller with
  SwiftUI host, WebKit, keyboard-heavy form, and nested scroll screens, a
  bookmark app-style tabbed list/detail/favorites/search/add route with detail
  favorite state changes, and a modal form.
- `testNavigationListFormAndGestures` verifies normal XCUITest navigation,
  table scrolling, form input, and gesture behavior.
- `run-loupe-driven-ui-test.sh` verifies the key proof: fetch Loupe snapshot,
  find nodes by `testID`, convert view frames to window coordinates, and execute
  XCUITest tap/drag actions against those coordinates.

## Current Limitation

Loupe now exposes initial CLI action commands:

```bash
loupe tap --test-id example.customer.24
loupe tap --ref n83
loupe tap --x 201 --y 274 --udid booted
loupe swipe --from 219,760 --to 219,190 --width 438 --height 954
loupe drag --from 88,420 --to 372,420 --width 438 --height 954
loupe inspect snapshot.json --test-id example.components.switch
loupe accessibility snapshot.json
loupe query snapshot.json --tree accessibility --test-id example.components.switch
loupe audit snapshot.json
loupe subtree snapshot.json --test-id example.components --depth 4
loupe tree --udid booted --accessibility --depth 2
loupe compare-design snapshot.json figma-export.json
loupe diff before-snapshot.json after-snapshot.json
loupe trace-summary /tmp/loupe-trace
loupe skills install --target codex
loupe start --bundle-id dev.loupe.example --device booted
loupe cleanup --dry-run
loupe set --list
loupe set --test-id example.components.label text "Runtime edited" --output /tmp/loupe-set.json
loupe reflect /tmp/loupe-set.json --source Examples/LoupeExample/LoupeExample
loupe set --test-id example.design.card backgroundColor --color '#ff3366'
loupe wait-for-visible --test-id example.detail --timeout 5
loupe wait-for-gone --test-id example.loading --timeout 5
loupe wait-for-value --test-id example.components.switch --key uiKit.switch.isOn --equals true
loupe type "Ada"
```

The low-level HID backend is implemented inside Loupe with CoreSimulator and
SimulatorKit private framework calls. The Homebrew formula does not install a
separate action tool. `loupe pinch` keeps the intended command shape, but pinch
dispatch is still future work.

Native accessibility traversal through public in-app `UIAccessibility` container
APIs is currently opt-in with `LOUPE_NATIVE_ACCESSIBILITY=1`; the default
runtime path uses the view-derived accessibility tree because native traversal
can block the app main thread on current simulators. SwiftUI inner
`accessibilityIdentifier` values are intentionally selector-usable only when the
app process exposes them as addressable accessibility nodes.

The legacy action proof is implemented in
`Examples/LoupeExample/LoupeExampleUITests/LoupeExampleUITests.swift` using
`XCUIApplication`, `XCUICoordinate`, and snapshots fetched from Loupe. This is a
legacy proof, not the desired product architecture.

## Action Strategy

Do not make app-internal `UIEvent` synthesis the main strategy. It is fragile on
iOS, depends on private behavior, and does not match how user-visible simulator
interactions are normally driven.

The public Loupe E2E path should be runtime-driven: a user or agent should be
able to launch an app, fetch observations, and execute `tap`, `swipe`, `drag`,
and `type` through Loupe commands without creating or running XCTest cases.
Tap-by-text remains out of the public contract because text is ambiguous and
fragile.

The desired structure is:

```text
loupe CLI
  -> accessibility tree selector resolution for movement/input
  -> view tree selector resolution for UI/layout/style verification
  -> native Loupe HID backend
  -> native runtime action runner process later
    -> fetch Loupe snapshot
    -> derive view tree and accessibility tree
    -> resolve node by ref/testID/text/role from the appropriate tree
    -> compute screen/window coordinate
    -> execute real simulator input
    -> capture after snapshot, accessibility tree, screenshot, and action log
```

This keeps observation and action separated:

- `LoupeKit` / `LoupeInjector`: app-side observation and metadata.
- `LoupeCore`: view tree models, accessibility tree models, selectors, refs,
  geometry, query, compact context.
- Native Loupe HID backend: real simulator input without requiring XCTest as the
  public harness.
- `loupe` CLI: stable public commands and trace output.

## Next Work

1. Expand native Loupe HID dispatch to pinch and hardware-button events.
2. Extend accessibility coverage for SwiftUI inner semantic elements.
3. Add better selector scoring.
4. Add screenshot baseline diff helpers.
5. Expand layout/style assertions beyond the current audit checks.
6. Improve installation flow: Homebrew formula should package the CLI and
   injector, and the Codex skill should discover that Homebrew path.

## Verified Commands

2026-05-19 local note: the code-level checks below pass after embedding the
native HID backend. `run-bookmark-e2e.sh` was re-run against iOS 26.3; the app
could install and Loupe runtime could answer, but local CoreSimulator launch
state regressed into `bootstatus` waits (`AddressBookLegacy.migrator` /
`Waiting on System App`) and `SimLaunchHost.arm64` SIGBUS reports. The harness
now fails fast around boot/install and records screenshots/logs instead of
hanging, but this local simulator state needs a clean runtime/device before the
bookmark flow can be re-validated end to end.

```bash
swift test
```

```bash
Examples/LoupeExample/run-injected.sh
```

```bash
Examples/LoupeExample/run-runtime-e2e.sh
```

```bash
Examples/LoupeExample/run-native-scenarios.sh
```

```bash
Examples/LoupeExample/run-bookmark-e2e.sh
```

```bash
xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:LoupeExampleUITests/LoupeExampleUITests/testNavigationListFormAndGestures \
  test
```

```bash
Examples/LoupeExample/run-loupe-driven-ui-test.sh
```
