# React keyboard

Open `index.html` directly or serve this directory. It is a self-contained HTML file: React 18.3.1, ReactDOM 18.3.1, Babel Standalone 7.26.10, CSS, TSX, icons, logo, and comparison reference are embedded. No network connection or build step is required to run it.

Edit the inline `<style>` and `<script id="keyboard-source" type="text/tsx">` blocks. `KEY_DATA` describes the 79 keys. `KEY_TYPES` maps each kind to one reusable component: `StandardKey`, `FunctionKey`, `WideKey`, `ModifierKey`, `SpaceKey`, and `ArrowKey`. All use `KeyFrame` for placement, focus, and selection. Keycaps, dishes, shadows, and characters are HTML/CSS; only the original function icons and logo use images.

Babel strips TypeScript syntax and compiles JSX on load; it does not perform TypeScript type checking. Comparison controls and key selection use React state.

The separate assets and extraction tools are retained as reference materials. Running `tools/extract-assets.py` exports the old image-based markup to `tools/extracted-layout.html`; it does not overwrite the React app. The former `style.css` and `effects.js` are not loaded by the single-file app.
