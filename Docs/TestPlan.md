# Loupe Test Plan

This plan tracks whether Loupe can support a repeated developer loop:
observe the app, act through the available platform backend, inspect exact
UIKit/AppKit state on demand, and validate functional or design regressions
without making XCTest the public harness.

## Post-Change Harness

Agents should run the repository-level verification command after code changes:

```bash
scripts/verify-agent-work.sh
```

That command is the default post-work gate and the `Post-change E2E` GitHub
Actions required check. It runs:

- `swift test`
- benchmark helper syntax, case-contract, prompt-generation,
  transcript-diagnosis, measured-run finalization, usage-parsing, and
  replay-matrix freshness checks
- `swift build --configuration release --disable-sandbox --product loupe`
- `Examples/LoupeExample/run-injected.sh`
- `Examples/LoupeExample/run-runtime-e2e.sh`
- `Examples/LoupeExample/run-native-scenarios.sh`
- `Examples/LoupeExample/run-bookmark-e2e.sh`
- `scripts/verify-platform-builds.sh`
- `Examples/MacLoupeExample/run-macos-e2e.sh`
- `Examples/LoupeTVExample/run-tvos-runtime-e2e.sh`
- `Examples/LoupeWatchExample/run-watchos-runtime-e2e.sh`

If local simulator state blocks E2E, record the failing script, exit status,
and the generated `/tmp/loupe-*` logs or screenshots before handing work back.

## Design-to-Code Evaluation

This is a benchmark workflow, not Loupe's primary positioning; the same runtime
evidence should also support functional debugging and regression checks.

When evaluating whether Loupe improves implementation quality, use a blind
baseline instead of reusing the current agent's context.

Required setup:

- Start two fresh subagents without inherited conversation context.
- Give both agents the same design link, target screen, exported design
  metadata when available, and app requirements.
- Give the Loupe agent only the Loupe CLI/skill as the extra capability.
- Give the baseline agent no Loupe CLI, snapshots, traces, view tree, or skill.
- Use separate work directories and simulator devices.
- Forbid both agents from reading previous `/tmp/loupe-*` comparison artifacts.

Score both outputs with the same artifacts:

- visual distance to the design reference
- view-tree structure for native text, image views, tab bars, scroll views, and
  layout/style metadata
- audit output for contrast, overlap, target-size, and layout regressions
- action traces for critical routes and scroll gestures
- runtime correctness, including whether fixed chrome is outside content scrolls
- runtime screen size and device-class correctness before visual scoring
- screenshot capture status with
  `scripts/benchmark-screenshot-check.sh --target <target.png> --actual <final.png> --summary <report/summary.json> --top-chrome-sensitive`
  so target-sized, native-scale, and mismatched screenshots are reported
  consistently
- a case contract under `Docs/benchmarks/design-to-code/cases/` summarized with
  `scripts/benchmark-summarize-ab.sh <case.json> --output-dir <summary-dir>`
  so build count, launch count, mutation count, screenshot status, and
  compare-design counts are comparable across cases
- a cross-case matrix from
  `scripts/benchmark-summarize-matrix.sh <summary.json>...` before claiming a
  trend
- speed, command count, exact runner-provided token usage when available, and
  amount of context needed. For Codex worker transcripts, extract usage with
  `scripts/benchmark-extract-codex-usage.sh <session.jsonl> --output <usage.json>`.
  If only the worker thread id is known, locate the transcript first with
  `scripts/benchmark-find-codex-session.sh <thread-id>`.
  To turn a completed prepared run into a replay case, use
  `scripts/benchmark-finalize-measured-run.sh --manifest <run>/manifest.json ...`.
  If a worker transcript arrives after a summary already exists, attach it with
  `scripts/benchmark-attach-usage.sh <summary.json> --side baseline|loupe --session <session.jsonl>`.
  Diagnose token/context drift with
  `scripts/benchmark-diagnose-transcript.sh <session.jsonl>` before changing
  prompts or skill guidance. For new strict worker runs, fail avoidable
  context leaks with `scripts/benchmark-lint-transcript.sh <session.jsonl>`
  before treating token/context metrics as clean. The replay matrix also
  surfaces saved-transcript worker turns, tool calls, `view_image` calls,
  image-output bytes, total tool-output bytes, and overhead signals such as
  prompt echoing, memory lookup, broad simulator lists, repeated image loads,
  and build-log tails so token drift is tied to observable context weight
  rather than guessed from command count.
  Report raw token usage separately from quality-normalized token usage. A
  baseline that spends fewer raw tokens but still misses acceptance after the
  allowed correction rounds is not a token-efficiency win for the requested
  quality level. The replay matrix should surface both readings side by side.
  If exact tokens are unavailable, use prompt/context bytes only as proxy
  evidence and keep token winners unmeasured.
