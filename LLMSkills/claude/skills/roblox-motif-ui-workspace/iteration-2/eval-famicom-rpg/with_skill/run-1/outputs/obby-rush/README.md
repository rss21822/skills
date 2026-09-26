# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `src/client/ui/` — Famicom RPG skin: `FamicomSkin.luau` (runtime skin over UITheme + title-screen layout
  for the main menu), `FamicomSpec.luau` (generated from `design/famicom-rpg.skin.json`, do not hand-edit),
  `MotifSkinKit.luau` (shared helpers). MainMenu loads it guarded; without it the menu builds as before.
- `tools/` — `test_famicom_skin.luau` (skin test), `compile_all.luau`, `dump_gui.luau` + `render_preview.py`
  (preview PNG/HTML from the real Luau output). Run from this folder, e.g. `lune run tools/test_famicom_skin.luau`.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
