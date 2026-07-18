# Loupe Agent Guide

This repository is a SwiftPM/Xcode prototype for Loupe, an Apple-platform
runtime inspection, diagnostic, and action harness.

Use this file as a map, not as a full manual. Keep deeper project state in
`Docs/Status.md` and product direction in `Docs/LoupePlan.md`.

## Current Shape

- `Sources/LoupeCore`: snapshot models, accessibility tree models, compact
  observations, queries, inspection, layout audit, simctl helpers, injector path
  resolution.
- `Sources/LoupeKit`: linked or injected in-app SDK and localhost observation
  server for Apple-platform runtimes.
- `Sources/LoupeInjection`: simulator-only injected library that starts
  `LoupeServer`.
- `Sources/LoupeCLI`: host CLI for fetch, compact, query, inspect, audit,
  launch, doctor, runtime actions, and injector path lookup.
- `Examples/LoupeExample`: UIKit simulator app used to prove injection,
  snapshotting, and coordinate resolution for UI actions.
- `Examples/MacLoupeExample`: linked AppKit runtime used to prove macOS
  snapshots, accessibility, diagnostics, state, and layout audit coverage.
- `Examples/LoupeTVExample`: tvOS Simulator runtime used to prove view-tree
  coverage, remote press actions, focus state, diagnostics, and state flows.
- `skills/loupe`: Codex skill source for Loupe workflows.

## Architecture Rules

- LoupeKit observes app state. It should not be the primary place where touch
  events are synthesized.
- Runtime E2E should be driven by the Loupe CLI or a host runner, not by
  `xcodebuild test`, XCTest cases, or a test bundle as the public harness.
- User actions should be executed from the host side by a simulator action
  backend that consumes Loupe snapshots and emits real simulator UI input.
- Use the view tree for UI/layout/style validation. Use the accessibility tree
  first for movement and input; selector actions should only fall back to view
  frames when no accessibility match exists.
- For design-to-code evaluation, keep Loupe evidence honest: compare against a
  no-Loupe baseline with fresh subagents that do not inherit prior workspace
  context or `/tmp` artifacts. The Loupe path should prove quality with view
  tree inspection, screenshots, and action traces, not with remembered fixes.
- The CLI currently exposes `tap`, `swipe`, `drag`, and `type`. Tap by text
  should stay out of the public interface; use `testID`, `ref`, or coordinates
  for tap.
- Keep full snapshots on disk. Send compact observations to agents by default,
  then query or inspect specific refs on demand.
## Verification

After code changes, run the repository post-change harness before handing work
back unless the user explicitly scopes verification down or local simulator
state blocks E2E. It includes SwiftPM tests, release CLI build, and the
XCTest-free runtime E2E scripts:

```bash
scripts/verify-agent-work.sh
```

For narrower debugging, run the individual checks below. Core unit tests use
Swift Testing (`import Testing`, `@Test`, `#expect`, `#require`), not XCTest:

```bash
swift test
```

Verify simulator injection and observation:

```bash
Examples/LoupeExample/run-injected.sh
```

Verify native HID runtime gestures, accessibility tree export/query, UIKit
component inspection, and layout audit:

```bash
Examples/LoupeExample/run-native-scenarios.sh
```

Verify the bookmark app-style E2E route:

```bash
Examples/LoupeExample/run-bookmark-e2e.sh
```

Verify platform runtime builds and linked/runtime platform examples:

```bash
scripts/verify-platform-builds.sh
Examples/MacLoupeExample/run-macos-e2e.sh
Examples/LoupeTVExample/run-tvos-runtime-e2e.sh
```

Verify the legacy UIKit XCTest example flow:

```bash
xcodebuild \
  -project Examples/LoupeExample/LoupeExample.xcodeproj \
  -scheme LoupeExample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  -only-testing:LoupeExampleUITests/LoupeExampleUITests/testNavigationListFormAndGestures \
  test
```

Verify the legacy Loupe snapshot to coordinate action proof:

```bash
Examples/LoupeExample/run-loupe-driven-ui-test.sh
```

## Known Boundary

`loupe act tap`, `loupe act swipe`, `loupe act drag`, `loupe act input`, and
`loupe act press` are runtime commands. They use Loupe's native HID dispatch.
`loupe act perform` invokes a target's declared Apple accessibility action in
the app runtime. Pinch is not implemented. The current UI test remains a legacy
proof only.