- Keep benchmark result count labels machine-readable. `Build count`,
  `Install count`, `Launch count`, `Mutation count`, and `Correction rounds`
  should contain integers only; record app-build, CLI-build, injector-build, or
  correction details on separate note lines.
- Label issue counts by source. Use `compare-design issues` for design fixture
  matching and `audit issues` for runtime layout/contrast/touch-target checks;
  do not collapse them into a single unqualified `issues` score.
- For SwiftUI benchmark cases, record whether evidence comes from native
  accessibility, raw hosting-tree nodes, or app-authored probes. Probe-backed
  `compare-design` can prove intended bounds and identifiers, but visual review
  and audit still decide whether the screen is acceptable.
- When screenshot fidelity and runtime inspectability disagree, record visual
  winner and proof winner separately. A screenshot-close SwiftUI result with a
  sparse runtime tree is not the same outcome as a screenshot-close result with
  queryable text, identifiers, and design-node matches.
- Keep benchmark workers on the smallest runnable app/project that satisfies
  the case. Loupe attachment is only one of these paths: simulator injection at
  launch with the Loupe CLI/injector, or a physical-device debug-only app
  dependency that links and embeds the dynamic LoupeInjector runtime.
  Repository verification apps are internal fixtures, not app templates or
  attachment modes. Successful build logs should be written to artifact files
  instead of printed into the worker transcript.
- `scripts/benchmark-usage-smoke.sh` and a small transcript-diagnosis smoke in
  the repository verification harness so usage parsing and context-overhead
  regressions are caught without needing a real Figma or simulator run.
- prompt-generation smoke also rejects stale installed Loupe skills in
  existing Codex/Claude skill folders, so fresh-worker results cannot silently
  use old skill guidance.
- replay-matrix freshness in the repository verification harness so changed
  replay summaries cannot silently leave
  `Docs/benchmarks/design-to-code/replays/matrix.md` stale.

The Loupe path should improve the final result, not just produce more logs.
Treat the benchmark as failed when the Loupe output has worse visual distance
than the no-Loupe baseline and the extra view-tree evidence did not lead to a
concrete structural or interaction advantage. In that case, update the skill or
CLI feedback loop before claiming Loupe improves design implementation quality.
Do not accept `compare-design` as the only success signal; it is structural and
property evidence, not a replacement for screenshot review and audit results.
For non-rectangular simulator screenshots, prefer `simctl io screenshot --mask
ignored` when available, and record any device, scale, or simulator chrome
caveat before visual scoring.

This benchmark is useful only when the Loupe result is produced from fresh
runtime evidence. A result produced from remembered fixes or prior screenshots
does not count as evidence that the CLI or skill improved agent performance.
When Loupe evidence leads to a source patch, the loop is not finished until the
patched source is relaunched and verified with a fresh report, screenshot,
screenshot-check output, and design comparison when a fixture exists.

Use `Docs/DesignToCodeBenchmark.md` for the current Figma Community seed
candidate pool and intake/scoring checklist.

Current benchmark status:

- `FIN001` completed as the first independently duplicated Figma Community
  A/B case. Loupe won the quality/proof score by reducing `compare-design`
  from 44 issues to 3 unexpected-node noise issues, while baseline won the
  compile-loop score because Loupe needed extra CLI/injector/app builds and
  its one runtime mutation was restored by UIKit layout.
