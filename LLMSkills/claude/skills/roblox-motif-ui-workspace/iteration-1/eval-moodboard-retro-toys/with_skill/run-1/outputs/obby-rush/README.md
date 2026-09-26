# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.

Look: the "Retro Toy Box" skin (from the retro-toys mood board) is applied on top of the plain Theme build.

- `design/retro-toy-skin.json` — the skin spec (palette, fonts, shapes, icons, robot mascot). Regenerate
  `src/client/MenuSkin/MotifSpec.luau` from it with the roblox-motif-ui `skin_preview.py --luau`; do not edit MotifSpec by hand.
- `src/client/MenuSkin/` — `MotifSkinKit` (skin helpers), `MotifSpec` (generated), `RetroToySkin` (applies the look to the
  `MainMenu` ScreenGui; presentation only, falls back to the plain menu if it fails). `UITheme` itself is unchanged.
- `tests/test_menu_skin.luau` — Lune test of the skin (applies, keeps every path of the plain build, no old navy, faces,
  hover/press, page/toggle state, reduced motion, fallback). Run: `lune run tests/test_menu_skin.luau`.
