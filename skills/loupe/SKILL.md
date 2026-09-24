---
name: loupe
description: Inspect, act on, and verify native Apple-platform app interfaces using Loupe runtime snapshots, accessibility, screenshots, and action traces. Use for runtime UI diagnosis, design comparison, simulator injection, or linked LoupeInjector workflows.
---

# Loupe

## Choose The Runtime

- Identify the platform and attachment mode. Prefer the host printed by
  `loupe app launch`; `app current` may refer to another app.
- Keep the same `--host <url>` or `--bundle-id <id>` across live commands.
  Add `--udid <id>` when the same bundle runs on multiple simulators.
- Simulator injection needs no app source change or `import LoupeKit`.
  Physical devices need a debug-only linked and embedded LoupeInjector.
- Read [runtime-modes](references/runtime-modes.md) for launch and platform setup.

## Short Working Loop

```bash
loupe act targets --host <host> --search <label-or-id>
loupe act tap '#1' --host <host>
loupe ui query --host <host> --tree accessibility --test-id <expected-id>
```

- Aliases are quoted, one-shot intents. List targets again after an alias action.
  If the app-owned testID is known, use `act tap --test-id <id>` directly.
- Discover through accessibility; inspect layout/style through the view tree.
  Zero matches means not found; multiple matches require a more precise target.
- Refs belong to a snapshot/session. Use `--snapshot <file>` for saved-ref
  actions and mutations. Text is for discovery, not tap targeting.
- Verify the expected change with a focused query, wait, value, screenshot,
  or trace. Successful dispatch alone does not prove the intended result.
  If dispatch may already have occurred, inspect state before retrying.

## Keep Context Small

- For layout/design work, capture `ui report --host <host> --output <dir>`.
  Keep the snapshot and images on disk, then use `ui query <snapshot.json>`
  or `ui node <snapshot.json> --ref <ref> --fields node`.
- `ui tree` defaults to 80 lines with bounded line lengths. Focus with `--ref`
  or `--limit`; use `--all` only when full output is needed as an artifact.
- Use `ui tree --text`, `ui screen`, `ui paint`, `debug object-graph`, and
  `debug defaults` (also for feature flags). Check subcommand help only for
  unfamiliar options; avoid repeatedly loading help or full JSON/build logs.
- For design iteration, review one report/screenshot, compare with the design,
  try a small mutation if useful, then patch source and verify after relaunch.

## Task-Specific References

Read only the reference relevant to the next operation:

- [actions-and-mutations](references/actions-and-mutations.md): input, waits,
  traces, mutation, self-sizing, and source reflection.
- [evidence-workflow](references/evidence-workflow.md): visibility/occlusion,
  design comparison, SwiftUI/probes, and focused diagnostics.
