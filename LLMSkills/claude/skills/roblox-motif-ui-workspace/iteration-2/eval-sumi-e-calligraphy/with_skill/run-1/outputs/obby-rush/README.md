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

## Skin: Sumi & Washi (水墨画と書道)

The menu is drawn in ink on washi paper with one vermilion seal. It is a runtime skin: `UITheme.luau` is
not edited; `MainMenu.build` calls `Skin.apply(Theme)` first and `Skin.decorate(gui)` last, both in
`pcall`, so if the skin is missing or fails the menu builds with the plain theme.

- `src/client/ui/SumiSkin.luau` — the adapter (palette swap, panel/label/button wrappers) and the main
  menu composition. Only presentation changes; names, callbacks and page logic stay as built.
- `src/client/ui/SumiParts.luau` — brush strokes, ensō, misty peaks, seals, the ink coin, scroll mounting.
- `src/client/ui/MotifSkinKit.luau` — shared skin helpers (fonts, tweens with reduced motion, top bar).
- `src/client/ui/MotifSpec.luau` — generated from `skin/sumi-e.spec.json`; edit the JSON and regenerate
  with `python <roblox-motif-ui>/scripts/skin_preview.py skin/sumi-e.spec.json --luau src/client/ui/MotifSpec.luau`.
- `skin/test_sumi_skin.luau` — skin tests (palette: ink/washi/vermilion only, one seal per view, states,
  reduced motion, fallback). Run from this folder: `lune run skin/test_sumi_skin.luau`.
