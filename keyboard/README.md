# React keyboard

Open `index.html` directly or serve this directory. It is a self-contained HTML file: React 18.3.1, ReactDOM 18.3.1, Babel Standalone 7.26.10, CSS, TSX, icons, logo, and comparison reference are embedded. No network connection or build step is required to run it.

Edit the inline `<style>` and `<script id="keyboard-source" type="text/tsx">` blocks. `KEY_DATA` describes the 79 keys. `KEY_TYPES` maps each kind to one reusable component: `StandardKey`, `FunctionKey`, `WideKey`, `ModifierKey`, `SpaceKey`, and `ArrowKey`. All use `KeyFrame` for placement, focus, and selection. Keycaps, dishes, shadows, and characters are HTML/CSS; only the original function icons and logo use images.

Babel strips TypeScript syntax and compiles JSX on load; it does not perform TypeScript type checking. Comparison controls and key selection use React state.

The separate assets and extraction tools are retained as reference materials. Running `tools/extract-assets.py` exports the old image-based markup to `tools/extracted-layout.html`; it does not overwrite the React app. The former `style.css` and `effects.js` are not loaded by the single-file app.

Key legends use SVG outlines derived from the embedded Quicksand Light font, with DejaVu Sans for symbols missing from that font. The outlines are embedded in the page and saved in `keyboards/mx-keys-mini-us/glyphs.json` for editing. Each path is fitted to its source-measured ink bounds. The original embedded font remains as a fallback for legends added by other models. The Quicksand OFL is embedded in the HTML; the DejaVu license accompanies the glyph data.

Regenerate reference bounds with `python3 keyboard/tools/register-legends.py` from the repository root. This updates the inline key data; the served default model definition must also be updated when changing the layout. The old text alignment audit in `tools/verify-legend-alignment.js` applies to fallback text, not the SVG paths.

Word labels are registered character by character so matching an overall word box cannot conceal internal spacing or baseline differences. The current dataset has 174 printed targets; both Shift labels have five independent character targets.

The viewer now lives in `keyboard/`. Its keyboard picker reads `keyboards/catalog.json`; each model has its own folder and definition. See `keyboards/README.md` for adding another model. The MX Keys Mini US layout is the default. The served viewer loads its default model from the catalog, while direct-file use retains the embedded default.

Scroll over the canvas to zoom smoothly around the pointer (0.4×–5×). Drag any background or non-interactive keyboard surface to pan; key clicks retain their selection behavior. Double-click the background to fit the keyboard again, or focus the canvas and press `0`. Resizing the viewport also restores the fitted view. Reduced-motion preferences disable zoom interpolation.

Comparison controls and the reference image are excluded from the normal page. Open `index.html?adjust=1` (or `http://localhost:8765/?adjust=1`) to show HTML, overlay, reference, and Difference controls for future adjustments.

The lighting layer generates a height field and normal map from the active keyboard's key geometry, then renders an orthographic 3D mesh with WebGL. A shader applies mouse-following diffuse and specular light and traces height-field shadows for the point light and 45-degree directional light. The HTML keyboard remains interactive beneath the transparent lighting canvas. If WebGL is unavailable, the keyboard remains usable without that lighting layer.
