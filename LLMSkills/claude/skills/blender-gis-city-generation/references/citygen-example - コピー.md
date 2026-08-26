# 実装例: citygen パイプライン

`Claude3DProject/Tokyo` にある実装。SKILL.md の手法が具体的にどう落ちているかの資料。
**このリポジトリを触るときはここが正本。**

対象は怪獣ゲーム用の沿岸都市。OSM → 破壊可能な 3D 都市 → Roblox。

## 動かす前に

Blender が起動していて MCP サーバ（`localhost:9876`）が動いていること。
この環境の Blender は Microsoft Store 版なので **`blender --background` は使えない**
（WindowsApps の ACL が実行を拒否し、PATH のランチャは分離して stdout を返さない）。
P3 以降はすべて起動中インスタンスへソケット経由でコードを送る。

```bash
cd Tokyo
python -c "import sys;sys.path.insert(0,'src');from lib.blender import BlenderClient;print(BlenderClient().ping())"
```

繋がらなければユーザーに「Blender を起動し、サイドバーの Blender Lab / MCP で
Start Server」を依頼する。こちらからは起動できない。

Blender 側の Python には **yaml も shapely も pyproj も無い**（site-packages が
読み取り専用で pip も効かない）。ホスト側で YAML を JSON に直し、`params` で渡す。
幾何演算もホスト側で解く。

## コマンド

```bash
# 設定の検証だけ
python src/citygen.py validate --city tokyo_bay

# 連鎖実行（工程は下表）
python src/citygen.py run --city new_york_harbor --to p8
python src/citygen.py run --city new_york_harbor --from p7

# 単体
python src/citygen.py fetch   --city tokyo_bay
python src/citygen.py analyze --city tokyo_bay

# テスト（ネットワークも Blender も不要）
python tests/run_all.py
```

## 工程表

`citygen.py` の `STAGES` が正本。P3/P5/P6 は単体では現れず、他工程が内部で呼ぶ。

| キー | 名前 | 内容 |
|---|---|---|
| `p1` | fetch | Overpass 取得 → GeoJSON |
| `p2` | analyze | 街区分割・高さ分布・ゾーニング・水域マスク |
| `p4` | place | ひな型生成(P3)＋配置＋セクター分割 |
| `p8` | qc | 最適化(P5)＋予算検査＋異常検知＋プレビュー＋クレジット |
| `p7` | export | 破壊状態(P6)＋セクター別FBX＋マニフェスト |

## ソース

| ファイル | 側 | 役割 |
|---|---|---|
| `src/citygen.py` | ホスト | 連鎖実行。工程ごとの終了コード語彙を持つ |
| `src/lib/config.py` | ホスト | 3種の設定の検証（キー名付きで落ちる） |
| `src/lib/blender.py` | ホスト | MCP ソケット越しに Blender を駆動 |
| `src/p1_fetch.py` | ホスト | タイル分割・再試行・キャッシュ・原子的書き込み |
| `src/p2_analyze.py` | ホスト | 陸海・街区・ゾーン・統計 |
| `src/p3_archetypes.py` | Blender | ひな型30種の生成・LOD・コリジョン・UV |
| `src/p3_landmarks.py` | Blender | もじりランドマーク |
| `src/p4_place.py` | ホスト | 配置解（shapely）。チャンクで Blender へ送る |
| `src/p4_instance.py` | Blender | リンク複製でインスタンス化 |
| `src/p5_optimize.py` | Blender | マテリアル統合・LOD 降格 |
| `src/p6_destruction.py` | Blender | 破壊3状態＋瓦礫8種 |
| `src/p7_export.py` | ホスト | 書き出し駆動・マニフェスト |
| `src/p7_sector.py` | Blender | 1セクター生成→書き出し→破棄／`save_blend` |
| `src/p8_qc.py` `p8_inspect.py` `p8_preview.py` | 両方 | 予算検査・異常検知・プレビュー |

テクスチャ関連（`p5_texture.py` / `p5_rooftop.py` / `p5_apply_texture.py`）は
別スキル `procedural-building-textures` の管轄。

## 設定

