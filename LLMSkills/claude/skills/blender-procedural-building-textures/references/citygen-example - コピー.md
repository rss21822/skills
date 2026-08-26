# 実装例: citygen パイプライン

`Claude3DProject/Tokyo` にある実装。SKILL.md の手法が具体的にどう落ちているかの資料。
**このリポジトリを触るときはここが正本。**

対象は OSM から生成した街（8,839棟）を Roblox へ持ち込むパイプライン。

## 動かす前に

Blender が起動していて MCP サーバ（`localhost:9876`）が動いていること。
この環境の Blender は Microsoft Store 版なので **`blender --background` は使えない**。
すべて起動中インスタンスへソケット経由でコードを送る（`src/lib/blender.py`）。

```bash
cd Tokyo
python -c "import sys;sys.path.insert(0,'src');from lib.blender import BlenderClient;print(BlenderClient().ping())"
```

繋がらなければユーザーに「Blender を起動し、サイドバーの Blender Lab / MCP で
Start Server」を依頼する。こちらからは起動できない。

シーンが空なら `out/{city}.blend` を開いてもらう。`.blend` が壊れていても
`out/manifest/{city}_placement.json` が正本なので `python src/p4_place.py --city {city}`
で再構築できる（約5分）。

## コマンド

```bash
# 試験: 1セクターを中心に 3x3（推奨。まずここで確認する）
python src/p5_apply_texture.py --city new_york_harbor --sectors "S+07_-01:1" --rooftop --no-shots

# 全域: 313セクター 8,839体。約70秒
python src/p5_apply_texture.py --city new_york_harbor --all --rooftop --no-shots

# 取り消し / 屋上付加物だけ除去
python src/p5_apply_texture.py --city X --sectors "..." --revert
python src/p5_apply_texture.py --city X --sectors "..." --no-rooftop
```

終了コードは予算超過・マテリアル不一致・UV 範囲外のいずれかで 1 になる。
**0 以外なら「完了」と言わない**（仕様書§9-6）。

作業後は必ずシーンを保存する。保存を怠って11分ぶんのシーンを失った事故がある。

```bash
python -c "
import sys,os;sys.path.insert(0,'src')
from lib.blender import BlenderClient
p=os.path.abspath('out/new_york_harbor.blend').replace(chr(92),'/')
print(BlenderClient().run_module('src/p7_sector.py',entry='save_blend',params={'path':p},timeout=300))"
```

## 構成

| ファイル | 側 | 役割 |
|---|---|---|
| `src/p5_texture.py` | Blender | アトラス生成・UV展開・マテリアル・監査・撮影 |
| `src/p5_rooftop.py` | Blender | 屋上付加物（給水塔・塔屋）をメッシュに融合 |
| `src/p5_apply_texture.py` | ホスト | 上2つを順に呼ぶ。判断はしない |

ホスト側が YAML を読んで JSON で渡す。Blender の Python には yaml も shapely も無い。

工程の順序には理由がある。

```
generate → unsplit_roof → rooftop → unwrap → build_materials → apply → verify_uv → audit
```

**`rooftop` は `unwrap` より前**。`unwrap` は面の実寸を見て区画を割り当てるので、
後から形状を足すとその面だけ UV が入らないまま残る。

## この案件で確定した制約

Roblox 公式（create.roblox.com/docs/art/modeling/texture-specifications）:

> All UV coordinates must exist within a 0:1 space
> Mesh objects can only have one material assigned

`config/budget.yaml` の `max_texture_size: 1024` は §4.3 の
**「値を変更しないこと」ブロック内**。`max_textures_per_sector: 4` も同様。
解像度が足りないときはアトラス内の面積配分を見直すのであって、上限を上げない。

## 三段構成

| 段 | 内容 | 追加コスト |
|---|---|---|
| Tier 1 | 都市 YAML の `texture_style`（配色） | なし |
| Tier 2 | 区画ごとの様式（非常階段・軒蛇腹・アーチ窓） | なし |
| Tier 3 | 屋上給水塔・塔屋（メッシュに融合） | 三角形のみ |

`texture_style` のスキーマと NY の実例は `citygen-texture-style-schema.md`。

## 実測値（new_york_harbor 全域適用後）

