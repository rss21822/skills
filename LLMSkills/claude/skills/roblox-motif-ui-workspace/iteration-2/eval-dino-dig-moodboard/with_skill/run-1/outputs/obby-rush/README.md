# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `src/client/DigSite/` — the "Lost Valley Dig" skin (dinosaur dig in the jungle): `DinoDigSkin.luau` recolours
  `UITheme` at runtime and dresses the menu (amber PLAY, field-notes pages, fossil-slab nav, specimen-label shop);
  `MotifSpec.luau` is generated from `dino-dig-skin.spec.json` by the roblox-motif-ui skill (do not hand-edit);
  `MotifSkinKit.luau` is the skill's unchanged helper kit. If the skin cannot load, the menu builds with the plain theme.
- `skin-tests/` — `lune run skin-tests/test_dino_dig_skin.luau` (skin checks), `lune run skin-tests/compile_check.luau`,
  and `python skin-tests/make_previews.py --out <dir>` (renders the real instance tree to HTML/PNG + layout audit).
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
