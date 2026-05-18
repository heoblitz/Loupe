# Loupe Test Plan

This plan tracks whether Loupe can support a repeated developer loop:
observe the app, act through the simulator, inspect exact UIKit state on demand,
and validate functional or design regressions without making XCTest the public
harness.

## Implemented

- Core unit tests use Swift Testing (`@Test`, `#expect`, `#require`).
- AXe-backed runtime action smoke:
  `Examples/LoupeExample/run-runtime-e2e.sh`
- AXe-backed repeated scenarios:
  `Examples/LoupeExample/run-axe-scenarios.sh`
- Bookmark app-style E2E scenario:
  `Examples/LoupeExample/run-bookmark-e2e.sh`
- Navigation pop by interactive edge gesture.
- Navigation push by Loupe selector tap.
- Navigation pop by Loupe ref tap.
- Routed fixtures for UIKit components, alerts, and mixed fixture tabs.
- Full-screen iPhone Simulator sizing through `LaunchScreen.storyboard`.
- Compact observation with interactive UIKit type/class identity.
- Separate view and accessibility trees:
  view tree is used for UIKit/layout/style validation, while accessibility tree
  is used first for selector-driven movement and input.
- Accessibility tree export and query:
  `loupe accessibility <snapshot.json>`, `loupe query --tree accessibility`,
  and `/accessibility`.
- Runtime `/accessibility` returns Loupe's view-derived accessibility tree by
  default, with native `UIAccessibility` container traversal kept behind
  `LOUPE_NATIVE_ACCESSIBILITY=1` while its simulator blocking behavior is
  stabilized.
- On-demand full node inspection:
  `loupe inspect <snapshot.json> --test-id <id>`
- Runtime inspection endpoint:
  `/inspect?testID=<id>`
- Bounded subtree inspection:
  `loupe subtree <snapshot.json> --test-id <id> --depth <n>` and
  `/subtree?testID=<id>&depth=<n>`
- Runtime waiting:
  `loupe wait-for-visible --test-id <id> --timeout <seconds>`,
  `loupe wait-for-gone --test-id <id>`, and
  `loupe wait-for-value --test-id <id> --key <path> --equals <value>`.
- Human-readable tree preview:
  `loupe tree [snapshot.json] --view|--accessibility --depth <n>`.
- Snapshot diff and trace summary:
  `loupe diff before-snapshot.json after-snapshot.json` reports appeared,
  disappeared, changed, and moved nodes; `loupe trace-summary <trace-dir>`
  summarizes action target, errors, logs, target crop, and snapshot diff.
- Design comparison:
  `loupe compare-design snapshot.json figma-export.json` compares exported
  design nodes to a Loupe snapshot by `testID`, role/text, and geometry.
- Skill installation:
  `loupe skills install` upserts the Loupe skill into existing Codex or Claude
  Code skill folders and skips missing clients.
- Runtime start wrapper:
  `loupe start --bundle-id <id> [--port <port>]` launches with injection and
  waits for the in-app Loupe server to answer `/runtime`.
- Cleanup:
  `loupe cleanup` prunes stale runtime records and trace bundles older than 7
  days; recordings are only pruned with `--recordings-older-than`.
- Runtime registry:
  `loupe runtimes` / `loupe apps` lists known simulator hosts and live state.
- Runtime identity handshake:
  `loupe runtime --udid <sim>` verifies that the contacted Loupe host belongs to
  the expected simulator before recorder commands use it.
- Injection communication:
  apps can post `dev.loupe.log` and `dev.loupe.viewMetadata` notifications to
  send custom logs and metadata without importing `LoupeKit`.
- Recorder replay loop:
  `loupe record start <alias>`, direct user or CLI interaction,
  `loupe record stop` saves `~/.loupe/recordings/<alias>.json`, app relaunch,
  then `loupe replay <alias> --host <url> --udid <sim>` uses recorded selector
  candidates before coordinate fallback.
- Basic action traces for public CLI actions:
  `--trace-dir <path>` saves before/after view snapshots, accessibility trees,
  runtime logs, screenshots, action records, and the resolved target query result
  around CLI actions.
- Failed runtime actions automatically save `error.json`, failure snapshot,
  accessibility tree, logs, screenshot, and action record under
  `/tmp/loupe-traces`.
- Action traces save `target-crop.png` when a resolved target frame is available.
- Basic layout audit:
  `loupe audit <snapshot.json>` and `/audit`
- Layout audit currently checks sibling overlap, child-outside-parent,
  duplicate test IDs, missing public interactive test IDs, small interactive
  targets, and low text contrast.
- UIKit component coverage for:
  labels, buttons, synthetic bar button items, switches, sliders, segmented
  controls, steppers, date pickers, page controls, progress views, activity
  indicators, image views, text fields, text views, scroll views, table views,
  collection views, picker views, tab bars, stack-backed rows, alerts, and
  styled design fixtures.
- Mixed fixture coverage for:
  a SwiftUI hosting screen, a `WKWebView`, a keyboard-heavy form, nested scroll
  views, and a full `UITabBarController` flow with synthetic `UITabBarItem`
  selectors.
- Bookmark app-style coverage for:
  tab bar navigation, list/detail navigation, favorites, search, add form text
  input, detail favorite state changes, `testID` tap, `ref` tap, text-tap
  rejection, automatic failure trace, selector inspection, and layout audit.
- Style capture for:
  background color, text color, border color, border width, corner radius,
  font name, and font size.

## Known Gaps

- `loupe pinch` is still unsupported by the AXe backend.
- `loupe tap` intentionally rejects text selectors; `testID`, `ref`, and
  coordinate taps remain in the public contract.
- `loupe audit` does not yet assert spacing, alignment, z-order intent,
  clipping, truncation, or typography rules.
- Compact observations expose UIKit identity, but component-specific properties
  intentionally require `inspect`.
- `inspect` returns `UIView`-common properties at `uiKit` top level and
  component-specific properties under nested objects such as `uiKit.stepper`,
  `uiKit.textField`, `uiKit.tabBar`, and `uiKit.webView`.
- Retry policies beyond explicit wait commands are not implemented yet.
- Native `UIAccessibility` traversal is opt-in and still needs guardrails before
  it can be part of the default runtime endpoint.
- Screenshot baseline diffing is not implemented yet.
- AXe is the only action backend. Native Loupe HID dispatch is still future
  work.
- SwiftUI movement/input selectors are intentionally limited to elements exposed
  through the accessibility tree. Loupe does not synthesize selectors from
  private SwiftUI view-tree implementation details.

## Reference Projects To Mine

- AXe: terminal-native simulator interaction and accessibility inspection.
- XcodeBuildMCP: agent-friendly Xcode, simulator lifecycle, logging, and UI
  automation workflows.
- WebDriverAgent/Appium XCUITest driver: long-running HTTP action runner model,
  selector semantics, and device compatibility lessons.
- Maestro and Detox: flow DSL, retry/wait ergonomics, and mobile-specific
  flake handling patterns.
- idb-based tools: lower-level simulator/device control and HID primitives.
