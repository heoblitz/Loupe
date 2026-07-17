---
name: loupe
description: Use this skill when implementing, inspecting, or verifying native app interfaces on Apple platforms with Loupe runtime evidence, simulator injection, linked LoupeInjector runtimes, view/accessibility trees, design comparison, mutation probes, or CLI-driven actions.
---

# Loupe

Use Loupe to observe, query, act on, mutate, and diagnose Apple-platform app
runtimes through the in-process server.

## Workflow Configuration

### Command Route

- Use grouped commands from current help: `app`, `ui`, `act`, and `debug`.
  Old top-level verbs are compatibility aliases only.
- Check subcommand help before adding unfamiliar flags; options are not shared
  globally. Do not re-open help for exact command recipes already provided by
  the task or this skill.
- Keep the attachment mode explicit: simulator injection, debug-only
  physical-device LoupeInjector dependency, macOS host runtime, watchOS, or
  visionOS.

### Evidence And Context

- Keep full reports, snapshots, and traces on disk; use compact observations
  in chat, then query or inspect refs as needed.
- Keep verbose build logs and large JSON on disk. Print a short path/status,
  and inspect only the focused node, summary, or failing log tail needed for the
  next decision.
- Prefer accessibility for discovery/action intent; prefer the view tree for
  layout, style, mutations, and visual diagnostics.
- For screen movement, use `act targets` then `act tap '#N'`. For view
  analysis, use `ui report`.
- Command success alone is not proof. Verify with fresh reports, traces,
  screenshots, hit-tests, logs, defaults, or effective state.

### Targeting

- Discover with accessibility, role, or text; act with app-owned `testID`,
  current `ref`, or coordinates. Do not use tap-by-text as a public contract.
- For action, mutation, and wait, fresh-resolve the current screen: zero
  matches means not found; multiple actionable matches means ambiguous.
- Treat `ref` as a snapshot/session handle, not a durable selector.
- Suggest missing `testID`s only as hints. Prefer the nearest route/root prefix;
  avoid index, coordinate, or deep hierarchy names.

### Runtime Boundaries

- Simulator injection uses the Loupe CLI/injector outside the app. It should
  not require changing the app source or adding `import LoupeKit`.
- Physical devices are different: the debug app must link and embed the
  dynamic LoupeInjector runtime. Do not include it in App Store release builds.

## Reference Map

- `references/runtime-modes.md`: attaching, launching, platform boundaries.
- `references/evidence-workflow.md`: reports, visibility, design
  implementation evidence, SwiftUI, probes, logs, diagnostics.
- `references/actions-and-mutations.md`: actions, waits, scrolls, mutations,
  self-sizing, `reflect`.

## Workflow

1. Identify the runtime mode and host. Prefer the host printed by `app launch`;
   `app current` can be stale.
2. Use `act targets` then `act tap '#N'` for lightweight screen movement. The
   quoted alias is one-shot; list targets again before the next alias action.
3. Use `ui report` for view analysis. Keep `snapshot.json`, then query or
   inspect only the relevant nodes.
4. For design checks, capture one report, review the screenshot and audit
   summary, then run `ui compare-design` when a design fixture exists.
5. Keep each design iteration bounded: report, screenshot/audit judgment,
   compare, optional one small mutation batch, after-proof, then source
   patch/relaunch. Avoid broad diagnostics unless the scenario requires them.
6. For overlays, alerts, reused cells, or stale refs, recapture and use
   hit-test, responder-chain, screenshot, or trace proof.
7. Act or mutate with a fresh output/trace path, then prove the result with a
   fresh report, query, node, trace, or effective-state check.
