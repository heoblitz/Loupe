---
name: loupe
description: Use this skill when working with Loupe Apple-platform runtime automation, simulator injection, linked LoupeKit runtimes, view-tree inspection, accessibility tree querying, compact screen context, or Loupe CLI-driven platform actions.
---

# Loupe

Use Loupe for Apple-platform runtime observation, diagnostics, CLI actions,
mutation probes, and design QA. Keep full snapshots on disk during the task,
send compact output to agents, and delete artifacts after use unless they are
evidence, failure traces, or part of a before/after comparison.

## Rules

- Use the installed `loupe`; resolve injector paths with `loupe injector-path`.
- Loupe talks to the injected app server; no separate host daemon is needed.
- Use accessibility for text discovery and action targets. Use the view tree for
  layout, style, UIKit properties, mutation refs, and visual checks.
- Drive runtime E2E with Loupe CLI actions, not XCTest as the public harness.
- Public simulator actions are `tap`, `swipe`, `drag`, `type`, and tvOS
  `press`; prefer `testID`, `ref`, or coordinates over tap-by-text.
- Artifacts are temporary. Use task-specific `/tmp` paths, clear old paths first,
  and manually remove explicit `ui report` output or `--trace-dir` directories.
  `loupe app cleanup` only prunes stale runtime records and old automatic traces.

## Runtime

```bash
xcrun simctl install booted /path/to/App.app
loupe app launch --bundle-id com.example.App

loupe app list
loupe app use com.example.App
loupe app use --host <runtime-host>
loupe app current
```

For linked runtimes such as macOS examples, start the app normally and pass the
runtime `--host`.

Observation commands can use `--bundle-id` or `--host`. Simulator action
commands do not accept `--bundle-id`; run
`loupe app use <bundle-id> --udid <sim-udid>` first, or pass
`--host <runtime-host> --udid <sim-udid>`. If multiple simulators are booted, do
not use `--udid booted`; use the UDID from `loupe app current` or `loupe app list`.

## Observe

```bash
REPORT=/tmp/loupe-checkout-report
rm -rf "$REPORT"
loupe ui report --bundle-id com.example.App --output "$REPORT"
loupe ui compact "$REPORT/snapshot.json"
loupe ui screen "$REPORT/snapshot.json" --limit 80
loupe ui tree "$REPORT/snapshot.json" --accessibility --depth 3
loupe ui tree "$REPORT/snapshot.json" --view --depth 3
loupe ui node "$REPORT/snapshot.json" --test-id target.id
```

`ui report` stores screenshot, snapshot, screen-map, accessibility,
compact, audit, runtime, and summary files. Logs are in `runtime.json.logs`;
newer CLI builds may also emit `logs.json`. Start broad, then query only the
target:

```bash
loupe ui query "$REPORT/snapshot.json" --test-id target.id
loupe ui node "$REPORT/snapshot.json" --test-id target.id --node-only
loupe ui subtree "$REPORT/snapshot.json" --test-id target.container --depth 2
```

Prefer `--test-id` when available. Use `--ref` only within the same snapshot.
Use text or role flags for discovery, then switch to `testID` or `ref`.

For app diagnostics, use `Loupe.log("checkout_visible")` when importing
`LoupeKit`. Without that import, post the bridge notification and read logs
explicitly when needed:

```swift
NotificationCenter.default.post(
    name: Notification.Name("dev.loupe.log"),
    object: nil,
    userInfo: ["message": "checkout_visible"]
)
```

```bash
loupe debug logs --bundle-id com.example.App --output "$REPORT/logs.json"
```

Use `Notification.Name("dev.loupe.viewMetadata")` for scalar metadata on a
UIKit view or stable `testID`, then verify with `loupe ui node`.
Use `Loupe.recordReference(...)` or the `dev.loupe.reference` notification when
the task needs ownership evidence, then answer owner questions with:

```bash
loupe debug object-graph DeviceActuationService --host <runtime-host> --output /tmp/loupe-reference-graph.json
```

The graph is app-authored reference evidence, not private heap traversal.
Use `owners` to answer what points at a target, and cite `evidenceID`, `kind`,
`label`, `metadata`, and `timestamp` when explaining the result.

## Act

```bash
TRACE=/tmp/loupe-checkout-trace
rm -rf "$TRACE"
loupe act tap --test-id checkout.payButton --host <runtime-host> --udid <sim-udid> --trace-dir "$TRACE"
loupe act tap --snapshot "$REPORT/snapshot.json" --ref n21 --udid <sim-udid>
loupe act tap --x 201 --y 274 --udid <sim-udid> --width 438 --height 954
loupe act swipe --from 219,760 --to 219,190 --host <runtime-host> --udid <sim-udid> --width 438 --height 954 --trace-dir "$TRACE"
loupe act press select --host <runtime-host> --udid <tvos-sim-udid> --trace-dir "$TRACE"
loupe debug scroll --test-id feed.list --delta 0,80 --host <runtime-host> --output /tmp/loupe-scroll-profile.json
loupe debug trace summary "$TRACE"
loupe debug trace diff "$TRACE/before-snapshot.json" "$TRACE/after-snapshot.json" --changed-only
```

Also use `act drag`, `act type`, `act press`, and `debug trace explore` when needed. Treat scroll
with no offset or visible-frame change as failed unless `--no-verify-scroll` is
intentional. Use `debug scroll --delta` or `--to-offset` for linked runtimes that
can expose scroll state but do not have host HID scroll input. Preserve failed
trace paths until summarized or handed back. Remove successful trace dirs unless
a later diff/audit needs them. Action traces use
`before-snapshot.json`/`after-snapshot.json`; `ui set-many --trace-dir` uses
`prev-snapshot.json`/`next-snapshot.json`.

## Mutate

Mutations are developer-only probes. Prefer stable `testID`; use `ref` only
within the same observed screen. Use `loupe ui mutations`, `loupe ui set`,
`loupe ui set-many`, `loupe act wait value`, and `loupe ui reflect`. Use
`--no-animate` when verification needs immediate state. Treat frame and Auto
Layout mutations as probes until `loupe ui node` confirms the effective state.

## Design QA

For Figma, screenshot, or visual-reference work, capture a report, inspect
anchors, run `loupe ui audit "$REPORT/snapshot.json"`, then act and diff. Use
`loupe ui compare-design "$REPORT/snapshot.json" /path/to/design.json --limit 20`
when fixture data exists. Reject wrong screen size, duplicated
simulator chrome, scrolling fixed chrome, wrong scroll axis, bad key
text/frame/color/corner metadata, untraceable routes, or unintended app state.
For `compare-design`, match by `testID`, then role plus text, then geometry.

## Debug

```bash
loupe doctor
loupe injector-path
loupe app launch --bundle-id <id> --inject
loupe app cleanup --dry-run
```
