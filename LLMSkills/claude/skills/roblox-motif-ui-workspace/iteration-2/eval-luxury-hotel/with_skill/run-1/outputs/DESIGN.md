# Obby Rush — Grand Hotel lobby skin

## Brief

```
モチーフ: 「obby-rush の舞台を高級ホテル（黒い大理石と金の装飾、シャンデリアのあるロビー）に変える。
          UIも上品で大人っぽい感じ。可愛い感じやポップな感じは要らない」
トーン: 上品・大人（夜のグランドホテル、アール・デコ寄り）
7 軸: 素材 黒大理石（ネロ・マルキーナの白い脈）/ 磨いた真鍮・金の細い象嵌線 / クリスタル / 刻印
      形   角 2 px、不透明の金の二重線（外 1 px＋内側の線）、四隅の◆、半円の扇（サンバースト）、円のメダリオン
      色   黒大理石 #141012・面 #1A1517 / 金 #D2AE62（CTA 専用）・#C9A45C（線）・#7C6034（奥の線）
           アイボリー #EFE6D2（文字）/ 宝石色は意味色だけ（ボルドー #8C2635、エメラルド #2E6E55）
      字   RomanAntique（英字の刻印・館名・階数）＋ AccanthisADFStd Bold（ページ見出し）
           ＋ Merriweather Bold/Heavy（ボタン・本文・金額）。日本語は全部 Bold 以上を要求
      物   シャンデリア（鎖・3 段の金の環・蝋燭 21 本・クリスタルの滝）、エレベーターの階数ダイヤル、
           壁の燭台、交差した金の鍵（コンシェルジュの紋章）。マスコット無し
      動き ゆっくり: 光の呼吸 4.2 s（常時ループはこれ 1 つ）、ホバーでダイヤルの針が L→5 へ 0.7 s、
           ページは 0.35 s で 10 px 沈んで定位置へ、スイッチの玉が 0.2 s。弾まない・傾かない
世界の中の UI: CTA=真鍮のエレベーター扉（金の板＋刻印の内線＋▲、段付きの枠と扇形の階数ダイヤル L 1–5）
               パネル=金の二重線で額装した大理石の板（上辺に交差した鍵の紋章、下に館名のフッター）
                      ショップ=ルームサービスのメニュー表（名前 · · · · · 金貨 300 ／ 購入）
               ナビ=館内案内板（BOUTIQUE / CLOAKROOM / CONCIERGE / RECEPTION の刻印＋日本語）
使わないもの: 艶・下縁・太いインクの縁取り・傾き・押すと縮む動き（ステッカー語彙＝ポップ）、
              キャンディ色、絵文字アイコン（🪙 は Roblox では豆腐になる → 金貨は Frame で描画）、
              マスコット、紺スレートの半透明パネル（旧テーマ）
言い換えテスト: 決め手はシャンデリア・階数ダイヤル・案内板の英字刻印・黒大理石の脈
```

Spec and style board (drawn before any Luau): `design/hotel-skin-spec.json`, `design/style-board.png`
(`skin_preview.py` lint: 0 errors, 0 warnings; ink on paper 15.2:1).

## How it is built

- **Runtime skin, not a rewrite.** `src/shared/HotelSkin/` is applied once by `UITheme` (pcall; missing or
  failing skin = original look). It rewrites `Theme.colors` in place and wraps `corner / stroke / panel /
  label / button`: the original builders still create every instance, the skin only restyles them
  and adds `Hotel*` children. Button roles come from names (`PlayButton`=brass door, `Nav_*`=directory
  plaque, `Product_*` row + primary=outlined "reserve" plate, `Toggle_*`/`CloseButton`=ghost).
- **Two tiny hooks in existing code:** `UITheme` routes hover through `Theme.hover` (default = old lerp),
  so the skin's painter owns hover without fighting the original handlers; `MainMenu` asks
  `Theme.formatCoins` for amounts ("1,250"; falls back to the old emoji) and calls
  `Theme.skin.decorateMainMenu(gui)` at the end of `build` (pcall).
- **Lobby scene** (`Lobby.luau`): opaque marble wall with procedurally drawn veins (seeded, same on every
  client), two gold-lined wall slabs with candle sconces and Art Deco fans, the chandelier with a soft
  stacked glow, the elevator portal + dial behind PLAY, polished floor with brass inlay in perspective
  and a gold reflection. Chandelier/dial scale with screen height; the dial hides below 480 px; wall
  panels start under the cornice so phones stay clear.
- **Pages**: wine-dark veil over the lobby (the directory stays above it and lights the open page's
  plaque), crest, English facility caption + Japanese title, divider, footer, menu-card rows with dot
  leaders and gold coin tokens, brass slide switches for 音楽/効果音.
- Top bar pushed below Roblox's top bar (`kit:clearTopbar`, 58 px + margin); CTA is the only solid gold.

## Not changed

Every instance name, parent, callback, Visible logic and touch size the contract test pins; `tests/`
is byte-identical. `MenuEntry.client.luau` untouched. The 3D obby course is not in this project, so the
"stage" here is the menu's lobby backdrop; building the hotel in the world is a follow-up.
`Background` is now opaque (was 25 % see-through to the world).

## Verification (no Studio used)

| Check | Result |
|---|---|
| `lune run tests/test_main_menu.luau` (unchanged contract) | 29/29 PASS |
| `lune run tools/test_hotel_skin.luau` (look, hover, veil, lamps, layout, reduced motion, fallbacks) | 51/51 PASS |
| `luau.compile` on all src/tools Luau · `rojo build` | 12/12 OK · builds (HotelSkin = ModuleScript + 4 children) |
| Previews rendered from the real built tree (`tools/dump_menu.luau` → `tools/render_preview.py`) | 1280×720 lobby/hover/shop/settings/quests, 1024×768, 844×390 |
| Browser audit of those renders (text fit, <48 px buttons, off-screen, overlap) | 0 issues (`preview-audit.json`) |
| Blind paraphrase test (agent shown only screenshots) | "the lobby or elevator hall of a luxury grand hotel … opulent, dark, formal … nothing cute or pop"; picked プレイ as the CTA. Its notes (placeholder-looking "OR" crest, half-empty pages, unclear settings dot, small captions, empty wall panels) were fixed afterwards |

Previews: `preview-*.png/html`, `compare-before-after.png`, originals in `before-*.png`.

## Not verified / risks

- Real Roblox rendering: fonts are Google look-alikes in the previews (Cinzel, Libre Bodoni,
  Merriweather, Noto Sans JP); `AutomaticSize` name chips, `TopbarInset`, UIStroke placement and
  ClipsDescendants with rotated children are from API knowledge, not a Studio run. Run
  `scripts/studio_ui_audit.luau` and take screenshots in Studio before shipping.
- ~800 GuiObjects on the menu (chandelier ~270, veins ~240, static). Fine on desktop; profile on a
  low-end phone. Knobs: vein steps in `VEINS`, strand spacing in `Lobby.chandelier`.
- Portrait phones: the original 560 px NavBar is wider than the screen (pre-existing, not changed).

## Next candidates

Build the lobby in 3D for the obby's spawn (marble, brass, a real chandelier with PointLights) so menu
and world match; HUD/result screens in the same vocabulary (a floor-dial progress meter fits an obby);
a hotel "bell" SFX on PLAY.
