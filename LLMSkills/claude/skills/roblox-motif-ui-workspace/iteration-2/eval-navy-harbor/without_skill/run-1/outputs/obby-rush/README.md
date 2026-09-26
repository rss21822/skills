# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`). Theme: **night harbour & navy**
(navy / white / red, brass hardware, signal flags, rope) — see `../DESIGN.md`.

- `src/shared/UITheme.luau` — palette, fonts, motion helpers and the helpers every screen uses (panel, label, button,
  piping, gradient). The legacy `Theme.colors` keys and helper signatures are kept; new options are optional.
- `src/shared/NavalMotif.luau` — the ornaments: International Code signal flags, brass portholes and coins, laid rope,
  rope coil, sailor-collar stripes, neckerchief knot.
- `src/client/HarborBackdrop.luau` — the night-harbour scenery behind the menu.
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.
- `tools/preview/` — preview tooling, not synced by Rojo: `dump_tree.luau` builds the real menu through the test mock
  and dumps the instance tree; `render.py` lays it out as HTML; `build_previews.py <outDir> [--before <oldProject>]`
  screenshots it with headless Chrome.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
