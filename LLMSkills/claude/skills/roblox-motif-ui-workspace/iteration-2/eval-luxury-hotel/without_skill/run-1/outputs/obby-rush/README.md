# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — "Grand Hotel" theme (black marble, antique gold, serif + spaced small caps):
  colours, fonts and the helpers every screen uses (panel, label, caption, button, rule, diamond, coin, switch).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages. `MainMenu.layout` fits the pages to the viewport.
- `src/client/LobbyBackdrop.luau` — decorative lobby behind the menu (chandelier, marble veins, gold pilasters).
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