| 項目 | 値 | 上限 | 使用率 |
|---|--:|--:|--:|
| テクスチャ | 4枚 × 1024²（GPU 約 2.8MB / BC1） | セクター4枚 | 100% |
| MeshPart | 8,839（最悪セクター 81） | 350/セクター | 23% |
| tris 合計 | 1,032,310 | — | — |
| 最悪セクター tris | 14,842 | 250,000 | 5.9% |
| 最悪 MeshPart tris | 392 | 10,000 | 3.9% |

**テクスチャ枚数だけが上限に張り付いている。** 法線マップを足す（4→8枚）と
超えるので、予算の見直しが前提になる。三角形と MeshPart には余裕があるので、
屋上付加物を増やす方向は取れる。

## 終わったと言う前に

`audit` と `verify_uv` の両方が緑であること。加えて:

| 確認 | 期待 |
|---|---|
| `verify_uv.out_of_range_count` | 0 |
| `audit.worst` | `max_textures_per_sector` 以下 |
| `audit.objects_with_multiple_materials` | 0 |
| `audit.material_archetype_mismatch` | 0 |
| `apply.unmapped_archetypes` | 空 |
| `python tests/run_all.py` | 全スイート通過 |

**そのうえで必ずレンダを見る。**

```bash
python -c "
import sys,os;sys.path.insert(0,'src')
from lib.blender import BlenderClient
c=BlenderClient();d=os.path.abspath('out/preview').replace(chr(92),'/')
sec=['citygen_city/S{0:+03d}_{1:+03d}'.format(7+dx,-1+dy) for dy in (-1,0,1) for dx in (-1,0,1)]
for v in ('close','roof'):
    print(v, c.run_module('src/p5_texture.py',entry='shot',
        params={'sectors':sec,'view':v,'out':'{0}/chk_{1}.png'.format(d,v)},timeout=300).get('ok'))"
```

全市なら `src/p8_preview.py` の `main`（上空1枚＋海上の怪獣視点3枚）。

## このリポジトリ固有の注意

- **カテゴリはメッシュ名から引く**（`category_of_mesh` / `archetype_of`）。
  マテリアル名から引くと `p5_optimize._merge_materials` の色一致統合に巻き込まれる
- **`apply` は約40セクターずつに割る**。8,839体を1回で送ると応答待ちを超える
- **テクスチャ PNG は都市別**（`out/textures/{city}/`）
- **UV かジオメトリを変えたら FBX の再出力**（`citygen run --city X --from p7`）。
  絵柄だけなら PNG の差し替えで済む

## 未解決（2026-08-01 時点）

評価で3つの独立したエージェントが同じ箇所を指摘した。**実在の設計課題**として
扱うべきもの。

1. **`PANEL_STYLE` / `_STYLE_FN` が都市別でない。** カテゴリ単位で固定されており
   都市 YAML から届かない。東京に `texture_style` を入れても色は日本・形はニューヨーク
   になる（団地の正面に NY の非常階段が描かれる）。Tier 1 で配色を都市側へ出したのと
   同じ処理が Tier 2 にも要る
2. **P5 が `archetypes.yaml` の `style` を読んでいない。** 22種の様式値が
   `p3_archetypes.py` でしか使われておらず、`LOWRISE_SCHOOL`(364体) と
   `LOWRISE_ARCADE`(443体) に店舗の看板帯が出る
3. **residential ゾーンの4割超が `LOWRISE_*` アーキタイプ。**
   `classify_zone` は `hmean < 14.0` で residential と判定し、その高さ帯は
   低層アーキタイプが高さ適合で勝つ帯でもある。P4 の抽選と衝突している。
   直すなら `zone_weights.residential` だが、`archetypes.yaml` は全都市共有なので
   東京も動く。かつ P4 再配置と FBX 再出力を伴う

## 守るべき線（仕様書）

- **§9-2** もじりに留める。brownstone・非常階段・給水塔といった**類型**は一般的な
  建築語彙であって商標ではない。実在建物の固有意匠、実在企業の名前・ロゴは使わない
- **§9-6** 予算超過を「完了」と扱わない
- **§9-4** HP・ダメージ・スコアはこのパイプラインで決めない
