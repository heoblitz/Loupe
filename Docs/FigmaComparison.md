# Figma Comparison

Loupe does not call the Figma API directly. The comparison command consumes a
small exported design JSON produced by a plugin, script, or manual fixture.
Figma comparison is one fixture workflow built on the same runtime evidence used
for UI diagnosis and regression checks.

## Minimal Design JSON

```json
{
  "frame": {
    "name": "BookmarkDetail",
    "width": 402,
    "height": 874
  },
  "nodes": [
    {
      "id": "bookmark.detail.favorite",
      "aliases": ["detail.favoriteSwitch"],
      "name": "Favorite switch",
      "role": "switch",
      "frame": { "x": 325, "y": 282, "width": 63, "height": 28 },
      "style": {
        "backgroundColor": "#34C759",
        "cornerRadius": 14
      }
    }
  ]
}
```

## Matching Policy

Loupe matches design nodes in this order:

1. `testID` / accessibility identifier exact match by `id` or `aliases`.
2. Role plus exact visible text.
3. Role plus nearest center point.
4. Visual fallback by frame and size similarity.

Use `aliases` when the Figma/exported design id should stay stable but the app
uses a different accessibility identifier. This keeps comparison output tied to
the design node while still matching app-specific `testID` names.

## Runtime Evidence Loop

```bash
loupe ui report --bundle-id com.example.App --output loupe-report
loupe ui screen loupe-report/snapshot.json --limit 120
loupe ui tree loupe-report/snapshot.json --view --depth 6
loupe ui paint loupe-report/snapshot.json --point 201,319
loupe ui compare-design loupe-report/snapshot.json figma-export.json
loupe ui compare-design loupe-report/snapshot.json figma-export.json --suggest-mutations --host "$(jq -r .host loupe-report/summary.json)"
loupe ui compare-design loupe-report/snapshot.json figma-export.json --json
loupe ui compare-design loupe-report/snapshot.json figma-export.json --json --suggest-mutations > compare-design.json
loupe ui apply-design-suggestions compare-design.json --host "$(jq -r .host loupe-report/summary.json)" --snapshot loupe-report/snapshot.json --output-dir loupe-design-probes --max 3 --properties text,textColor,backgroundColor,cornerRadius,fontSize
loupe ui compare-design loupe-report/snapshot.json figma-export.json --json --color-tolerance 0.08 --corner-radius-tolerance 2
```

Use `ui report` when a design loop needs screenshot judgment and runtime
structure together. Use `ui screen` before formal comparison when an agent
needs a DOM-like runtime summary. Use `ui paint` when a visual target is
covered by an overlay, content view, blur view, or same-frame child.

## Reported Deltas

`ui compare-design` reports:

- missing design nodes
- unexpected app nodes
- role and text deltas on matched nodes
- frame deltas
- color deltas
- corner radius deltas
- font name and font size deltas

This is separate from screenshot baseline diffing. Figma comparison is for
structural and property drift; screenshot diffing is for pixel-level visual
regressions.

Do not use a zero-issue `compare-design` result as the whole acceptance gate.
It can miss simulator chrome, viewport mismatch, safe-area/background coverage,
media crops, contrast, touch-target, or visually worse layout tradeoffs. Treat
the final decision as screenshot review plus runtime audit plus comparison
counts. If comparison improves while the screenshot or audit gets worse, record
that split result and keep iterating.

Use style fields sparingly. In native-app comparisons, map the design's font
weight/size/color to the expected platform implementation and add tolerances
when minor color or radius differences are not meaningful. Do not tune
tolerances so high that real emphasis mistakes disappear.

For SwiftUI or AppKit probe-backed evidence, compare-design treats transparent
probe backing views and 1pt placeholder text styles as structural evidence, not
visual style evidence. Use the screenshot and audit output to decide whether the
rendered UI actually matches the design.

Use `--suggest-mutations` when a Loupe-assisted implementation loop needs to
test small fixes before rebuilding. Suggestions are runtime probes for text,
frame, color, corner radius, and font size deltas; verify the effective state
with a fresh report/node before patching source.

Use `ui apply-design-suggestions` when several low-risk suggestions should be
probed before a rebuild. It reads `compare-design --json` output and writes
before/after snapshots, mutation responses, diff, and a summary so the agent
can see which runtime changes were effective.

Suggestion batches default to at most three probes, try text/style/scalar
suggestions first, and include at most one frame suggestion when non-frame
probes exist. Prefer an explicit text/style property filter for pre-rebuild
checks. Use `--max 1 --properties frame` only when frame probing is intentional,
and run the batch while the compared runtime is still live. A post-fix dry-run
only proves which suggestions would be selected; it does not prove effective
runtime state.

Spacing and alignment deltas between matched siblings are planned follow-ups.
