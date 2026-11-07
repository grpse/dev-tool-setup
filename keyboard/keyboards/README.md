# Keyboard models

`catalog.json` populates the viewer's keyboard dropdown. The default is `mx-keys-mini-us`.

Each model has its own folder and `keyboard.json`. The definition supplies its `id`, `name`, `rail`, `keys`, and `art`. The current default is stored in `mx-keys-mini-us/keyboard.json`; its artwork is embedded there so the model is portable. The viewer also embeds this default as a fallback when opened directly as a file or when the catalog cannot be loaded.

To add a keyboard:

1. Add `keyboards/<model-id>/keyboard.json` using the existing definition as the schema.
2. Add `{ "id": "<model-id>", "name": "Display name", "definition": "keyboards/<model-id>/keyboard.json" }` to `catalog.json`.
3. Reload the viewer. Selecting the new entry loads that definition and resets pan/zoom.

Key coordinates use the existing normalized 1360 × 600 keyboard canvas within the 2443 × 1374 stage. Key kinds are `standard`, `function`, `wide`, `modifier`, `space`, and `arrow`. Each printed legend supplies ink bounds in key-local source coordinates. Set `rail` to `false` for a model without the upper Logitech rail. Asset values in `art` may be data URLs or paths relative to that model's JSON file. The original reference belongs in `art.reference` and is displayed only in adjustment mode.
