# Loupe Architecture Notes

Loupe is an Apple-platform runtime harness for observation, platform-visible
input where available, diagnostics, and fast UI iteration.

## Goals

- Capture high-fidelity UIKit/AppKit and accessibility state from inside the
  app.
- Give agents compact context by default and full snapshots on demand.
- Resolve stable selectors for inspection and action.
- Execute real simulator input without making XCTest the public harness.
- Keep screenshots, logs, diffs, and traces for reproducible failures.
- Let developers try supported UIKit mutations at runtime, verify effective
  state, and reflect successful experiments back into source.

Figma API integration is not part of the runtime architecture. Design checks use
Loupe snapshots, screenshots, screen maps, audits, and optional exported design
fixtures.

## Components

```text
loupe CLI
  - launches and injects simulator apps where injection is supported
  - talks to linked LoupeKit runtimes for platforms such as macOS
  - records runtime host mappings
  - stores snapshots, reports, screenshots, logs, and traces
  - resolves selectors and dispatches host-side simulator input

LoupeKit / LoupeInjection
  - runs inside the app process
  - captures view, accessibility, UIKit/AppKit, layout, style, and metadata state
  - exposes localhost runtime endpoints
  - applies allowlisted UIKit mutation experiments on the app main thread

LoupeCore
  - shared models for snapshots, accessibility trees, queries, audits, diffs,
    compact observations, and design comparison
```

Homebrew installs both the CLI and `LoupeInjector.framework`; `loupe app launch`
resolves the injector path automatically for simulator injection workflows.

## Runtime Selection

Injected apps bind to localhost. The CLI launch path chooses an available port
unless `--port` or `LOUPE_PORT` is explicitly provided. Do not build workflows
around a fixed default port.

Use stable identity first:

```bash
loupe app list
loupe app use com.example.App
loupe app current
loupe ui report --bundle-id com.example.App --output loupe-report
```

Use `--host <runtime-host>` only when it comes from `loupe app list` or
`loupe app current`.

## Observation Policy

Do not put the whole tree into LLM context by default.

Default agent context should come from:

- `ui compact`
- `ui tree --accessibility`
- `ui tree --view`
- `ui screen`
- targeted `ui node`
- `debug trace summary`
- `debug trace diff --changed-only`

Use accessibility for movement/input selectors and text discovery. Use the view
tree for layout, style, UIKit properties, mutation refs, and design checks.

## Action Boundary

Loupe should not rely on app-internal `UIEvent` synthesis as the main action
strategy. App-side code observes state; host-side Loupe commands dispatch user
visible input through the simulator.

Target flow:

```text
loupe act tap --test-id checkout.payButton --trace-dir /tmp/loupe-trace
  -> fetch runtime accessibility/snapshot state
  -> resolve target and coordinates
  -> dispatch native simulator input
  -> capture after state, screenshot, logs, and diff
```

`tap`, `swipe`, `drag`, `type`, and tvOS `press` are implemented.
Tap-by-text is intentionally not the public contract because visible text is
ambiguous; prefer `testID`, `ref`, or coordinates.

## Runtime Mutation

Mutation is a runtime experiment path, not a guarantee that UIKit will keep every
requested value. Support is allowlisted, not arbitrary Objective-C selector
execution.

```bash
loupe ui mutations --test-id checkout.card
loupe ui set --test-id checkout.title text "New title" --output /tmp/loupe-set.json
loupe ui set --test-id checkout.card backgroundColor --color '#ff3366'
loupe ui set --test-id checkout.card frame --rect 20,120,220,80 --no-animate
loupe ui reflect /tmp/loupe-set.json --source ./Sources
```

Supported families include view, layer, accessibility, text, control, scroll,
stack, and Auto Layout constraint properties. Text, colors, alpha, hidden state,
layer styling, and common control values are the strongest targets. Frame and
constraint edits are useful probes, but UIKit owners may restore them during a
layout pass. Mutation responses include requested and effective state so those
reversions are visible.

## Runtime UI Verification

UI implementation is considered successful only when runtime evidence supports
it. Design comparison is one optional workflow in that loop:

- screen size matches the intended simulator
- fixed chrome does not scroll with content
- scroll gestures produce meaningful content movement
- key route actions produce traceable state changes
- key elements have expected text, frame, color, corner radius, clipping, and
  hierarchy
- screenshots match the intended visual state

Use `Docs/FigmaComparison.md` for optional exported-design fixture comparison.

## Planned Work

1. Add screenshot baseline diffing.
2. Expand layout/style assertions for spacing, typography, alignment, clipping,
   and z-order intent.
4. Improve selector scoring for ambiguous accessibility and view-tree matches.
5. Continue refining the Loupe skill with measured agent A/B loops.
