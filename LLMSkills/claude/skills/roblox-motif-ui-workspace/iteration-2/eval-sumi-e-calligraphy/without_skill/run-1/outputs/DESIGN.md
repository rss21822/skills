# Obby Rush — 水墨画と書のメインメニュー

Request: make the obby-rush UI a world of sumi-e and calligraphy — only ink, washi and a vermilion
seal, no extra colours, a quiet screen with plenty of empty space, and don't break the tests.

## How the motif was translated

| Motif | On screen | Where |
|---|---|---|
| **和紙** (washi paper) | The whole menu is one opaque sheet `(240,234,219)`. Faint ink toward the edges suggests an old sheet. Pages are a second sheet laid on top, drawn only with an ink hairline. While a page is open, a thin washi "veil" covers the menu, like tracing paper. | `Background`, `PaperEdgeX/Y`, `Theme.panel`, `PageVeil` |
| **墨** (sumi ink) | All text and every line. Tone comes only from **ink density**: transparency of one ink `(27,26,24)` over the paper (焦 0 / 濃 .12 / 中 .35 / 淡 .62 / 清 .88 in `Theme.ink`). Small text never goes lighter than 中墨 (about 4.8:1). | `Theme.ink`, `Theme.label` |
| **筆** (the brush) | The hero is an **ensō (円相)** built from ~185 overlapping ink capsules on a slightly wandering arc. It lands heavy, eases over the top, presses again on the way down, then splits into dry hairs (飛白) and leaves the circle open at the bottom. Hovering a nav word draws a tapered brush stroke (起筆→収筆) under it. Page titles carry the same stroke. | `Theme.enso`, `Theme.brush` |
| **山水** | Three ranges of distant mountains in 清墨 at the bottom left. They are rotated squares with unequal slopes. The ridge is densest and the ink dissolves into mist toward the foot. | `Theme.wash`, `paint()` |
| **書 / 画賛** | A vertical inscription, **七転び八起き** ("fall seven times, rise eight"), for a game about falling off and trying again. It ends with a small seal. | `Inscription`, `Rakkan` |
| **朱の落款** | Vermilion `(192,55,38)` is used **only as seals**. It appears twice on the menu: the small 遊 seal (遊印) that closes the inscription, and the PLAY button, which is a large 白文印 reading **出走** set inside the ensō. Its surface is made uneven like seal paste, and it has a paper-coloured frame line. Starting the game means *pressing the seal*. It stamps in when the menu opens, straightens on hover and sinks when pressed. Because it is the only strong colour, it is also the call to action. | `Theme.button{seal}`, `Theme.seal` |
| **余白** | No boxes on the main screen. There is a 48 px margin, the title and purse are plain type on paper, and the nav is four brushed words. Empty pages keep one small pale ensō and one line of 中墨. | `TopBar {bare}`, `emptyState()` |

Other translations:
- The coin emoji (gold) was replaced by an ink **文銭** (a coin with a square hole) used as a unit mark: `1,250 ◉`.
- Shop rows are ruled lines (罫線). 購入 is an ink-ruled box that fills with ink on hover.
- Settings show the state in 中墨 (`音楽　OFF`) with a filled or open ink dot.
- Type is Garamond for Latin and digits, with weight kept regular; emphasis comes from size and ink density.

## Constraints kept

- **Three colours only.** `UITheme.luau` is the only place a `Color3` is defined: 3 pigments. Legacy `Theme.colors.*` keys (accent, subtext, danger…) still exist and all resolve to those pigments. `subtext` is 中墨 flattened onto washi.
- **Contract unchanged.** Every instance name and parent path the other systems use is unchanged: `MainMenu`, `Background`, `TopBar/Title`, `TopBar/CoinLabel`, `PlayButton` (still directly under `Background`), `NavBar/Nav_*`, `*Page/Title|CloseButton`, `ShopPage/ProductList/Product_*/ProductName|Price|BuyButton`, `Toggle_Music|SFX`, `Empty`. The same goes for callbacks and `MainMenu.open`. Everything new is added alongside. `tests/` was not modified.
- **Touch and scale.** Every offset-sized button is ≥ 48 px. The ensō and seal scale with screen height, and the seal has a UISizeConstraint minimum of 64 px. The inscription is TextScaled with a 30 px cap. Reduced Motion snaps all tweens (`Theme.tween`).

## Verification (Roblox Studio was not launched, as requested)

1. `lune run tests/test_main_menu.luau` passes **29/29** (the original also passed 29/29).
2. **Previews come from the real code.** `_preview_tools/render_menu.luau` runs the actual `MainMenu.build` under the test's mock. It drives hover, page and toggle scenarios, then lays out the instance tree the way Roblox does and writes HTML. Headless Chrome screenshots it at 1280×720 and at 844×390 (phone landscape).
3. **Palette audit.** `_preview_tools/verify_palette.py` checks that every pixel of every render lies inside the RGB triangle spanned by washi, sumi and shu (i.e. only those pigments and their mixtures).
   - All ten renders pass: ≤ 0.002 % stray pixels, all at anti-aliased edges.
   - The original design fails at 100 %, which confirms the check does catch off-palette colour.

## Caveats and approximations

- Japanese text uses Roblox's CJK fallback face, which is a gothic, not a brush or mincho face. The previews use Noto Sans JP to match. To get a brush feel in the glyphs themselves, add a Japanese brush or mincho font asset and change `Theme.font`.
- The previews approximate Roblox rendering. Items to re-check in Studio:
  - the gradient span on the rotated mountain washes
  - the UIStroke outer position
  - UICorner pill clamping on the ensō capsules
- The hero ensō is about 185 static frames. That is fine for a static menu. If profiling objects, it could be baked into one uploaded image; this could not be done offline here.
- Clicking the veil outside a page closes the page. This is a new, deliberate convenience that the test does not exercise.

## Files

- `obby-rush/src/shared/UITheme.luau` — pigments, ink densities, and the helpers: brush, rule, seal, coin, enso, wash, and three button voices (seal / outline / quiet).
- `obby-rush/src/client/MainMenu.luau` — the composition. Names and paths are unchanged.
- `preview.html`, `preview_overview.png` and `preview_*.png` — before/after, hover, pages, phone.
- `_preview_tools/` — renderer, screenshot script, palette checker and the raw HTML renders.
