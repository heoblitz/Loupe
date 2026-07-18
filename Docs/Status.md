# Loupe Status

Last verified: 2026-06-06.

Loupe is a runtime diagnostic and E2E harness for Apple-platform apps. The
current product surface is the `loupe` CLI plus injected or LoupeInjector-linked
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
- Inspect Objective-C runtime class metadata and weak lifetime probes through
  `debug objects` and `debug leaks` for development diagnostics.
- Query and inspect nodes by `testID`, text, role, or ref.
- Dispatch simulator-visible `tap`, `swipe`, `drag`, `type`, and tvOS remote
  `press` through Loupe's native host-side action backend where the simulator
  platform supports it.
- Dispatch `tap --backend runtime` against runtime-backed targets to activate
  selector-addressed UI controls such as AppKit `NSButton` when native HID is
  not the right backend.
- Profile scroll offset changes through simulator gesture traces or runtime
  offset probes for runtime platform examples.
- Resolve action targets through the accessibility tree first, then fall back to
  the view tree when needed.
- Save action traces with before/after snapshots, accessibility trees, logs,
  screenshots, action records, diffs, and target crops when available.
- Run quick route sweeps with `loupe debug trace explore`.
- Try allowlisted UIKit property mutations at runtime with `loupe ui set`,
  `loupe ui set-many`, and `loupe ui apply-design-suggestions`; property
  mutations animate by default and report effective state.
- Probe UIKit collection/table self-sizing during runtime mutations with
  `--try-self-sizing` on iOS 16+ when Loupe can identify a supported list
  sizing context. Repeated probes on an already-enabled container no-op and
  report `already-enabled`.
- Inspect and mutate Auto Layout constraints with `loupe ui constraints`,
  `loupe ui set-constraint`, and `loupe ui deactivate-constraint`, including effective-state
  verification.
- Reflect verified runtime mutation experiments back toward source with
  `loupe ui reflect`.
- Apply a small bounded batch of `ui compare-design --json` mutation
  suggestions before committing to a source rebuild. The default selection
  probes at most three copy/style/scalar-first changes and writes before/after
  snapshots, mutation responses, diff, and summary artifacts.
- Install the Codex/Claude skill with `loupe skills install`.

## Supported Verification

The repository post-change gate is:

```bash
scripts/verify-agent-work.sh
```

It runs:

- `swift test`
- benchmark helper syntax, case contracts, prompt generation,
  transcript-diagnosis, usage parsing, and replay-matrix freshness checks
- release CLI build
- runtime injection smoke E2E
- native HID and UIKit scenario E2E
- bookmark app-style E2E
- platform build checks for iOS, macOS, tvOS, visionOS Simulator, and watchOS
  Simulator targets
- injected macOS AppKit runtime E2E
- injected tvOS Simulator runtime and remote press E2E
- injected watchOS Simulator registered-probe runtime E2E

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

- Runtime observation is covered by injected iOS Simulator, macOS AppKit, tvOS
  Simulator, and watchOS Simulator examples. visionOS currently has build
  coverage for the UIKit-based runtime path, but no checked-in runtime E2E
  example yet. watchOS uses a registered-probe backend: apps can expose SwiftUI
  `.loupeProbe(...)`, `Loupe.registerProbe(...)`, or no-import
  `dev.loupe.probe` nodes plus logs, metadata, defaults/flags, and runtime
  identity. It does not yet do broad automatic WatchKit/SwiftUI element
  discovery or runtime input actions. iOS physical devices require a debug app
  that links and embeds the dynamic `LoupeInjector` product and is selected by
  `--host`; launch-time injection remains simulator-only.
- Native `UIAccessibility` container traversal is opt-in with
  `LOUPE_NATIVE_ACCESSIBILITY=1`; the default runtime path uses Loupe's
  view-derived accessibility tree. `act perform` does a bounded live traversal
  to revalidate and execute the selected accessibility action.
- SwiftUI movement/input selectors depend on elements exposed through the
  accessibility tree. Loupe does not synthesize private SwiftUI view selectors.
  Snapshots may include a bounded `swiftui` summary, but not raw private
  hierarchy.
- Screenshot baseline diffing is not implemented yet.
- Layout audit is useful for obvious issues, but it does not yet fully encode
  spacing, alignment, typography, z-order intent, clipping, or truncation rules.
- Layout-owned frame and Auto Layout mutations may be restored by UIKit. Loupe
  reports requested and effective state; only effective changes should guide
  source edits.
- Collection/table self-sizing probes are diagnostic and deliberately narrow:
  fixed item sizes, delegate-owned row heights, custom collection layouts, and
  unsupported OS versions are skipped with a reason.

## Source Of Truth

- Product goal: `Docs/Goal.md`
- Architecture: `Docs/LoupePlan.md`
- Verification coverage: `Docs/TestPlan.md`
- Runtime transport: `Docs/RuntimeCommunication.md`
- Agent workflow: `skills/loupe/SKILL.md`
