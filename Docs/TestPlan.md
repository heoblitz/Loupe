# Loupe Test Plan

This plan tracks whether Loupe can support a repeated developer loop:
observe the app, act through the available platform backend, inspect exact
UIKit/AppKit state on demand, and validate functional or design regressions
without making XCTest the public harness.

## Post-Change Harness

Agents should run the repository-level verification command after code changes:

```bash
scripts/verify-agent-work.sh
```

That command is the default post-work gate and the `Post-change E2E` GitHub
Actions required check. It runs:

- `swift test`
- `swift build --configuration release --disable-sandbox --product loupe`
- `Examples/LoupeExample/run-injected.sh`
- `Examples/LoupeExample/run-runtime-e2e.sh`
- `Examples/LoupeExample/run-native-scenarios.sh`
- `Examples/LoupeExample/run-bookmark-e2e.sh`
- `scripts/verify-platform-builds.sh`
- `Examples/MacLoupeExample/run-macos-e2e.sh`
- `Examples/LoupeTVExample/run-tvos-runtime-e2e.sh`

If local simulator state blocks E2E, record the failing script, exit status,
and the generated `/tmp/loupe-*` logs or screenshots before handing work back.

## Design-to-Code Evaluation

This is a benchmark workflow, not Loupe's primary positioning; the same runtime
evidence should also support functional debugging and regression checks.

When evaluating whether Loupe improves implementation quality, use a blind
baseline instead of reusing the current agent's context.

Required setup:

- Start two fresh subagents without inherited conversation context.
- Give both agents the same design link, target screen, and app requirements.
- Give the Loupe agent only the Loupe CLI/skill as the extra capability.
- Give the baseline agent no Loupe CLI, snapshots, traces, view tree, or skill.
- Use separate work directories and simulator devices.
- Forbid both agents from reading previous `/tmp/loupe-*` comparison artifacts.

Score both outputs with the same artifacts:

- visual distance to the design reference
- view-tree structure for native text, image views, tab bars, scroll views, and
  layout/style metadata
- action traces for critical routes and scroll gestures
- runtime correctness, including whether fixed chrome is outside content scrolls
- runtime screen size and device-class correctness before visual scoring
- speed, command count, and amount of context needed

The Loupe path should improve the final result, not just produce more logs.
Treat the benchmark as failed when the Loupe output has worse visual distance
than the no-Loupe baseline and the extra view-tree evidence did not lead to a
concrete structural or interaction advantage. In that case, update the skill or
CLI feedback loop before claiming Loupe improves design implementation quality.

This benchmark is useful only when the Loupe result is produced from fresh
runtime evidence. A result produced from remembered fixes or prior screenshots
does not count as evidence that the CLI or skill improved agent performance.

## Implemented

- Core unit tests use Swift Testing (`@Test`, `#expect`, `#require`).
- Native HID runtime action smoke:
  `Examples/LoupeExample/run-runtime-e2e.sh`
- Native HID repeated scenarios:
  `Examples/LoupeExample/run-native-scenarios.sh`
- Bookmark app-style E2E scenario:
  `Examples/LoupeExample/run-bookmark-e2e.sh`
- Platform build coverage:
  `scripts/verify-platform-builds.sh`
- Linked macOS AppKit runtime E2E:
  `Examples/MacLoupeExample/run-macos-e2e.sh`
- tvOS Simulator runtime and remote press E2E:
  `Examples/LoupeTVExample/run-tvos-runtime-e2e.sh`
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
  `loupe ui accessibility <snapshot.json>`, `loupe ui query --tree accessibility`,
  and `/accessibility`.
- Runtime `/accessibility` returns Loupe's view-derived accessibility tree by
  default, with native `UIAccessibility` container traversal kept behind
  `LOUPE_NATIVE_ACCESSIBILITY=1` while its simulator blocking behavior is
  stabilized.
- On-demand full node inspection:
  `loupe ui node <snapshot.json> --test-id <id>`
- Runtime inspection endpoint:
  `/inspect?testID=<id>`
- Bounded subtree inspection:
  `loupe ui subtree <snapshot.json> --test-id <id> --depth <n>` and
  `/subtree?testID=<id>&depth=<n>`
- Runtime waiting:
  `loupe act wait visible --test-id <id> --timeout <seconds>`,
  `loupe act wait gone --test-id <id>`, and
  `loupe act wait value --test-id <id> --key <path> --equals <value>`.
