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

## Grand Hotel skin (2026-09)

The menu is dressed as the lobby of a grand hotel: black marble, hairline gold, a crystal chandelier.

- `src/shared/HotelSkin/` — runtime skin applied by `UITheme` at load (`init.luau` adapter,
  `Lobby.luau` lobby scene and page furniture, `Ornaments.luau` drawing parts, `MotifSkinKit.luau` +
  generated `MotifSpec.luau`). It only recolours/re-fonts and adds `Hotel*` children; every name the
  contract test pins is unchanged. If the folder is missing or errors, the original theme stays.
- `tools/test_hotel_skin.luau` — Lune test of the look (palette, no sticker parts, CTA prominence,
  directory plaques, veil, reduced motion, fallbacks): `lune run tools/test_hotel_skin.luau`.
- `tools/dump_menu.luau` + `tools/render_preview.py` — build the real menu in Lune and render it
  to HTML/PNG with headless Chrome (plus a text-fit / touch-size audit):
  `lune run tools/dump_menu.luau . 1280 720 lobby menu.json` then
  `python tools/render_preview.py menu.json menu.html --png menu.png --audit audit.json`.
