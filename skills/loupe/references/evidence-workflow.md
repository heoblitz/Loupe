# Evidence Workflow

Use this when deciding what Loupe evidence proves and what to capture next.

## Capture

```bash
$LOUPE ui report --host <host> --output /tmp/loupe-report
$LOUPE ui query /tmp/loupe-report/snapshot.json --test-id target.id
$LOUPE ui node /tmp/loupe-report/snapshot.json --ref n21
```

Saved snapshots are positional arguments for read-only `ui` commands; reserve
`--snapshot` for ref-based actions and mutations. `ui report` writes JSON plus
screenshots when supported; macOS host runtimes may need JSON-only proof.

## Visibility And Targeting

- Prefer `testID` when available. Use text/role for discovery, then switch to
  stable `testID` or current-snapshot `ref`.
- Raw `isVisible` can include dismissed sheets or reused offscreen cells. For
  current-screen claims, use default `ui query`, `compact`, `screen`, `audit`,
  hit-test evidence, screenshots, or a fresh report.
- `ui hit-test` and `ui responder-chain` are live-runtime evidence; pass
  `--host`, `--udid`, or `--bundle-id`, not a saved snapshot path.
- If overlays, alerts, menus, sheets, or keyboards may cover a target, hit-test
  before acting and recapture after acting.
- If screenshot-visible controls are missing from default query, inspect with
  `--include-hidden`, hit-test/focus the point, then prove state with trace plus
  fresh report/screen/node evidence.

## Design Implementation Evidence

- Use the target screenshot or selected design frame as the visual target, then
  choose the simulator/device viewport before detailed source work.
- After meaningful source changes, capture a fresh `ui report`; inspect the
  current screen with `ui screen`, `ui query`, and `ui node`.
- If design JSON is available for the current target, run
  `ui compare-design <snapshot.json> <design.json>` for role, text, frame,
  color, corner-radius, and font drift. Keep screenshot judgment for
  pixel-level fidelity, media crops, and platform chrome.
- Match identifiers to the design node's visual bounds. Text-node identifiers
  should be on the actual label, not on a wider row, column, card, or stack
  container. Use separate identifiers for backgrounds, dividers, icons, and
  cards when the design names those nodes.
- If `compare-design` improves while the screenshot looks worse, record a
  split result and keep iterating on visual fidelity. Structural proof is not
  visual proof.
- Never accept a better structural score by truncating visible text. Unless the
  target itself has ellipsis, the final screenshot should show complete target
  labels; record any compare-design tradeoff needed to keep text readable.
- For photo-heavy, map-heavy, or avatar-heavy targets, preserve provided assets
  or target-derived non-text media crops before synthetic placeholders. Native
  structure does not compensate for visibly wrong product imagery.
- Use `ui set`, `ui compare-design --suggest-mutations`, or
  `ui apply-design-suggestions` only as live probes for small, local deltas.
- Verify a probe with fresh report/node/effective-state evidence, then patch
  source, relaunch, and recapture. Mutation-only state is not final proof.

## SwiftUI And Bridges

- Screenshot-visible text, buttons, metadata, or rows may be absent from both
  view and accessibility text queries. Treat that as a semantic boundary, not a
  blank app.
- Claim queryability only when `ui query`, `ui screen`, a stable accessibility
  ID, or a probe proves it.
- Use bridge controls, hit-tests, coordinate traces, screenshots, app-authored
  probes, logs, or defaults to prove workflows.
- For SwiftUI design checks, prefer real accessibility identifiers first. If
  the raw hosting tree is sparse, add minimal debug-only probes to expose
  intended bounds and identifiers, then record that comparison is probe-backed.
  Probe-backed `compare-design=0` is structural proof, not visual proof.
- Transparent probe overlays can create overlap or small-target audit noise.
  Separate that synthetic noise from real visual, accessibility, and interaction
  issues in the result.
- Treat `ui audit` on SwiftUI-hosted internals as triage. Empty
  `ui reflect sourceCandidates` can be correct for framework wrappers or
  synthetic probes.

## App-Authored Probes

- Import path: public `.loupeProbe(...)` from `LoupeKit`.
- No-import path: local `UIViewRepresentable`/`NSViewRepresentable` fallback
  with accessibility identifier/label/traits.
- Notification path: post `dev.loupe.probe` / `dev.loupe.removeProbe` with
  measured bounds. Synthetic nodes are structural locators, not platform views,
  so activation and mutation can correctly fail.
- Probe payload keys: `id`, `label`, `role`, `frame` with `x/y/width/height`,
  and optional `isInteractive`.

## Diagnostics

For no-import runtime logs, post `dev.loupe.log` with `["message": "..."]`,
then collect with `debug logs --host <host> --output <logs.json>`.

`debug network` collects app-authored `dev.loupe.network` events and LoupeKit
fixture URLProtocol events; it is not a general packet sniffer.

Use `debug refs`, `object-graph`, `leaks`, `keychain`, `defaults`, or `flags`
only when the app or task contract names that evidence/key. These are
app-scoped diagnostics; empty output can be a valid bounded result.
