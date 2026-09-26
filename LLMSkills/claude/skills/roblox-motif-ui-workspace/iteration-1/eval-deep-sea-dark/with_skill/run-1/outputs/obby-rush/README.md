# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `src/client/ui/DeepSeaSkin.luau` — the "Abyss Lantern" deep-sea skin: recolours/wraps UITheme at runtime and
  dresses the menu (anglerfish + lure-lit PLAY, jellyfish dock, page ribbons, bubbles). Presentation only;
  `MainMenu.build` applies it inside `pcall` and falls back to the plain theme if it fails.
- `src/client/ui/MotifSkinKit.luau` (skin helpers) and `src/client/ui/MotifSpec.luau` (generated from
  `design/deep-sea.skin.json` by roblox-motif-ui's `skin_preview.py`; edit the JSON, not the Luau).
- `tests/test_deep_sea_skin.luau` — Lune test of the skin (looks, page/scrim sync, layout, reduced motion,
  fallback). Run: `lune run tests/test_deep_sea_skin.luau`.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