- Human-readable tree preview:
  `loupe ui tree [snapshot.json] --view|--accessibility --depth <n>`.
- Snapshot diff and trace summary:
  `loupe debug trace diff before-snapshot.json after-snapshot.json` reports appeared,
  disappeared, changed, and moved nodes; `loupe debug trace summary <trace-dir>`
  summarizes action target, errors, logs, target crop, and snapshot diff.
- Design comparison:
  `loupe ui compare-design snapshot.json figma-export.json` compares exported
  design nodes to a Loupe snapshot by `testID`, role/text, and geometry.
- Skill installation:
  `loupe skills install` upserts the Loupe skill into existing Codex or Claude
  Code skill folders and skips missing clients.
- Runtime start wrapper:
  `loupe app launch --bundle-id <id> [--port <port>]` launches with injection and
  waits for the in-app Loupe server to answer `/runtime`.
- Cleanup:
  `loupe app cleanup` prunes stale runtime records and trace bundles older than 7
  days.
- Runtime registry:
  `loupe app list` lists known simulator hosts and live state.
- Runtime mutation:
  `loupe ui set --test-id <id> <property> <value>` posts a typed mutation to the
  injected server and reports whether the after snapshot reflects the
  allowlisted UIKit property change. Property mutations animate by default, and
  `--no-animate` verifies the immediate path. Layout-owned values may be
  restored by UIKit and must be judged by the effective state.
- Runtime mutation discovery:
  `loupe ui set --list` / `/mutations` exposes the active mutation property
  registry for agent planning.
- Runtime edit-to-code loop:
  `loupe ui set --output <mutation.json>`, `loupe ui node`, then
  `loupe ui reflect <mutation.json> --source <dir>` verifies a runtime edit and
  produces before/after summaries, hierarchy context, and source candidates for
  an agent-led code application step.
- Runtime identity handshake:
  `--udid <sim>` on runtime commands verifies that the contacted Loupe host belongs to
  the expected simulator before runtime commands use it.
- Injection communication:
  apps can post `dev.loupe.log` and `dev.loupe.viewMetadata` notifications to
  send custom logs and metadata without importing `LoupeKit`.
  `Examples/LoupeExample/run-injected.sh` verifies that the injected bridge
  captures an app-posted `dev.loupe.log`, that `loupe debug logs` can fetch it, and
  that view metadata is present in `loupe ui node` output.
- Basic action traces for public CLI actions:
  `--trace-dir <path>` saves before/after view snapshots, accessibility trees,
  runtime logs, screenshots, action records, and the resolved target query result
  around CLI actions.
- Scroll profiling:
  `loupe debug scroll` supports simulator gesture traces with `--from/--to` and
  runtime offset probes with `--delta` or `--to-offset` for linked/runtime
  platform examples.
- Failed runtime actions automatically save `error.json`, failure snapshot,
  accessibility tree, logs, screenshot, and action record under
  `/tmp/loupe-traces`.
- Action traces save `target-crop.png` when a resolved target frame is available.
- Basic layout audit:
  `loupe ui audit <snapshot.json>` and `/audit`
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

- `loupe ui audit` does not yet assert spacing, alignment, z-order intent,
  clipping, truncation, or typography rules.
- Compact observations expose UIKit identity, but component-specific properties
  intentionally require `loupe ui node`.
- `loupe ui node` returns `UIView`-common properties at `uiKit` top level and
  component-specific properties under nested objects such as `uiKit.stepper`,
  `uiKit.textField`, `uiKit.tabBar`, and `uiKit.webView`.
- Retry policies beyond explicit wait commands are not implemented yet.
- Native `UIAccessibility` traversal is opt-in and still needs guardrails before
  it can be part of the default runtime endpoint.
- Screenshot baseline diffing is not implemented yet.
- Native HID dispatch covers tap, drag, swipe, and US-keyboard text input.
- SwiftUI movement/input selectors are intentionally limited to elements exposed
  through the accessibility tree. Loupe does not synthesize selectors from
  private SwiftUI view-tree implementation details.
- Runtime mutation is strongest for text, color, visibility, layer styling, and
  control values. Frame and constraint edits are diagnostic unless the effective
  state confirms UIKit kept them.