- `TRV001` completed as the second independently duplicated Figma Community
  A/B case. It is a negative Loupe result: Loupe produced runtime reports,
  `compare-design`, and two effective mutations, but the final screenshot lost
  to the baseline because map crop/content, typography scale, sheet placement,
  and top controls remained visibly off. The baseline also won the compile-loop
  score once Loupe CLI and injector builds are counted.
- `PROD001` completed as a productivity/date-picker Community case. Loupe won
  quality after selecting the correct `390x844` viewport, proving one runtime
  frame mutation, and replaying against an expanded fixture at `matched=55`,
  `issues=1`. Baseline was also strong and still won compile-loop cost with
  two app builds versus Loupe's six total builds.
- `BKG001` completed as a banking transfer-contact Community case. Loupe won a
  bounded quality score by using `ui report`, `ui compare-design`, and one
  effective runtime frame mutation before reaching `matched=28`, `issues=0`;
  baseline still won compile-loop cost with four app builds versus Loupe's five
  total builds. The run also proved that shared Figma avatar assets can be
  valid PNGs but fully transparent, so bitmap asset content now needs an input
  check before assigning A/B workers.
- `S005-REPLAY-20260606121235` is the first replay with exact Codex worker
  token usage for both sides. Loupe won quality/proof (`issues=0` versus
  baseline `issues=38`), while baseline won compile-loop and token cost.
- `BKG001-REPLAY-20260606124951` is the first exact-token measured real
  Community replay. Loupe won quality/proof and loop cost
  (`2/2/2` build/install/launch versus baseline `7/5/2`) and used fewer exact
  worker tokens (`3,903,489` versus `7,198,517`). Its mutation batch selected
  ten frame suggestions but changed none, so it is not counted as a
  runtime-saved rebuild.
