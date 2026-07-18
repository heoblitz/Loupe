# Actions And Mutations

Use this only when the task needs input, trace proof, mutation, self-sizing, or
source reflection.

## Action Shapes

```bash
$LOUPE act targets --host <host>
$LOUPE act tap '#2' --host <host>
$LOUPE act perform '#4' increment --host <host>
$LOUPE act tap --host <host> --snapshot <snapshot.json> --ref n21 --udid <sim-udid> --trace-dir <trace-dir>
$LOUPE act tap --host <host> --x 201 --y 274 --width 438 --height 954 --udid <sim-udid> --trace-dir <trace-dir>
$LOUPE act swipe --host <host> --from 219,760 --to 219,190 --udid <sim-udid> --trace-dir <trace-dir>
$LOUPE act drag --host <host> --from 350,240 --to 80,240 --udid <sim-udid> --trace-dir <trace-dir>
$LOUPE act input '#3' "hello" --host <host> --udid <sim-udid>
$LOUPE act wait value --host <host> --test-id feed.list --key uikit.scrollView.contentOffset.y --equals 80 --output <wait.json>
$LOUPE debug trace summary <trace-dir>
```

Use one fresh trace directory per attempt.

Use `act targets` for movement and `ui report` for view analysis. `#N` aliases
come from visible, enabled, interactive accessibility nodes. Quote the alias;
it is consumed after a successful dispatch, so list targets again before the
next alias action.

## Proof Rules

- Refs are snapshot-scoped. Recapture before acting when the screen may have
  changed, or pass `--snapshot` when acting on a saved ref.
- For commands that must choose one target, do not silently pick the first
  role/text match. If multiple current-screen actionable targets match, inspect
  candidates and rerun with `testID`, current `ref`, node, or hit-test evidence.
- Prove action results with trace summary/diff plus fresh report, screenshot,
  query, node, content offset, log, default, focus, or state evidence.
- System permission alerts are outside the app runtime tree. Use screenshot or
  host/simulator evidence; do not claim an app query tapped the alert.
- `act input` focuses the saved target before writing; focusing can select existing
  text, so typing may replace instead of append. Traces redact requested input,
  so prove the final value with a fresh report/query/node and never raw
  secrets.
- Secure inputs may still query as `textField`; prove security with
  `uikit.textField.isSecureTextEntry` and redacted text/value evidence.
- `act wait`, `act drag`, and `debug scroll` need explicit postconditions:
  selector, key or coordinates, output/trace path, expected state, and fresh
  after-proof.
- iOS/tvOS simulators use native HID. macOS tap is AppKit control activation.
  watchOS, visionOS, and custom SwiftUI surfaces may correctly fail unless
  trace/screenshot/report/probe/state evidence proves otherwise.

## Mutations

```bash
$LOUPE ui mutations --host <host>
$LOUPE ui compare-design <report/snapshot.json> <design.json> --suggest-mutations --host "$(jq -r .host <report>/summary.json)"
$LOUPE ui compare-design <report/snapshot.json> <design.json> --json --suggest-mutations > <compare.json>
$LOUPE ui apply-design-suggestions <compare.json> --host <host> --snapshot <report/snapshot.json> --output-dir <design-probes> --max 3
$LOUPE ui apply-design-suggestions <compare.json> --snapshot <report/snapshot.json> --dry-run --output-dir <design-probes>
$LOUPE ui set --host <host> --snapshot <snapshot.json> --ref n21 textColor --color '#ff3366' --no-animate --output <set.json>
$LOUPE ui set --host <host> --test-id cell.title layout.hugging.horizontal 260 --try-self-sizing --no-animate
$LOUPE ui set-many --host <host> --refs n21,n22 alpha --number 0.5 --trace-dir <trace-dir>
$LOUPE ui reflect <set.json> --source <source-root> --output <reflect.json>
```

- `ui mutations` lists live capabilities; it does not take a selector.
- Prefer app-owned `testID`; use `ref` only from the current screen or with the
  source snapshot for saved-ref mapping.
- Dynamic table/collection cells can reuse refs. Mutate a current ref
  immediately, save the mutation response, inspect requested/effective state,
  and reflect that exact output.
- Use mutation to narrow small scalar fixes before a rebuild: text color,
  alpha, font size, hugging/compression, simple spacing constraints, or one
  visible label/control frame. Capture before/after reports and patch source
  only after the effective state proves the direction.
- When design JSON is available for the current target, prefer
  `compare-design --suggest-mutations` as the first suggestion list. Try a
  small, low-risk probe and keep the mutation response path so `ui reflect`
  can point back to likely source lines.
- Use `ui apply-design-suggestions` when several low-risk suggestions should be
  probed before a rebuild. Keep the batch small: default selection is capped at
  three suggestions, prioritizes text/style/scalar changes, and includes at
  most one frame probe when scalar/style suggestions exist. Prefer explicit
  `--properties text,textColor,backgroundColor,cornerRadius,fontSize` first;
  try `--max 1 --properties frame` only when frame drift is the useful signal.
  Inspect `summary.json`, response files, and a fresh compare/report before
  deciding which source constants to patch.
- Use `--dry-run` only for offline selection checks. It writes
  `selected-suggestions.json` and `summary.json`, but no response files and no
  effective-state proof.
- Use `--no-animate` for deterministic verification. Frame and Auto Layout
  mutations are probes until a fresh `ui node` confirms effective state.
- `--try-self-sizing` is conservative. `applied` means Loupe invalidated a
  supported list context; skip reasons such as `collection_layout_sizing_unknown`
  or `delegate_size_for_item_owns_cell_size` are bounded results.
- `ui reflect` returns ranked source hints, not an automatic patch. Empty
  candidates or weak bridge hints can be correct; compare them with the
  observed hierarchy before patching.
- Treat mutation-only state as temporary. Carry it back to source only when the
  effective state proves the direction, `ui reflect` gives a plausible source
  hint, or the probe explains why a runtime-only fix is unsafe.
