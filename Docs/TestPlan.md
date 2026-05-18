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
- Navigation push by Loupe selector tap.
- Navigation pop by interactive edge gesture.
- Navigation push/pop by tappable control.
- Full-screen iPhone Simulator sizing through `LaunchScreen.storyboard`.
- Compact observation with interactive UIKit type/class identity.
- Separate view and accessibility trees:
  view tree is used for UIKit/layout/style validation, while accessibility tree
  is used first for selector-driven movement and input.
- Accessibility tree export and query:
  `loupe accessibility <snapshot.json>`, `loupe query --tree accessibility`,
  and `/accessibility`.
- Runtime `/accessibility` merges Loupe's view-derived accessibility tree with
  native `UIAccessibility` container traversal for non-UIView accessibility
  elements, with the view tree as the fallback source of truth.
- On-demand full node inspection:
  `loupe inspect <snapshot.json> --test-id <id>`
- Runtime inspection endpoint:
  `/inspect?testID=<id>`
- Bounded subtree inspection:
  `loupe subtree <snapshot.json> --test-id <id> --depth <n>` and
  `/subtree?testID=<id>&depth=<n>`
- Runtime waiting:
  `loupe wait-for-visible --test-id <id> --timeout <seconds>`
- Basic action traces:
  `--trace-dir <path>` saves before/after view snapshots, accessibility trees,
  runtime logs, screenshots, action records, and the resolved target query result
  around CLI actions.
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
- Style capture for:
  background color, text color, border color, border width, corner radius,
  font name, and font size.

## Known Gaps

- `loupe pinch` is still unsupported by the AXe backend.
- `loupe audit` does not yet assert spacing, alignment, z-order intent,
  clipping, truncation, or typography rules.
- Compact observations expose UIKit identity, but component-specific properties
  intentionally require `inspect`.
- `inspect` returns `UIView`-common properties at `uiKit` top level and
  component-specific properties under nested objects such as `uiKit.stepper`,
  `uiKit.textField`, `uiKit.tabBar`, and `uiKit.webView`.
- Retry policies beyond explicit `wait-for-visible` polling are not implemented
  yet.
- Native `UIAccessibility` traversal depends on what the app process exposes
  through public accessibility APIs; some framework-provided semantic nodes may
  still require host-side accessibility tooling.
- Screenshot baseline diffing is not implemented yet.
- AXe is the only action backend. Native Loupe HID dispatch is still future
  work.
- SwiftUI is currently covered at the hosting-controller boundary plus any
  UIKit-backed controls exposed in the view tree. Inner SwiftUI
  `accessibilityIdentifier` values are not yet visible through Loupe's in-app
  traversal or AXe's current `describe-ui` output.

## Reference Projects To Mine

- AXe: terminal-native simulator interaction and accessibility inspection.
- XcodeBuildMCP: agent-friendly Xcode, simulator lifecycle, logging, and UI
  automation workflows.
- WebDriverAgent/Appium XCUITest driver: long-running HTTP action runner model,
  selector semantics, and device compatibility lessons.
- Maestro and Detox: flow DSL, retry/wait ergonomics, and mobile-specific
  flake handling patterns.
- idb-based tools: lower-level simulator/device control and HID primitives.
