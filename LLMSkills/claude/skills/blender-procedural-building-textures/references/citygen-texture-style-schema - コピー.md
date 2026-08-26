# `texture_style` スキーマ（都市 YAML の任意ブロック）

`config/cities/{city}.yaml` に書く。検証は `src/lib/config.py` の
`_validate_texture_style`。未指定なら `city.texture_style is None` となり、
Blender 側は従来どおりの無彩色で生成する（東京湾はこの状態）。

コードに都市名は一切入っていない。三番目の都市がコード変更なしで独自の様式を
宣言できる必要があるため、ここはすべてデータになっている。

## キー

| キー | 必須 | 内容 |
|---|---|---|
| `palettes` | ○ | 名前 → `#rrggbb` の並び。最低1つ |
| `category_base` | | カテゴリ → パレット名。**アトラスに焼く**基調色 |
| `archetype_palette` | | アーキタイプ id → パレット名。建物ごとの色味 |
| `roof_color` | | 屋根区画の基調色。壁に引きずられないよう別に持つ |
| `trim_color` | | トリム区画の基調色 |
| `tint_strength` | | 0〜1。既定 0.35。マテリアル側の色味の強さ |

カテゴリは `office` / `residential` / `lowrise` / `industrial` の4つ。
`p5_texture.CATEGORY_OF` が接頭辞から引く（TANK・WAREHOUSE・INFRA は industrial）。

### 検証で落ちるもの

- `palettes` が空
- `category_base` / `archetype_palette` が `palettes` に無い名前を参照
- `#` の無い色、桁数の違う色
- `tint_strength` が範囲外

参照名の綴り違いを通すと、**その一群だけ既定色になる**。レンダを凝視するまで
気づけないので、必ずキー名付きで落とす。回帰は
`tests/test_config_validation.py` の `case_texture_style_is_optional_and_checked`。

## ホスト側の解決

`p5_apply_texture._resolve_style` がパレット名を実際の色に落とす。

- `category_base` → **パレットの先頭**を使う。ここで振ると、たまたま最暗色が当たって
  街区ごと沈む（実際 lowrise が `#56392a` を引いた）
- `archetype_palette` → 名前から決定論的に選んだ添字。同じパレットを引く
  複数のアーキタイプが完全に同じ色にならないようにするため

## ニューヨークの実例

```yaml
texture_style:
  palettes:
    brownstone:      ["#6b4a35", "#7d5941", "#56392a"]   # 褐色砂岩の連棟住宅
    red_brick:       ["#8c4a3a", "#a35b48", "#6e392c"]   # 赤レンガの長屋
    buff_brick:      ["#b39272", "#c7a684", "#97785b"]   # 黄褐色レンガ
    limestone:       ["#cfc3a8", "#ddd2ba", "#b3a68c"]   # 戦前のセットバック
    terracotta:      ["#b8724f", "#c9855f", "#9c5c3d"]
    cast_iron:       ["#5d6b62", "#6f7d74", "#4a564f"]   # 塗装された鋳鉄柱
    dark_glass:      ["#3a4550", "#2f3945", "#4c5865"]   # 戦後のガラス幕壁
    warehouse_brick: ["#7a4536", "#8d5443", "#653529"]   # 川岸のレンガ倉庫
    steel_grey:      ["#7a7f83", "#8d9296", "#63686c"]

  # 実測でこの都市は HOUSE + MANSION が residential の過半を占める。
  # 基調色はアトラス単位で焼かれるので、支配的な型に合わせる。
  category_base:
    residential: brownstone
    lowrise:     red_brick
    office:      limestone
    industrial:  warehouse_brick

  archetype_palette:
    OFFICE_TOWER:        dark_glass
    OFFICE_TWIN:         dark_glass
    OFFICE_MID:          dark_glass
    OFFICE_SETBACK:      limestone
    OFFICE_PODIUM:       limestone
    OFFICE_SLAB:         limestone
    RESIDENTIAL_HOUSE:   brownstone
    RESIDENTIAL_MANSION: brownstone
    RESIDENTIAL_DANCHI:  red_brick
    RESIDENTIAL_SLAB:    red_brick
    RESIDENTIAL_TOWER:   buff_brick
    RESIDENTIAL_TOWER_HI: buff_brick
    LOWRISE_SHOP:        red_brick
    LOWRISE_MIXED:       red_brick
    LOWRISE_ARCADE:      cast_iron
    LOWRISE_KIOSK:       terracotta
    LOWRISE_SCHOOL:      buff_brick
    WAREHOUSE_BOX:       warehouse_brick
    WAREHOUSE_LONG:      warehouse_brick
    WAREHOUSE_COLD:      warehouse_brick
    INDUSTRIAL_PLANT:    steel_grey
    INDUSTRIAL_SILO:     steel_grey
    INDUSTRIAL_STACK:    warehouse_brick
    TANK_CYLINDER:       steel_grey
    TANK_SPHERE:         steel_grey
    INFRA_BRIDGE_PYLON:  steel_grey
    INFRA_CRANE:         steel_grey
    INFRA_PIER:          warehouse_brick
    INFRA_TANKFARM_PIPE: steel_grey
    INFRA_TOWER_LATTICE: steel_grey

  roof_color: "#2b2b2d"     # 黒いタール防水
  trim_color: "#8a8378"
  tint_strength: 0.80
```

## アトラスの区画（`p5_texture.PANEL_RECTS`）

1024² を8区画に敷き詰める。合計はちょうど 1024×1024 で、重なりも隙間も無い
（`tests/test_texture_atlas.py` が32px格子で画素単位に検査）。

| 区画 | 位置 (x, y, w, h) | 用途 |
|---|---|---|
| A | 0, 0, 512, 512 | 中央値ケース |
| F | 512, 512, 512, 512 | **屋根**。全18,258面の52%を占めるので A と同格 |
| H | 0, 512, 512, 256 | |
| B | 0, 768, 512, 256 | |
| C | 512, 0, 256, 256 | |
| D | 768, 0, 256, 256 | |
| E | 512, 256, 256, 256 | |
| G | 768, 256, 256, 256 | トリム（小面の逃がし先） |

屋根とトリムは面ごとに90°回転・反転させて絵柄の反復を崩すので、**正方形でなければ
ならない**（縦横比が壊れる）。テストが検査している。

各区画の `(ベイ数, 階数)` は `CATEGORY_PANELS` にあり、**実測した壁面 1,216 枚に
対して最適化**してある。手当てでは最悪 8.9 倍ずれていた（industrial の
29.8ベイ×0.9階＝桟橋の腰壁に (30,8) が当たり、高さ3mの壁に窓が8段入った）。
現在は最悪 2.4 倍。

区画の寸法や `(ベイ,階)` を変えたら、`tests/test_texture_atlas.py` の
`case_panel_choice_is_proportional` が実測94面に対して再検査する。
