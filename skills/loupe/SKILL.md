# Loupe

Use this skill when working with iOS Simulator UI automation, view-tree inspection, compact screen context, or Loupe injection.

## Tooling Assumptions

Prefer the Homebrew installation:

```bash
brew install loupe
```

The Homebrew package installs:

- `loupe` CLI on `PATH`
- `LoupeInjector.framework/LoupeInjector` under Homebrew `libexec`
- AXe for low-level simulator input

Do not hard-code DerivedData injector paths. Resolve the injector through Loupe:

```bash
loupe injector-path
```

## Build And Inject Workflow

For an app that has already been built with `xcodebuild`, install and launch it on the simulator through Loupe:

```bash
xcrun simctl install booted /path/to/App.app
loupe start --bundle-id com.example.App
```

`loupe start` resolves the Homebrew injector path, launches the app with
injection, and waits for the in-app Loupe server. It is a wrapper around
`loupe launch --inject`; Loupe does not need a separate host-side server.

If a nonstandard injector is needed, use:

```bash
loupe launch --bundle-id com.example.App --dylib /absolute/path/LoupeInjector.framework/LoupeInjector
```

## Observation

After launch, fetch context from the in-app Loupe server:

```bash
loupe fetch http://127.0.0.1:8765/observation
loupe fetch http://127.0.0.1:8765/snapshot --output /tmp/loupe-snapshot.json
loupe query /tmp/loupe-snapshot.json --test-id checkout.payButton
loupe accessibility /tmp/loupe-snapshot.json
loupe query /tmp/loupe-snapshot.json --tree accessibility --test-id checkout.payButton
loupe inspect /tmp/loupe-snapshot.json --test-id checkout.payButton
loupe subtree /tmp/loupe-snapshot.json --test-id checkout.form --depth 3
loupe audit /tmp/loupe-snapshot.json
loupe wait-for-visible --test-id checkout.payButton --timeout 5
```

Use compact observation for LLM context. It carries UIKit type/class identity for
interactive elements but avoids full property dumps. Keep full snapshots in
files, query the view tree by `testID`, text, role, or ref for UI verification,
and use `inspect` only when the full node, style, UIKit-specific fields, or
parent/sibling/child context is needed.

Use the accessibility tree for movement and input. Selector-based actions
already resolve there first, then fall back to the view tree only if no
accessibility match exists.

## Agent Routine

When using Loupe as an agent skill, follow this order:

```bash
loupe runtimes
loupe tree --udid booted --accessibility --depth 3
loupe tree --udid booted --view --depth 3
loupe fetch http://127.0.0.1:8765/snapshot --output /tmp/loupe-snapshot.json
loupe inspect /tmp/loupe-snapshot.json --test-id target.id
loupe tap --test-id target.id --udid booted --trace-dir /tmp/loupe-trace --expect-visible next.id
loupe trace-summary /tmp/loupe-trace
loupe diff /tmp/loupe-trace/before-snapshot.json /tmp/loupe-trace/after-snapshot.json
loupe audit /tmp/loupe-trace/after-snapshot.json
loupe compare-design /tmp/loupe-trace/after-snapshot.json figma-export.json
loupe cleanup --dry-run
```

The skill path should keep model context small: use `tree` and `compact` first,
then inspect specific refs or test IDs. Avoid pasting full snapshots into the
prompt unless the user explicitly asks for raw data.

## Actions

Loupe CLI action commands exist for runtime E2E:

```bash
loupe tap --test-id checkout.payButton --udid booted
loupe tap --test-id checkout.payButton --udid booted --trace-dir /tmp/loupe-trace
loupe tap --test-id checkout.payButton --udid booted --expect-visible checkout.confirmation
loupe drag --from 4,420 --to 360,420 --udid booted --duration 0.8
loupe swipe --from 219,760 --to 219,190 --udid booted --width 438 --height 954
loupe type "Ada" --udid booted
loupe record start checkout-flow
loupe record stop
loupe recordings
loupe replay checkout-flow --udid booted --width 438 --height 954
```

They currently delegate low-level HID dispatch to AXe. Install AXe with
`brew install cameroncooke/axe/axe`, or install Loupe through Homebrew so the
formula pulls AXe in as a dependency. `loupe pinch` is intentionally not listed
above because AXe does not support pinch yet.

Failed actions automatically create a trace under `/tmp/loupe-traces`. Trace
bundles include before/after snapshots, accessibility trees, logs, screenshots,
an action record, and `target-crop.png` when a target frame was available.

The product direction is runtime E2E through Loupe commands without requiring
XCTest, `xcodebuild test`, or a UI test bundle as the public harness. The current
legacy proof is:

```bash
Examples/LoupeExample/run-loupe-driven-ui-test.sh
```

That test fetches Loupe snapshots, resolves node frames, and uses
`XCUICoordinate` for tap and drag actions. Treat it as evidence for coordinate
resolution, not as the target action architecture.

## Debugging

Run:

```bash
loupe doctor
```

For Core unit coverage, prefer Swift Testing:

```swift
import Testing

@Test func resolvesSelector() {
    #expect(result.ref == "button")
}
```

If injection does not start the server:

- Confirm the app is running in iOS Simulator, not a real device.
- Confirm `loupe injector-path` prints an executable path.
- Relaunch the app with `loupe launch --bundle-id <id> --inject`.
- Check `http://127.0.0.1:8765/health`.

## Design Comparison

Figma API integration is not part of the skill yet. Use the JSON contract in
`Docs/FigmaComparison.md` for fixture work:

```bash
loupe compare-design snapshot.json figma-export.json
```

Match design nodes to Loupe nodes by `testID` first, then role plus text, then
geometry. Use Loupe view tree data for layout/style comparison and accessibility
tree data only for movement/input selectors.

## Install

```bash
loupe skills install
loupe skills install --target codex
loupe skills install --target claude
```

`skills install` upserts this skill into existing Codex or Claude Code skill
folders and skips missing clients.

## Cleanup

```bash
loupe cleanup
loupe cleanup --traces-older-than 14d
loupe cleanup --recordings-older-than 30d
```

Use `cleanup` to prune stale runtime records and old trace bundles. Recordings
are preserved unless explicitly requested.
