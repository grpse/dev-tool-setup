# React keyboard

Open `index.html` directly or serve this directory. It is a self-contained HTML file: React 18.3.1, ReactDOM 18.3.1, Babel Standalone 7.26.10, CSS, TSX, icons, logo, and comparison reference are embedded. No network connection or build step is required to run it.

Edit the inline `<style>` and `<script id="keyboard-source" type="text/tsx">` blocks. `KEY_DATA` describes the 79 keys. `KEY_TYPES` maps each kind to one reusable component: `StandardKey`, `FunctionKey`, `WideKey`, `ModifierKey`, `SpaceKey`, and `ArrowKey`. All use `KeyFrame` for placement, focus, and selection. Keycaps, dishes, shadows, and characters are HTML/CSS; only the original function icons and logo use images.

Babel strips TypeScript syntax and compiles JSX on load; it does not perform TypeScript type checking. Comparison controls and key selection use React state.

The separate assets and extraction tools are retained as reference materials. Running `tools/extract-assets.py` exports the old image-based markup to `tools/extracted-layout.html`; it does not overwrite the React app. The former `style.css` and `effects.js` are not loaded by the single-file app.

Text registration uses `RegisteredLegend` and source-measured `legends` in each key specification. These remain native HTML text, with per-label transforms matching the printed ink bounds rather than the font's line boxes. Canvas measures the embedded font; a zero-size DOM baseline probe accounts for browser text layout. The six key components share `PrintedLegends`.

Regenerate reference bounds with `python3 keyboard-layout/tools/register-legends.py` from the repository root. The script updates the inline key data without replacing the React components or CSS. `tools/verify-legend-alignment.js` is a read-only browser audit for the rendered positions. The last measured result is in `tools/legend-alignment-report.json`; this measures positioning rather than pixel-identical font outlines.

Word labels are registered character by character so matching an overall word box cannot conceal internal spacing or baseline differences. The current dataset has 174 printed targets; both Shift labels have five independent character targets.
