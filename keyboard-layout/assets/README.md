# Original keyboard artwork

Extracted from `../reference.webp` at its original 2443 × 1374 resolution.

- `icons/`: 15 separate transparent function-key icons used by the page.
- `keys/`: 79 key surfaces with the bright printed artwork removed and each key's original outline preserved in alpha, including the horizontal ANSI Enter and wide left Shift.
- `legends/`: printed characters and secondary markings, positioned in the original key coordinate system. Function icons are separate from these layers.
- `chassis.png`: continuous source chassis with transparent holes for the individual keys.
- `manifest.json`: source coordinates, dimensions, labels, and icon paths. Coordinates are relative to the keyboard origin at source pixel (542, 390).

The page composites the surface, legend, and icon layers individually. Key dimensions are trimmed to the detected socket bounds, preserving the source gaps without crop padding. Source imagery limits sharpness when zoomed beyond its original resolution.

Regenerate from the repository root using Python 3 and ffmpeg:

```sh
python3 keyboard-layout/tools/extract-assets.py
```

The extraction script reads `tools/layout-template.html` and writes `index.html` and these PNG assets. Change the template when changing the layout's markup.
