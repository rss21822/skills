# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button, tag).
  Theme: "Retro Toy Box" (cream paper, chocolate-brown outlines, mustard / teal / coral / sky / mint toys).
- `src/shared/ToyDecor.luau` — the toy decorations drawn from plain Frames/TextLabels (striped awning,
  confetti, donut, stars, robot, small icons).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
