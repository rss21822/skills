# NIGHT WARD — 廃病院からの脱出 (formerly Obby Rush; UI sample)

A small Roblox obby game's main menu, built with Rojo (`default.project.json`), rebranded as a
kid-safe horror obby: escape an abandoned hospital at night.

- `src/shared/UITheme.luau` — colours, fonts and the helpers every screen uses (panel, label, button).
  Same API as before; the palette now comes from `Motif/MotifSpec`.
- `src/shared/Motif/MotifSpec.luau` — generated from `design/night-ward.skin.json` (edit the JSON, then
  regenerate with the roblox-motif-ui skill's `scripts/skin_preview.py spec.json --luau MotifSpec.luau`).
- `src/shared/Motif/MotifSkinKit.luau` — presentation helpers (fonts, contrast-safe text colour, motion
  with reduced-motion support, top-bar inset).
- `src/client/MainMenu.luau` — builds the `MainMenu` ScreenGui: top bar (title, coins), PLAY, a nav bar
  (Shop / Inventory / Quests / Settings) and the four pages. Names, hierarchy and callbacks unchanged.
- `src/client/NightWardArt.luau` — the NIGHT WARD look layered onto that menu: the 非常口 exit-sign
  CTA, clipboard charts, room-number door plates, the corridor backdrop, responsive layout and motion.
  Every step runs in pcall; if it fails the plain themed menu still works.
- `src/client/MenuEntry.client.luau` — entry script.
- `tests/test_main_menu.luau` — Lune test of the menu contract (names, callbacks, page switching, touch
  sizes). Run from this folder: `lune run tests/test_main_menu.luau`.
- `design/` — not built into the place: the skin spec, `test_night_ward_skin.luau` (the look: colours by
  role, states, reduced motion, layouts, fallbacks — `lune run design/test_night_ward_skin.luau`) and the
  preview renderer (`bash design/render_all.sh <out-folder>` builds the real menu in Lune, lays it out
  like Roblox, screenshots it with headless Chrome and audits contrast / touch size / top bar / fit).

Other scripts (the obby itself, the shop server, analytics) look up the menu by the instance names the
test pins, so those names must not change.
