---
name: blender-scene-to-ue
description: >
  Blenderの3DシーンをUnreal Engine 5のレベル上に「完全再現」したいときに使う。
  特に、多数のモジュラーメッシュ＋多数のライト＋発光マテリアルから成る重いシーン
  （例：無限城のような暗い室内をランタン群で照らす構成）をUEへ移植する手順。
  Import Levelがクラッシュする／インポートでテクスチャやマテリアルが落ちる／
  配置後に真っ暗になる、といった問題の解決法を含む。Blender MCP（bpy実行）と
  UE Python（Execute Python Script）を併用する前提。
---

# Blender Scene → Unreal Engine Level 完全再現スキル

Blenderの実シーンをUE5レベルへ忠実移植するための実証済みワークフロー（Phase0〜5）。
`scripts/` 内のスクリプトは冒頭の CONFIG だけ変えれば使い回せる。
Blender側は Blender MCP（bpy）で、UE側は UEの Tools → Execute Python Script で実行する。

## 全体像
- Phase0: Blender下準備（テクスチャ2K化／unpack／ライト書き出し／FBX出力）
- Phase1: UEインポート（アセットのみ。Import Levelは使わない）
- Phase2: メッシュ配置（頂点焼き込み判定 → 原点配置 or トランスフォーム配置）
- Phase3: 発光マテリアル再現
- Phase4: ライト配置（Blender→UE座標フィット＋間引き）
- Phase5: 仕上げ（Lumen / Bloom / フォグ / 露出）

---

## Phase0: Blender下準備  → scripts/phase0_blender_prep.py（bpyで実行）
1. **テクスチャ2K化**：全画像の長辺を2048に縮小。8K/4Kのまま持ち込むとUEがVRAM/RAMで落ちる。
2. **unpack**：packed（.blend埋め込み）テクスチャを外部PNGへ書き出す。
   - これをしないと、FBXに実体が乗らずUEでテクスチャが入らない。
3. **ライト書き出し**：全ライトの位置・色・強度・スポット向き/コーン角をJSONへ。
   - 位置は UE座標へ変換：`(x, -y, z) * 100`（m→cm、Y反転）。
4. **FBXエクスポート**：Path Mode = Copy（Embedでも可）。メッシュのみ。

## Phase1: UEインポート（手動）
- **アセットのみ**インポート。`Import Level`（シーン丸ごと）は全アクター＋全ライト同時生成で**必ずクラッシュ**。
- **Nanite OFF**（軽いシーンには不要、VRAMを食う）。
- 必要なら **Legacy FBX Importer**（Interchangeが長い名前を生成しFName長エラーになる場合の回避）。
- 結果、多くの場合メッシュは「頂点がワールド絶対座標で焼き込まれた per-object アセット」になる。

## Phase2: メッシュ配置  → scripts/phase2_place_mesh.py（UEで実行）
- CONFIG: `SM_FOLDER`（StaticMeshフォルダ）, `LABEL`（配置アクターの接頭辞）。
- スクリプトが **焼き込み判定**（先頭20個の `get_bounds().origin` の大きさ平均）。
  - **デカい（>1000）＝絶対座標焼き込み** → 全アセットを **原点(0,0,0)・無回転・スケール1** で StaticMeshActor 配置。これだけで構成が完全再現される。
  - **0付近＝ローカル空間** → Blenderから各オブジェクトのトランスフォームを書き出して配置（別途）。

## Phase3: 発光マテリアル  → scripts/phase3_emissive.py（UEで実行）
- インポート品は **MaterialInstanceConstant**（フォルダ探索では見つからないことがある）。
- **メッシュが実際に参照しているマテリアル**を辿るのが確実（`static_materials` → `material_interface`）。
- 親が `FBXLegacyPhongSurfaceMaterial` なら **`EmissiveColor` パラメータを上書き**（非破壊）。
- 発光面がUEで欠落（スロットが `WorldGridMaterial`/空に化ける）した場合 → 発光ベースマテリアルを作り、そのスロットを差し替え。
- 注意：`get_*_parameter_names()` は `unreal.Name` を返す → `str()` 変換してから判定。

## Phase4: ライト配置  → scripts/phase4_place_lights.py（UEで実行）
- CONFIG: `LIGHTS_JSON`, `SM_LABEL`（Phase2の接頭辞）, `POINT_STEP`(間引き), 強度, `TEST`。
- **座標フィットが鍵**：ライトのBlender由来座標とUEのメッシュ実空間はスケールが合わない。
  - スクリプトが **メッシュ実バウンズ（5/95パーセンタイル）↔ ライトbbox** から等方スケール`S`＋オフセット`O`を自動算出してフィット。半径も`S`倍。
  - それでも合わなければ「メッシュ名↔バウンズ中心」と「Blenderオブジェクト位置」を突き合わせ **最小二乗で変換を厳密に解く**（util_dump_centers.py で中心を書き出して照合）。
- ライトは **間引き＋影OFF＋Movable**。スポットは向き(`make_rot_from_x`)とコーン角(outer=全角/2)。

## Phase5: 仕上げ  → scripts/phase5_finish.py（UEで実行）
- PostProcessVolume(Unbound)：**Lumen** GI/反射 ON、**Bloom** 上げ（発光・ランタンが映える）。
- **露出はロックしない**。`auto_exposure_bias` だけ補正（min=max固定にすると真っ暗になる罠）。
- 空は **黒のまま**（Blenderが黒ワールドなら SkyLight/SkyAtmosphere を足さない）。
- 薄い **Exponential Height Fog**（暖色・低密度、Volumetricは重いのでOFF）。

---

## ハマりどころ（実証済み）
- **真っ暗** → ほぼ「ライト位置ミス」か「露出ロック」。巨大テストライト1個を実バウンズ中心に置いて切り分け。
- **構成が散らばる** → アセットが絶対座標焼き込みなのにトランスフォームを二重適用している。原点配置に。
- **テクスチャが入らない** → packed＋FBX非埋め込み。Phase0でunpack＆Path Mode=Copy。
- **マテリアルが見つからない** → MaterialInstanceConstant。メッシュのスロットから辿る。
- **Import Levelでクラッシュ** → 使わない。アセット＋スクリプト配置に分離。
- **Blender MCPが落ちる**（WinError 10054）→ アドオンのサーバー再起動で再接続。重い処理は分割。
- **bpy execute**：返り値は dict を `result` に代入（listはNG）。結果は1MB以下に。
