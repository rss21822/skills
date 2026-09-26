# Obby Rush (UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`).

- `src/shared/UITheme.luau` — the 夏祭りの縁日 theme: palette, fonts and the helpers every screen uses (panel, label,
  button with a pressable face/lip, gradients, tweens that respect reduced motion).
- `src/shared/FestivalArt.luau` — festival illustrations built from Frames (lanterns, goldfish, candy apples, ramune,
  coin, noren curtain, ramune switch...). No image assets.
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages.
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
