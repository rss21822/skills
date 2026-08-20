---
description: 武器を「本格的な魚雷発射管」のような攻撃にする手順。既存武器の魚雷化や新規の魚雷の追加で、ユーザーが「魚雷」「torpedo」「発射管」「水中」「航跡」「雷撃」「水面下」等に言及したら必ずこのスキルを使う。
---

「魚雷」「torpedo」「発射管」「雷撃」「航跡」等を含む武器依頼で実行する。

# Weapon — Torpedo (魚雷) 雷撃化

このゲームの武器を **水面下を直進航走し、水面に白い航跡を引き、命中で大爆発＋範囲ダメージ** にする標準手順。
大砲(shell)・機銃(autocannon)・魚雷(torpedo)は同じ枠組み（profileの `fireMode` 分岐）で動く。このスキルは `fireMode = "torpedo"` 専用。大砲は `weapon-cannon.md`、機銃は `weapon-autocannon.md` 参照。

**魚雷ならではの特徴（他2種との違い）**：
- 重力を使わず **水平直進**（上下照準は無視＝水平方向のみ追従）。
- 弾体は **水面下** を進み、別パーツ `TorpedoWake` が **水面で航跡** を追従表示する（2パーツ構成）。
- 命中／寿命切れで **水柱を伴う大爆発＋範囲ダメージ**（shell系の爆発処理を流用）。

## アーキテクチャ（最初に頭に入れる）

- **WeaponConfig** `src/ReplicatedStorage/Shared/Config/WeaponConfig.luau` — profile の `fireMode` で射撃方式を切替。
- **WeaponService** `src/ServerScriptService/Game/Services/WeaponService.luau` — `FireMainGun` が `fireMode` で `FireTorpedo` に分岐。弾は `activeShells` に `kind = "torpedo"` で積まれ、`StepShells` で前進＋raycast＋航跡追従、衝突で `ExplodeShell`（torpedo枝＝水柱大爆発）。
- torpedo の本体ロジックは実装済み。新しい魚雷を作るなら原則 **WeaponConfig に profile を足すだけ**。

## 手順

### 1. WeaponConfig に profile を追加（または既存武器を書き換え）

```lua
NewTorpedo = {
    id = "NewTorpedo",
    displayName = "表示名",
    slotIndex = 5,
    fireMode = "torpedo",          -- ← これで魚雷になる
    damage = 80,                   -- 直撃ダメージ（高威力・低速の一撃型）
    cooldown = 4.0,                -- 次発までの秒。長め
    range = 700,
    spreadDeg = 0,                 -- 通常0（直進）。散布させるなら小さく
    torpedoSpeed = 70,             -- 航走速度(stud/s)。遅い＝避けられる緊張感
    torpedoDepth = 2.5,            -- 水面下の潜航深度
    torpedoLifetime = 15,          -- 命中せず自爆するまでの秒（射程相当）
    splashRadius = 16,             -- 爆風半径（大砲より大きめ）
    splashDamageMax = 60,          -- 爆心ダメージ
    splashDamageMin = 15,          -- 縁ダメージ（距離減衰）
    maxAimAngleDeg = 50,
    tracerColor = Color3.fromRGB(120, 210, 255),
    muzzlePartName = "Torpedo",
    assetModelName = "TorpedoTube",
    mountedModelName = "MountedTorpedoTube",
    mountScale = 3,                -- モデルが小さい場合の拡大率（任意）
    aimYawOffsetDeg = 0,           -- マウント向き補正
}
```

`WeaponConfig.SlotOrder` と `InventorySlots` にも登録する。装着は `WeaponService:BindCharacter` が weld方式で自動。
魚雷は脚部（LowerTorso付近）にマウントされる（`getMountPartForProfile` が `MountedTorpedoTube` を脚パーツに割り当てる）。新しい魚雷で同じ扱いにしたい場合はこの分岐に名前を追加するか、`mountedModelName` を踏襲する。

### 2. （挙動カスタム時のみ）WeaponService

torpedo系は実装済みで流用可能。流れ：

