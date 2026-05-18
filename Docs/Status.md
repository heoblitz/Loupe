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
  subtree inspection, `/accessibility` for an accessibility tree that merges
  view-derived nodes with native `UIAccessibility` container traversal, and
  `/audit` for machine-readable layout issues.
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
- `LoupeKit` exposes runtime endpoints for logs and touch recording:
  `/logs`, `/runtime`, `/recording/start`, `/recording/stop`, and `/recording`.
- `loupe tap`, `swipe`, `drag`, `pinch`, `type`, `screenshot`, `record-start`,
  `record-stop`, `recording`, `logs`, and `replay` are available as CLI
  commands.
- Runtime actions currently delegate HID dispatch to AXe.
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
- `Examples/LoupeExample/run-runtime-e2e.sh` verifies the XCTest-free runtime
  smoke path when AXe is installed.
- `Examples/LoupeExample/run-axe-scenarios.sh` repeats AXe-backed navigation,
  accessibility-tree, UIKit component inspection, and layout audit scenarios.
- `Examples/LoupeExample/run-injected.sh` verifies injection, health, snapshot,
  and query.
- `Examples/LoupeExample` now includes `UILaunchStoryboardName` and
  `LaunchScreen.storyboard`, so it runs at modern simulator size instead of
  the legacy 320x480 compatibility viewport.
- The example app now includes navigation, a large table view, a detail screen,
  a pan gesture target, a UIKit component screen with scroll, collection,
  picker, tab, alert, and design fixtures, a mixed fixture tab controller with
  SwiftUI host, WebKit, keyboard-heavy form, and nested scroll screens, and a
  modal form.
- `testNavigationListFormAndGestures` verifies normal XCUITest navigation,
  table scrolling, form input, and gesture behavior.
- `run-loupe-driven-ui-test.sh` verifies the key proof: fetch Loupe snapshot,
  find nodes by `testID`, convert view frames to window coordinates, and execute
  XCUITest tap/drag actions against those coordinates.

## Current Limitation

Loupe now exposes initial CLI action commands:

```bash
loupe tap --test-id example.customer.24
loupe swipe --from 219,760 --to 219,190 --width 438 --height 954
loupe drag --from 88,420 --to 372,420 --width 438 --height 954
loupe inspect snapshot.json --test-id example.components.switch
loupe accessibility snapshot.json
loupe query snapshot.json --tree accessibility --test-id example.components.switch
loupe audit snapshot.json
loupe subtree snapshot.json --test-id example.components --depth 4
loupe wait-for-visible --test-id example.detail --timeout 5
loupe tap --test-id example.form.name
loupe type "Ada"
```

The low-level HID backend is delegated to AXe for now. Install AXe with
`brew install cameroncooke/axe/axe`, or install Loupe through the Homebrew
formula, which declares AXe as a dependency. `loupe pinch` keeps the intended
command shape, but AXe does not support pinch yet. A native `LoupeActionRunner`
HID backend is still future work.

Native accessibility traversal currently uses public in-app `UIAccessibility`
container APIs. It enriches UIKit and custom accessibility containers, but
SwiftUI inner `accessibilityIdentifier` values remain a known gap when neither
the app process nor AXe exposes them as addressable accessibility nodes.

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

The desired structure is:

```text
loupe CLI
  -> accessibility tree selector resolution for movement/input
  -> view tree selector resolution for UI/layout/style verification
  -> delegated AXe backend today
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
- AXe delegated backend: real simulator input without requiring XCTest as the
  public harness.
- `LoupeActionRunner` future target: native Loupe HID dispatch.
- `loupe` CLI: stable public commands and trace output.

## Next Work

1. Add native Loupe HID dispatch so action commands do not depend on AXe.
2. Extend accessibility coverage for SwiftUI inner semantic elements.
3. Add better selector scoring.
4. Add screenshot baseline diff helpers.
5. Expand layout/style assertions beyond the current audit checks.
6. Improve installation flow: Homebrew formula should package the CLI and
   injector, and the Codex skill should discover that Homebrew path.

## Verified Commands

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
Examples/LoupeExample/run-axe-scenarios.sh
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