| ファイル | 内容 |
|---|---|
| `config/cities/{name}.yaml` | 範囲・原点・圧縮率・海の方角・ゾーン・ランドマーク・取得設定・`texture_style` |
| `config/archetypes.yaml` | ひな型30種（全都市共有）。階数・footprint・様式・屋根・ゾーン重み・配色 |
| `config/budget.yaml` | エンジン予算。**§4.3 の「値を変更しないこと」ブロックがある** |

**別都市は config 追加だけで通る**ことが受け入れ基準（§8-5）。コードに都市名を
持たせない。

## 実測値

| | tokyo_bay | new_york_harbor |
|---|---|---|
| 取得 | 105,093件 / 54.4MB | 124,080件 / 102.7MB |
| 街区 → 配置 | 2,787 → 8,627体 | 1,890 → 8,839体 |
| FBX | 349本 / 42.2MB | 314本 / 45.1MB |
| グリッド角 | 37.78° | 65.56° |
| 高さの実測率 | 0.9% | 74.6% |

高さ実測率の桁違いを同じコードで吸収できたことが、汎用性の実証になっている。

## 予算（new_york_harbor）

| 項目 | 値 | 上限 | 使用率 |
|---|--:|--:|--:|
| MeshPart | 8,839（最悪セクター 81） | 350/セクター | 23% |
| tris 合計 | 1,032,310 | — | — |
| 最悪セクター tris | 14,842 | 250,000 | 5.9% |
| 最悪 MeshPart tris | 392 | 10,000 | 3.9% |
| テクスチャ | 4枚 × 1024² | セクター4枚 | 100% |

## 踏んだ不具合（B1〜B19、`PROGRESS.md` に全件）

いずれも**例外を出さない**。発見経路が参考になる。

| # | 内容 | 見つけ方 |
|---|---|---|
| B1 | 陸海マスクの反転（103棟中100棟が海上） | 建物と巻き方向の2信号で検証して発覚 |
| B2 | 巻き方向の標本が足りず証拠に届かない | B1 の回帰テストで発覚 |
| B3 | ミラーが 200 で要素0を返す | 件数が合わない |
| B4 | ヒストグラムが範囲外を落とす | コード読み。**直した効果も測ったら 0 件だった** |
| B6 | クリップで環が切れ、断片と誤診 | 座標を追った |
| B10 | 圧縮を位置だけに適用 → 村の集まり | 俯瞰レンダ |
| B11 | 高さ統計がタグ既定値に汚染 | 配置構成の集計 |
| B12 | `str.replace` の無言失敗を「patched」表示で信じた | 接続断の原因追跡 |
| B13 | LOD 距離を静的距離と誤読 → 都市が消えた | QC の数値が半減 |
| B14 | 23,332体常駐で Blender がクラッシュ | 実クラッシュ。未保存11分を喪失 |

**B12 以降、パッチは不一致で失敗する `Edit` を使う。**

## テスト

`python tests/run_all.py` で7スイート。ネットワークも Blender も不要。

固定しているのは「落ちないが静かに間違う」不変条件:
陸海の向き、グリッド角の円平均、ヒストグラムの端、エンドポイントの健全性順序、
タイル被覆・キャッシュ鍵・原子的書き込み、設定検証、ゾーン判定（建物数の罠）、
アトラスの敷き詰めと決定論。

## 未解決

- **Q3** Roblox のモデレーション審査（Studio 手動インポート時に確認）
- **Q8** 建物の未割当率（tokyo_bay 34% / NY 24%）
- **P9 搬入は人間ゲート**（§5 P9）。`ROBLOX_API_KEY` は環境変数のみ（§9-5）
- テクスチャ側の3件（`procedural-building-textures` の
  `references/citygen-example.md` を参照）

## 守るべき線（仕様書§9）

1. Google 系データ由来のメッシュ・点群・テクスチャを取得も利用もしない
2. 実在建築物の実名・ロゴ・商標的意匠を再現しない（もじり方式）
3. ライセンス不明のアセットを混入させない
4. ゲームバランス数値（HP・ダメージ・スコア）をここで決めない
5. API キー・個人情報をコミットしない
6. 予算超過のまま完了扱いにしない