- `FireTorpedo(player, character, profile, origin, aimPosition)`
  `surfaceY = HRP.Y - 1.2`（水面の基準高さ）→ `flatDirection`（**水平成分のみ**に正規化＝上下を無視）→ `startPosition = (origin.X, surfaceY - depth, origin.Z)` で水面下から発進 → `createTorpedoParts` が **魚雷本体（金属＋気泡トレイル）と航跡パーツ `TorpedoWake`（水面の泡/ミスト）の2つ** を生成 → `activeShells` に `kind = "torpedo"`・`wakePart`・`surfaceY` 付きで積む → `spawnTorpedoLaunch`（発射時の泡＋圧搾空気音）→ cooldown。
- `StepShells`（torpedo）：重力なしで直進。本体を前進させつつ、`wakePart` を毎フレーム `(本体X, surfaceY, 本体Z)` に追従させて水面に航跡を残す。
- `ExplodeShell`（**torpedo枝**）：直撃ダメージ＋ `splashRadius` 内の範囲ダメージ（距離減衰、`DamageService:ApplyDamage`）→ `spawnTorpedoExplosion`（**水柱＋ミスト＋大爆発音**、大砲の地上爆発より派手）→ 本体破棄＋航跡を数秒残してフェード。

挙動を変えるなら主に `FireTorpedo` / `createTorpedoParts` / `spawnTorpedoExplosion` を触る。`torpedoSpeed`・`torpedoDepth`・`splashRadius` は profile 側で調整可能。

### 3. 反映 → テスト（fix-and-restart 準拠）

1. ローカル `src/` を編集（Rojoなので src が正）。
2. 同じ編集を Studio へ反映（`mcp__roblox-built-in__multi_edit`、または Rojo/Argon sync）。
3. `start_stop_play(true)` → `execute_luau`(Server) でプレイヤー／ボードを `DummyTargets` の正面へ `PivotTo`（魚雷は水平直進なので、標的を**正面の水平線上**に置くこと。上下に置くと当たらない）。
4. `execute_luau`(Client) で `FireMainGun:FireServer({ weaponId = "NewTorpedo", aimPosition = 標的座標 })`。
5. `screen_capture` で **水面下の弾体＋水面の航跡** を確認、命中時の **水柱** と標的 Humanoid の `Health` 減少を確認。`get_console_output` でエラー確認。航走に数秒かかるので命中までは `wait` する。
6. 確認後、Studio側ソースを `src/` に書き戻す。

## 落とし穴（実際に踏んだもの・必読）

- **上下照準は効かない**：魚雷は `flatDirection`（水平成分のみ）で進む設計。標的が自分と違う高さにあると当たらない。テストは必ず**正面の水平線上**に標的を置く。
- **「即消滅した」は誤観測が多い**：過去、魚雷がすぐ消えたように見えたのは、マッチ自動巡航でプレイヤーが流され狙いがズレて外れていただけだった。撃つ前にボードごと再配置し、必要ならHRP/ボードを静止させてからテストする。`activeShells` 監視や `ChildAdded`/`AncestryChanged` で寿命を実測すると確実。
- **水面は当たらないことがある**：RAFTの海は `CanQuery=false` パーツのことがあり、魚雷は海面を貫通して水中を進む（これは仕様通り）。逆に「水面着弾の判定」は期待しないこと。命中はオブジェクト/標的に対して起きる。
- **マウントは Anchored 厳禁**：装着武器パーツを `Anchored=true` にするとキャラ＆ボードの物理アセンブリ全体が固定され移動不能になる。weld方式（`Anchored=false`）で追従させる。
- **2パーツの後始末**：本体だけでなく `wakePart` も破棄/フェードする必要がある（実装済み）。新規でいじるときは航跡パーツの寿命処理を忘れない。
- **レガシー競合**：`CharacterSetup` / `WeaponEquipSystem` / `CombatServer` は旧系。Disabled を維持。

## 参照値

- 爆発音 `rbxassetid://165969964`（水柱爆発に流用）
- パーティクル `rbxasset://textures/particles/fire_main.dds` / `rbxasset://textures/particles/smoke_main.dds`
- 既存の torpedo 武器：`TorpedoTube`（速度70/深度2.5/半径16/直撃80/寿命15）を係数の出発点にする。
