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

## Look: "Ennichi" summer-festival skin

The menu wears a dusk-fair skin (paper lanterns, goldfish scooping, candy apples, ramune). It only changes
looks; every name, parent and callback above is unchanged.

- `design/ennichi-skin.json` — the palette / fonts / goldfish mascot (source of truth). Regenerate the Luau
  spec after editing it: `python <roblox-motif-ui>/scripts/skin_preview.py design/ennichi-skin.json
  --html board.html --png board.png --luau src/client/Ennichi/EnnichiSpec.luau` (also lints contrast,
  fonts and emoji).
- `src/client/Ennichi/EnnichiSkin.luau` — runtime adapter: rewrites `UITheme.colors` in place and wraps
  `panel` / `label` / `button` / `stroke`, so any screen built with UITheme gets the skin. Idempotent;
  restores the plain theme if it fails.
- `src/client/Ennichi/EnnichiScene.luau` — dresses the main menu (lantern string, PLAY as the big lantern,
  stall counter and stall-front tiles, noren page headers, price tags, switches, empty-state scenes).
  Adds only `Motif*` instances and removes them again if anything throws.
- `src/client/Ennichi/MotifSkinKit.luau` (shared kit, do not edit) and `EnnichiSpec.luau` (generated).
- `tests/test_ennichi_skin.luau` — the skin applies, keeps the contract, reacts (tabs, switches, press),
  lays out at 1280x720 / 1080x720 / 828x369 / 366x820, honours reduced motion and falls back cleanly.
- `tools/ui_preview/` — without Studio: `lune run tools/ui_preview/dump_menu.luau out` then
  `python tools/ui_preview/render_preview.py out previews` draws the real menu tree in headless Chrome and
  audits text fit / 48 px targets / off-screen / overlaps. `studio_ui_audit.luau` is the same audit for
  Studio (Play, then run it on the Client).

Coins now read `💰 1,250`: the old `🪙` is a Unicode 13 emoji that Roblox draws as an empty box.
