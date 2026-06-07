---
name: loupe
description: Use this skill when working with Loupe Apple-platform runtime automation, simulator injection, linked LoupeInjector runtimes, view-tree inspection, accessibility tree querying, compact screen context, or Loupe CLI-driven platform actions.
---

# Loupe

Use Loupe to observe, query, act on, mutate, and diagnose Apple-platform app
runtimes through the in-process server.

## Core Rules

- Use grouped commands from current help: `app`, `ui`, `act`, and `debug`.
  Old top-level verbs are compatibility aliases only.
- Check subcommand help before adding unfamiliar flags; options are not shared
  globally. Do not re-open help for exact command recipes already provided by
  the task or this skill.
- Keep the attachment mode explicit: simulator injection, debug-only
  physical-device LoupeInjector dependency, macOS host runtime, watchOS, or
  visionOS.
- Keep full reports, snapshots, and traces on disk; use compact observations
  in chat, then query or inspect refs as needed.
- Keep verbose build logs and large JSON on disk. Print a short path/status,
  and inspect only the focused node, summary, or failing log tail needed for the
  next decision.
- Prefer accessibility for discovery/action intent; prefer the view tree for
  layout, style, mutations, and visual diagnostics.
- Prefer `testID`, current-snapshot `ref`, or coordinates. Do not use
  tap-by-text as a public contract.
- Command success alone is not proof. Verify with fresh reports, traces,
  screenshots, hit-tests, logs, defaults, or effective state.
- Simulator injection uses the Loupe CLI/injector outside the app. It should
  not require changing the app source or adding `import LoupeKit`.
- Physical devices are different: the debug app must link and embed the
  dynamic LoupeInjector runtime. Do not include it in App Store release builds.

## References

- `references/runtime-modes.md`: attaching, launching, platform boundaries.
- `references/evidence-workflow.md`: reports, visibility, design
  implementation evidence, SwiftUI, probes, logs, diagnostics.
- `references/actions-and-mutations.md`: actions, waits, scrolls, mutations,
  self-sizing, `reflect`.

## Default Loop

1. Identify the runtime mode and host. Prefer the host printed by `app launch`;
   `app current` can be stale.
2. Capture `ui report` and keep `snapshot.json`.
3. Discover with text/role/accessibility, then switch to `testID` or a ref from
   the same snapshot. Inspect with `ui node` before acting.
4. For design checks, use one report plus one `ui compare-design` pass before
   deciding whether source or a small mutation probe is needed.
5. Keep each design iteration bounded: report, compare, optional one small
   mutation batch, after-proof, then source patch/relaunch. Avoid broad
   diagnostics unless the scenario requires them.
6. For overlays, alerts, reused cells, or stale refs, recapture and use
   hit-test, responder-chain, screenshot, or trace proof.
7. Act or mutate with a fresh output/trace path, then prove the result with a
   fresh report, query, node, trace, or effective-state check.
