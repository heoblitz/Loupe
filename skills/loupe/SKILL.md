---
name: loupe
description: Use this skill when working with iOS Simulator UI automation, Loupe runtime injection, view-tree inspection, accessibility tree querying, compact screen context, or Loupe CLI-driven simulator actions.
---

# Loupe

Use this skill when working with iOS Simulator UI automation, view-tree inspection, compact screen context, or Loupe injection.

## Runtime Assumptions

Use the installed `loupe` command. Do not hard-code DerivedData injector paths;
resolve the injector through Loupe when the path matters:

```bash
loupe injector-path
```

## Build And Inject Workflow

For an app that has already been built, place and launch it on the simulator
through Loupe:

```bash
xcrun simctl install booted /path/to/App.app
loupe start --bundle-id com.example.App
```

`loupe start` resolves the configured injector path, launches the app with
injection, and waits for the in-app Loupe server. It is a wrapper around
`loupe launch --inject`; Loupe does not need a separate host-side server.

If a nonstandard injector is needed, use:

```bash
loupe launch --bundle-id com.example.App --dylib /absolute/path/LoupeInjector.framework/LoupeInjector
```

## Observation

After launch, fetch context from the in-app Loupe server:

```bash
loupe current
loupe tree --bundle-id com.example.App --accessibility --depth 3
loupe fetch <runtime-host>/observation
loupe fetch <runtime-host>/snapshot --output /tmp/loupe-snapshot.json
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
loupe use com.example.App
loupe current
loupe tree --udid booted --accessibility --depth 3
loupe tree --udid booted --view --depth 3
loupe tree --bundle-id com.example.App --interesting
loupe tree --bundle-id com.example.App --text --accessibility
loupe current
loupe fetch <runtime-host>/snapshot --output /tmp/loupe-snapshot.json
loupe inspect /tmp/loupe-snapshot.json --test-id target.id
loupe mutations --ref n21
loupe tap --test-id target.id --udid booted --trace-dir /tmp/loupe-trace --expect-visible next.id
loupe trace-summary /tmp/loupe-trace
loupe diff /tmp/loupe-trace/before-snapshot.json /tmp/loupe-trace/after-snapshot.json
loupe audit /tmp/loupe-trace/after-snapshot.json
loupe compare-design /tmp/loupe-trace/after-snapshot.json figma-export.json
loupe set --list
loupe set --test-id example.design.card backgroundColor --color '#ff3366' --output /tmp/loupe-set.json
loupe reflect /tmp/loupe-set.json --source ./Sources
loupe cleanup --dry-run
```

The skill path should keep model context small: use `tree` and `compact` first,
then inspect specific refs or test IDs. Avoid pasting full snapshots into the
prompt unless the user explicitly asks for raw data.

When multiple apps are injected, select the active runtime before probing:

```bash
loupe runtimes
loupe use <bundle-id>
loupe current
```

Prefer `--bundle-id <id>` on `tree`, `query`, `set`, and `mutations` when the
target app is known. Do not keep retrying the default `http://127.0.0.1:8765`
after a timeout if `loupe runtimes` shows the app on another host.

For deep system apps, a low depth can show only containers. If `--depth 3`
only shows container nodes, retry depth 6-8, or switch to:

```bash
loupe tree --accessibility --text
loupe tree --interesting
loupe tree --visible-leaves
```

Use the accessibility tree for text discovery and tap targets. Use the view
tree plus `inspect` for mutation refs, UIKit class names, style, and layout.

## Actions

Loupe CLI action commands exist for runtime E2E:

```bash
loupe tap --test-id checkout.payButton --udid booted
loupe tap --test-id checkout.payButton --udid booted --trace-dir /tmp/loupe-trace
loupe tap --test-id checkout.payButton --udid booted --expect-visible checkout.confirmation
loupe drag --from 4,420 --to 360,420 --udid booted --duration 0.8
loupe swipe --from 219,760 --to 219,190 --udid booted --width 438 --height 954
loupe type "Ada" --udid booted
```

They use Loupe's native host-side HID backend. If dispatch fails, use
`loupe doctor` and the project docs rather than adding setup commands to this
skill. `loupe pinch` is intentionally not listed above because pinch dispatch is
not implemented yet.

Failed actions automatically create a trace under `/tmp/loupe-traces`. Trace
bundles include before/after snapshots, accessibility trees, logs, screenshots,
an action record, and `target-crop.png` when a target frame was available.

The product direction is runtime E2E through Loupe commands without requiring
XCTest, `xcodebuild test`, or a UI test bundle as the public harness.

## Debugging

Run:

```bash
loupe doctor
```

If injection does not start the server:

- Confirm the app is running in iOS Simulator, not a real device.
- Confirm `loupe injector-path` prints an executable path.
- Relaunch the app with `loupe launch --bundle-id <id> --inject`.
- Check `loupe current`, then `<runtime-host>/health`.

## Design Comparison

Figma API integration is not part of the skill yet. Use the JSON contract in
`Docs/FigmaComparison.md` for fixture work:

```bash
loupe compare-design snapshot.json figma-export.json
```

Match design nodes to Loupe nodes by `testID` first, then role plus text, then
geometry. Use Loupe view tree data for layout/style comparison and accessibility
tree data only for movement/input selectors.

## Cleanup

```bash
loupe cleanup
loupe cleanup --traces-older-than 14d
```

Use `cleanup` to prune stale runtime records and old trace bundles.

## Runtime Mutation

```bash
loupe set --udid <UDID> --test-id example.components.label text "Runtime edited"
loupe set --udid <UDID> --test-id example.design.card backgroundColor --color '#ff3366'
loupe set --udid <UDID> --test-id example.design.card frame --rect 20,120,220,80
loupe constraints --udid <UDID> --test-id example.design.card --json
loupe set-constraint --udid <UDID> --id <constraint-id> constant 120
loupe deactivate-constraint --udid <UDID> --id <constraint-id>
loupe set --udid <UDID> --list
loupe reflect /tmp/loupe-set.json --source ./Sources
```

Use `set` for developer-only UI iteration against the injected runtime. Prefer
stable `testID` selectors; use `ref` only within the same observed screen.
Use `constraints` before changing Auto Layout constraints, then read the
mutation response's effective state to confirm UIKit kept the requested value.
Use `reflect` after a verified mutation to summarize before/after state, confirm
the target hierarchy, and find source lines containing the test ID.
