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

1. `testID` / accessibility identifier exact match.
2. Role plus exact visible text.
3. Role plus nearest center point.
4. Visual fallback by frame and size similarity.

## Runtime Evidence Loop

```bash
loupe ui report --bundle-id com.example.App --output loupe-report
loupe ui screen loupe-report/snapshot.json --limit 120
loupe ui tree loupe-report/snapshot.json --view --depth 6
loupe ui paint loupe-report/snapshot.json --point 201,319
loupe ui compare-design loupe-report/snapshot.json figma-export.json
loupe ui compare-design loupe-report/snapshot.json figma-export.json --json
```

Use `ui report` when a design loop needs screenshot judgment and runtime
structure together. Use `ui screen` before formal comparison when an agent
needs a DOM-like runtime summary. Use `ui paint` when a visual target is
covered by an overlay, content view, blur view, or same-frame child.

## Reported Deltas

`ui compare-design` reports:

- missing design nodes
- unexpected app nodes
- frame deltas
- color deltas
- corner radius deltas
- font name and font size deltas

This is separate from screenshot baseline diffing. Figma comparison is for
structural and property drift; screenshot diffing is for pixel-level visual
regressions.

Spacing and alignment deltas between matched siblings are planned follow-ups.