- `PROD001-REPLAY-20260606131822` is the second exact-token measured
  Community replay. Loupe won quality/proof (`matched=55`, `issues=4` versus
  baseline `matched=55`, `issues=57`), while baseline won compile-loop and
  token cost (`4/3/3` build/install/launch and `1,658,781` tokens versus
  Loupe's `5/5/5` and `7,455,004` tokens). No mutation suggestions were
  emitted, so this is not a runtime-saved rebuild.
- `PROD001-REPLAY-20260606192140` repeats the productivity/date case after
  syncing the installed skill and adding verification-fixture reuse guardrails. Loupe won
  quality/proof (`matched=55`, `issues=0`, `suggestions=0` versus baseline
  `matched=55`, `issues=61`, `suggestions=56`), while baseline still won loop
  cost (`4/3/3` versus Loupe's `4/3/4` plus one mutation) and exact token cost
  (`1,461,153` versus `4,021,520`). This confirms the guardrails reduced Loupe
  overhead from the earlier PROD001 replay, but not enough to claim token
  efficiency.
- `PROD001-REPLAY-20260607170000` is the first lint-clean replay with a
  quality-normalized token follow-up. Baseline won raw token and raw loop cost
  (`947,886` tokens and `1/1/1` build/install/launch versus Loupe's
  `2,416,905` tokens and `5/5/5`), but Loupe won quality (`55` matched, `0`
  issues) and quality-normalized token cost because the baseline reached
  `2,639,975` tokens after two correction rounds and still had `28` issues.
- `TRV001-REPLAY-20260606134323` is an exact-token measured travel/map replay.
  It differs from the earlier negative fresh replay: Loupe won structure/proof
  (`matched=16`, `issues=13` versus baseline `matched=15`, `issues=40`), loop
  cost tied at seven build/install/launch operations each, and baseline won
  token cost (`3,808,675` versus Loupe's `4,297,288`). Loupe ran a 6-change
  mutation batch, but this is not counted as a runtime-saved rebuild.
- `FOOD004-REPLAY-20260606140635` is an exact-token measured dense support-chat
  replay. Loupe won quality/proof (`issues=20` versus baseline `issues=22`)
  and loop cost (`3/3/2` build/install/launch versus baseline `4/3/3`), while
  baseline won token cost (`2,379,012` versus Loupe's `3,047,847`). Loupe ran a
  6-change mutation batch, but this is not counted as a runtime-saved rebuild.
- `FOOD004-REPLAY-20260606195549` repeats the dense support-chat case with the
  bounded-iteration prompt. Loupe won quality/proof after fixture expansion for
  required bottom chrome (`matched=25`, `issues=27` versus baseline
  `matched=20`, `issues=28` plus five missing bottom-tab nodes), while baseline
  won loop and token cost (`2/2/2` and `2,115,123` tokens versus Loupe's
  `3/3/3`, one 3-change mutation batch, and `4,503,789` tokens). The run
  exposed prompt echoing, memory lookup, and broad simulator-list output as the
  next context-overhead targets.
- `FIN001-REPLAY-20260606143203` is an exact-token measured finance replay.
  The first no-Loupe candidate was rejected as screenshot-only custom drawing.
  After one correction round, Loupe still won quality/proof (`matched=39`,
  `issues=1` versus baseline `matched=38`, `issues=73` default / `issues=50`
  tolerant), loop cost (`2/2/2` build/install/launch versus baseline `3/2/2`
  plus one correction), and token cost (`2,796,971` versus baseline
  `5,471,935`). No mutation suggestions were emitted, so this is not a
  runtime-saved rebuild.
- `FOOD001B-REPLAY-20260606152308` is an exact-token measured food-home replay.
  Baseline won visual quality, compile-loop cost, and token cost because it
  preserved target-derived food photos and finished at `1/2/2`
  build/install/launch with `2,493,331` tokens. Loupe won structural proof
  (`issues=35` default / `34` tolerant versus baseline `60` / `59`) and proved
  an 8-change mutation batch that reduced live issues from 37 to 29, but final
  imagery stayed synthetic and the batch did not save a rebuild.
- `EDU001-REPLAY-20260606181448` is an exact-token measured image-budget
  replay for the education course-detail case. Loupe won quality/proof
  (`matched=17`, `issues=5` versus baseline `matched=10`, `issues=42`) and
  loop cost (`2/2/2` build/install/launch versus baseline `3/3/2`), but
  baseline still won token cost (`1,574,969` versus Loupe's `3,213,843`). The
  replay used fewer Loupe image-output bytes than baseline, so the remaining
  token gap is not explained by repeated screenshot viewing alone.
- `YQ001-FRESH-20260608003529` is the first Desktop Figma MCP-derived iOS
  UIKit product-flow case. Loupe won quality/proof on the YumQuick live
  tracking screen (`issues=6` versus baseline `37`) and loop cost was
  effectively tied (`15` baseline loop ops versus `14` Loupe loop ops), with no
  measured token winner and no runtime-saved rebuild.
- `YQS001-FRESH-20260608010604` is the first iOS SwiftUI Figma case. Loupe won
  quality/proof by making the support-chat screen queryable with probe-backed
  evidence (`issues=0` versus baseline `24`), while baseline won loop cost
  (`7` loop ops versus Loupe's `15`).
- `YQ003-REPLAY-20260608070108` repeats the iOS SwiftUI path on the YumQuick
  Contact Us screen. Both sides produced target-close screenshots, but baseline
  stayed screenshot-only after two correction rounds (`nodes=6`,
  `visibleTexts=0`, `matched=0`, current `issues=29`). Loupe won
  quality/proof by adding a debug-only probe layer (`nodes=55`,
  `visibleTexts=36`, `matched=28`). After probe-layer placeholder style
  cleanup, the same snapshots compare at `0` Loupe issues versus baseline
  `29`. Loupe narrowly won loop cost (`11` loop ops versus baseline `12`). Its
  three live mutation probes changed runtime state but did not count as a
  saved rebuild.
- `YQ004-REPLAY-20260608073549` adds a Desktop Figma MCP-derived iOS UIKit FAQ
  accordion case. Both sides produced target-close native UIKit screens. Loupe
  won quality/proof with richer runtime evidence. After general system-font
  alias normalization and a corrected FAQ disclosure fixture, the same
  snapshots compare at `10` Loupe issues versus baseline `79`. Baseline won
  loop cost (`6` loop ops versus Loupe `19`) after Loupe needed one visual
  correction for bottom safe area/status chrome. This is a post-run compare
  cleanup, not a runtime-saved rebuild.
- `ADM002A-FRESH-20260608013416` is the first AppKit-only Figma desktop case.
  Baseline won both quality and loop cost (`issues=142` versus Loupe `150`,
  `5` loop ops versus `13`). The run exposed noisy AppKit audit behavior around
  passive styled card/footer backgrounds, which is now covered by unit tests.
- `ADM002A-REPLAY-20260608032754` repeats the AppKit dashboard after the audit
  fix and one Loupe correction round. Visual quality was close enough to count
  as a split result. Baseline still won loop cost (`8` loop ops versus Loupe
  `21`), but post-run tooling cleanup improves the evidence from the same
  snapshots: current compare-design reports `114` Loupe issues versus `132`
  baseline issues, and current audit reports `47` Loupe issues versus `61`
  baseline issues. The compare cleanup ignores non-tight native static text
  frame width and viewport-clipped root height noise; the audit cleanup ignores
  accessible passive ShapeView/background surfaces that only expose generated
  layer labels. This is a post-run tooling improvement, not a saved
  implementation loop.
- `ADMS001-FRESH-20260608020301` is the first macOS SwiftUI-only Figma desktop
  case. Loupe won quality/proof by making the SwiftUI-hosted dashboard
  inspectable (`issues=43` versus baseline `48`, with richer runtime evidence),
  while baseline won loop cost (`5` loop ops versus Loupe's `15`).
- `ADMS001-REPLAY-20260608054041` repeats the macOS SwiftUI dashboard with a
  leaner prompt. Both sides produced near-identical screenshots, but baseline
  remained runtime-sparse (`0` matched design nodes, `48` issues). With current
  compare-design cleanup, Loupe keeps all `48` design nodes matched and drops to
  `2` issues by normalizing macOS window-origin offsets for clipped descendants
  and treating transparent SwiftUI probe backing leaves as style-unavailable
  geometry probes. Baseline still won loop cost; this is a post-run tooling
  improvement, not a saved rebuild.
- Next independent Community cases should expand beyond the completed food,
  finance, travel, productivity, and banking files, or revisit rejected
  chat/commerce candidates only after MCP/manual evidence shows usable
  product-flow frames.

## Implemented

- Core unit tests use Swift Testing (`@Test`, `#expect`, `#require`).
- Native HID runtime action smoke:
  `Examples/LoupeExample/run-runtime-e2e.sh`
- Native HID repeated scenarios:
  `Examples/LoupeExample/run-native-scenarios.sh`
- Bookmark app-style E2E scenario:
  `Examples/LoupeExample/run-bookmark-e2e.sh`
- Platform build coverage:
  `scripts/verify-platform-builds.sh`
  - Covers LoupeKit and LoupeInjector builds for iOS Simulator, macOS, tvOS,
    visionOS Simulator, and watchOS Simulator.
- Linked macOS AppKit runtime E2E:
  `Examples/MacLoupeExample/run-macos-e2e.sh`
  - Covers runtime-backed AppKit button activation, workbench/detail/long-list
    route transitions, route trace artifacts, and route scroll offset probes.
- tvOS Simulator runtime and remote press E2E:
  `Examples/LoupeTVExample/run-tvos-runtime-e2e.sh`
  - Covers focus-driven remote press routing into detail and long-list screens,
    route trace artifacts, and scroll offset probes on routed scroll views.
- watchOS Simulator registered-probe runtime E2E:
  `Examples/LoupeWatchExample/run-watchos-runtime-e2e.sh`
  - Covers no-import SwiftUI probe registration through the notification
    bridge, runtime identity, accessibility export, logs, network evidence,
    refs, lifetime probes, and defaults/flags.
- Navigation pop by interactive edge gesture.
- Navigation push by Loupe selector tap.
- Navigation pop by Loupe ref tap.
- Routed fixtures for UIKit components, alerts, and mixed fixture tabs.
- Full-screen iPhone Simulator sizing through `LaunchScreen.storyboard`.
- Compact observation with interactive UIKit type/class identity.
- Separate view and accessibility trees:
  view tree is used for UIKit/layout/style validation, while accessibility tree
  is used first for selector-driven movement and input.
- Accessibility tree export and query:
  `loupe ui accessibility <snapshot.json>`, `loupe ui query --tree accessibility`,
  and `/accessibility`.
- Runtime `/accessibility` returns Loupe's view-derived accessibility tree by
  default, with native `UIAccessibility` container traversal kept behind
  `LOUPE_NATIVE_ACCESSIBILITY=1` while its simulator blocking behavior is
  stabilized.
- On-demand full node inspection:
  `loupe ui node <snapshot.json> --test-id <id>`
- Runtime inspection endpoint:
  `/inspect?testID=<id>`
- Bounded subtree inspection:
  `loupe ui subtree <snapshot.json> --test-id <id> --depth <n>` and
  `/subtree?testID=<id>&depth=<n>`
- Runtime waiting:
  `loupe act wait visible --test-id <id> --timeout <seconds>`,
  `loupe act wait gone --test-id <id>`, and
  `loupe act wait value --test-id <id> --key <path> --equals <value>`.
- Human-readable tree preview:
  `loupe ui tree [snapshot.json] --view|--accessibility --depth <n>`.
- Snapshot diff and trace summary:
  `loupe debug trace diff before-snapshot.json after-snapshot.json` reports appeared,
  disappeared, changed, and moved nodes; `loupe debug trace summary <trace-dir>`
  summarizes action target, errors, logs, target crop, and snapshot diff.
- Design comparison:
  `loupe ui compare-design snapshot.json figma-export.json` compares exported
  design nodes to a Loupe snapshot by `testID`, role/text, and geometry.
  `--suggest-mutations --host <url>` turns supported deltas into candidate
  `ui set` commands for runtime probing before source rebuilds.
  `loupe ui apply-design-suggestions <compare-design.json>` applies a small
  bounded set of those suggestions and saves before/after snapshots, responses,
  diff, and summary artifacts. Default selection is capped at three
  copy/style/scalar-first probes, with frame probing kept explicit or limited.
  Expected `role=view` matches role-less visible view containers, and
  switch-like compound controls can compare against close visual descendants so
  platform-owned `UISwitch` internals do not produce noisy parent frame/style
  suggestions.
- Skill installation:
  `loupe skills install` upserts the Loupe skill into existing Codex or Claude
  Code skill folders and skips missing clients.
- Runtime start wrapper:
  `loupe app launch --bundle-id <id> [--port <port>]` launches with injection and
  waits for the in-app Loupe server to answer `/runtime`.
- Cleanup:
  `loupe app cleanup` prunes stale runtime records and trace bundles older than 7
  days.
- Runtime registry:
  `loupe app list` lists known simulator hosts and live state.
- Runtime mutation:
  `loupe ui set --test-id <id> <property> <value>` posts a typed mutation to the
  injected server and reports whether the after snapshot reflects the
  allowlisted UIKit property change. Property mutations animate by default, and
  `--no-animate` verifies the immediate path. Layout-owned values may be
  restored by UIKit and must be judged by the effective state.
- Runtime collection/table self-sizing probe:
  `loupe ui set --try-self-sizing` reports `selfSizingProbe` for cell-contained
  mutations on iOS 16+. `Examples/LoupeExample/run-native-scenarios.sh` verifies
  that fixed collection item sizes are skipped, estimated flow-layout
  collection cells apply `enabledIncludingConstraints`, and repeated probes on
  the same container return `already-enabled` without another invalidation.
- Runtime mutation discovery:
  `loupe ui set --list` / `/mutations` exposes the active mutation property
  registry for agent planning.
- Runtime edit-to-code loop:
  `loupe ui set --output <mutation.json>`, `loupe ui node`, then
  `loupe ui reflect <mutation.json> --source <dir>` verifies a runtime edit and
  produces before/after summaries, hierarchy context, and source candidates for
  an agent-led code application step.
- Runtime identity handshake:
  `--udid <sim>` on runtime commands verifies that the contacted Loupe host belongs to
  the expected simulator before runtime commands use it.
- Injection communication:
  apps can post `dev.loupe.log` and `dev.loupe.viewMetadata` notifications to
  send custom logs and metadata without importing `LoupeKit`.
  `Examples/LoupeExample/run-injected.sh` verifies that the injected bridge
  captures an app-posted `dev.loupe.log`, that `loupe debug logs` can fetch it, and
  that view metadata is present in `loupe ui node` output.
- Basic action traces for public CLI actions:
  `--trace-dir <path>` saves before/after view snapshots, accessibility trees,
  runtime logs, screenshots, action records, and the resolved target query result
  around CLI actions.
- Scroll profiling:
  `loupe debug scroll` supports simulator gesture traces with `--from/--to` and
  runtime offset probes with `--delta` or `--to-offset` for linked/runtime
  platform runtimes.
- Failed runtime actions automatically save `error.json`, failure snapshot,
  accessibility tree, logs, screenshot, and action record under
  `/tmp/loupe-traces`.
- Action traces save `target-crop.png` when a resolved target frame is available.
- Basic layout audit:
  `loupe ui audit <snapshot.json>` and `/audit`
- Layout audit currently checks sibling overlap, child-outside-parent,
  duplicate test IDs, missing public interactive test IDs, small interactive
  targets, and low text contrast.
- UIKit component coverage for:
  labels, buttons, synthetic bar button items, switches, sliders, segmented
  controls, steppers, date pickers, page controls, progress views, activity
  indicators, image views, text fields, text views, scroll views, table views,
  collection views, picker views, tab bars, stack-backed rows, alerts, and
  styled design fixtures.
- Mixed fixture coverage for:
  a SwiftUI hosting screen, a `WKWebView`, a keyboard-heavy form, nested scroll
  views, and a full `UITabBarController` flow with synthetic `UITabBarItem`
  selectors.
- Bookmark app-style coverage for:
  tab bar navigation, list/detail navigation, favorites, search, add form text
  input, detail favorite state changes, `testID` tap, `ref` tap, text-tap
  rejection, automatic failure trace, selector inspection, and layout audit.
- Style capture for:
  background color, text color, border color, border width, corner radius,
  font name, and font size.

## Known Gaps

- `loupe ui audit` does not yet assert spacing, alignment, z-order intent,
  clipping, truncation, or typography rules.
- Compact observations expose UIKit identity, but component-specific properties
  intentionally require `loupe ui node`.
- `loupe ui node` returns `UIView`-common properties at `uiKit` top level and
  component-specific properties under nested objects such as `uiKit.stepper`,
  `uiKit.textField`, `uiKit.tabBar`, and `uiKit.webView`.
- Retry policies beyond explicit wait commands are not implemented yet.
- Native `UIAccessibility` traversal is opt-in and still needs guardrails before
  it can be part of the default runtime endpoint.
- Screenshot baseline diffing is not implemented yet.
- Native HID dispatch covers tap, drag, swipe, and US-keyboard text input.
- SwiftUI movement/input selectors are intentionally limited to elements exposed
  through the accessibility tree. Loupe does not synthesize selectors from
  private SwiftUI view-tree implementation details.
- Runtime mutation is strongest for text, color, visibility, layer styling, and
  control values. Frame, constraint, and list self-sizing edits are diagnostic
  unless the effective state confirms UIKit kept them.
