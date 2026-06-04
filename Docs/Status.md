# Loupe Status

Last verified: 2026-06-03.

Loupe is a runtime diagnostic and E2E harness for Apple-platform apps. The
current product surface is the `loupe` CLI plus injected or linked LoupeKit
runtime servers.

## Current Capabilities

- Launch simulator apps with injection through `loupe app launch`.
- Assign an available localhost port on launch, record the runtime under
  `~/.loupe/runtimes`, and resolve later commands by `--bundle-id`, `--udid`,
  or `loupe app use <bundle-id>`.
- Capture full snapshots, compact observations, accessibility trees, visible
  screen maps, screenshots, layout audits, runtime logs, and action traces.
- Read URLSession network evidence, app-authored network events, reference
  evidence, defaults/flags, and keychain metadata from the running app.
- Query and inspect nodes by `testID`, text, role, or ref.
- Dispatch simulator-visible `tap`, `swipe`, `drag`, `type`, and tvOS remote
  `press` through Loupe's native host-side action backend where the simulator
  platform supports it.
- Dispatch `tap --backend runtime` against linked runtimes to activate
  selector-addressed UI controls such as AppKit `NSButton` when simulator HID is
  not the right backend.
- Profile scroll offset changes through simulator gesture traces or runtime
  offset probes for linked/runtime platform examples.
- Resolve action targets through the accessibility tree first, then fall back to
  the view tree when needed.
- Save action traces with before/after snapshots, accessibility trees, logs,
  screenshots, action records, diffs, and target crops when available.
- Run quick route sweeps with `loupe debug trace explore`.
- Try allowlisted UIKit property mutations at runtime with `loupe ui set` and
  `loupe ui set-many`; property mutations animate by default and report effective
  state.
- Inspect and mutate Auto Layout constraints with `loupe ui constraints`,
  `loupe ui set-constraint`, and `loupe ui deactivate-constraint`, including effective-state
  verification.
- Reflect verified runtime mutation experiments back toward source with
  `loupe ui reflect`.
- Install the Codex/Claude skill with `loupe skills install`.

## Supported Verification

The repository post-change gate is:

```bash
scripts/verify-agent-work.sh
```

It runs:

- `swift test`
- release CLI build
- runtime injection smoke E2E
- native HID and UIKit scenario E2E
- bookmark app-style E2E
- platform build checks for iOS, macOS, and tvOS support targets
- linked macOS AppKit runtime E2E
- tvOS Simulator runtime and remote press E2E

GitHub Actions uses the same command for the `Post-change E2E` required check.

## Runtime Diagnosis And UI Iteration

For diagnosis, design, or screenshot-driven work, the expected loop is:

```bash
loupe ui report --bundle-id com.example.App --output loupe-report
loupe ui screen loupe-report/snapshot.json --limit 120
loupe ui tree loupe-report/snapshot.json --view --depth 6
loupe ui node loupe-report/snapshot.json --test-id key.control
loupe ui audit loupe-report/snapshot.json
loupe ui screenshot --udid booted --output loupe-screen.png
```

Use screenshots for visual sanity and the view tree for actionable checks:
frames, hierarchy, fixed chrome, scroll containers, colors, corner radius,
clipping, and UIKit metadata.

## Current Limits

- Runtime observation is covered by iOS Simulator injection plus linked macOS
  AppKit and tvOS Simulator examples; physical devices are out of scope.
- Native `UIAccessibility` container traversal is opt-in with
  `LOUPE_NATIVE_ACCESSIBILITY=1`; the default runtime path uses Loupe's
  view-derived accessibility tree.
- SwiftUI movement/input selectors depend on elements exposed through the
  accessibility tree. Loupe does not synthesize private SwiftUI view selectors.
- Screenshot baseline diffing is not implemented yet.
- Layout audit is useful for obvious issues, but it does not yet fully encode
  spacing, alignment, typography, z-order intent, clipping, or truncation rules.
- Layout-owned frame and Auto Layout mutations may be restored by UIKit. Loupe
  reports requested and effective state; only effective changes should guide
  source edits.

## Source Of Truth

- Product goal: `Docs/Goal.md`
- Architecture: `Docs/LoupePlan.md`
- Verification coverage: `Docs/TestPlan.md`
- Runtime transport: `Docs/RuntimeCommunication.md`
- Agent workflow: `skills/loupe/SKILL.md`
