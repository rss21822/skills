---
description: 武器を「本格的な大砲（砲撃）」のような射撃にする手順。既存武器の砲撃化や新規の砲の追加で、ユーザーが「大砲」「砲撃」「本格的な射撃」「弾道」「着弾爆発」「砲弾」等に言及したら必ずこのスキルを使う。
---

「大砲」「砲撃」「本格的な射撃にして」等を含む武器依頼で実行する。

# Weapon — Cannon (Shell) 砲撃化

このゲームの武器を **弾道シェル（放物線で飛び、着弾で爆発し範囲ダメージ）** にする標準手順。
大砲・20mm機銃・魚雷はすべて同じ枠組み（profileの `fireMode` 分岐）で動く。このスキルは `fireMode = "shell"` 専用。

## アーキテクチャ（最初に頭に入れる）

- **WeaponConfig** `src/ReplicatedStorage/Shared/Config/WeaponConfig.luau`
  武器ごとの profile を定義。`fireMode` フィールドが射撃方式のスイッチ。
- **WeaponService** `src/ServerScriptService/Game/Services/WeaponService.luau`
  サーバー権威。`FireMainGun` が `fireMode` で `FireShell` / `FireBullet` / `FireTorpedo` に分岐。
  発射体は `self.activeShells` に `kind` 付きで積まれ、Heartbeat の `StepShells` で毎フレーム前進＋raycast、衝突で `ExplodeShell`。
- shell の本体ロジックは実装済み。**新しい砲を shell 型にするだけなら、原則 WeaponConfig に profile を足すだけで動く。** 挙動を変えたいときだけ WeaponService をいじる。
- クライアント（`WeaponClientController` / `InputController`）の発射入力経路は既存のままで通常は変更不要。

## 手順

### 1. WeaponConfig に profile を追加（または既存武器を書き換え）

`profiles` テーブルに以下を追加する。`fireMode = "shell"` が砲撃化の本体。

```lua
NewGun = {
    id = "NewGun",
    displayName = "表示名",
    slotIndex = 5,
    fireMode = "shell",            -- ← これで砲撃になる
    damage = 50,                   -- 直撃ダメージ
    cooldown = 2.4,                -- 連射間隔(秒)。重い砲ほど長く
    range = 900,
    spreadDeg = 0.35,              -- 散布(度)。0で完全命中
    projectileSpeed = 300,         -- 初速(stud/s)。大きいほど低伸
    projectileGravity = 55,        -- 重力。大きいほど山なり
    splashRadius = 12,             -- 爆風半径。0なら範囲ダメージ無し
    splashDamageMax = 30,          -- 爆心ダメージ
    splashDamageMin = 8,           -- 爆風縁ダメージ（距離で減衰）
    shellLifetime = 10,            -- 着弾せず自爆するまでの秒
    maxAimAngleDeg = 35,
    tracerColor = Color3.fromRGB(120, 232, 255),
    aimYawOffsetDeg = -90,         -- マウント向き補正（後述・重要）
    assetModelName = "MainGunModel",   -- ReplicatedStorage か Assets.WeaponModels のモデル名
    mountedModelName = "MountedNewGun",
}
```

### 2. SlotOrder と InventorySlots に登録

`WeaponConfig.SlotOrder` に `"NewGun"` を追加し、`InventorySlots` に `{ index = N, weaponId = "NewGun", label = "N\n表示" }` を足す。
装着は `WeaponService:BindCharacter` が SlotOrder を全周回して **weld方式で自動装着** する。profile を足せば自動で付く。

### 3. （挙動をカスタムするときだけ）WeaponService を調整

既存 shell ロジックを流用できる。流れだけ把握しておく：

- `FireShell(player, character, profile, origin, aimPosition)`
  `solveBallisticVelocity(origin, aimPosition, speed, gravity)` で自動仰角を解く → `applySpread` → `createShellPart` で砲弾(炎/煙トレイル付き)生成 → `activeShells` に `kind = "shell"` で積む → `emitMuzzleBlast`（砲口炎＋煙＋光＋轟音）→ `SetWeaponCooldown`。
- `StepShells(deltaTime)` 砲弾に重力を加算 → 変位ぶん `workspace:Raycast` → 当たれば `ExplodeShell`、寿命超過でも自爆。
- `ExplodeShell`（shell枝）直撃ダメージ → `splashRadius` 内を `workspace:GetPartBoundsInRadius` で取得し距離減衰の範囲ダメージ（`DamageService:ApplyDamage` 経由＝チーム/自傷は自動で弾く、`MatchService:IsLive()` のときだけ有効）→ `spawnExplosionEffects`（地上=爆発＋黒煙、水面=水柱＋ミスト）。

新パラメータを足すなら主にこの3関数と `createShellPart` / `spawnExplosionEffects` を触る。エフェクトは `createEffectHost` + `ParticleEmitter:Emit()` パターン。

### 4. 反映 → テスト（fix-and-restart 準拠）

1. ローカル `src/` を編集する（Rojoプロジェクトなので **src が正**）。
2. 同じ編集を Studio へ反映する（`mcp__roblox-built-in__multi_edit` でStudio側スクリプトにも当てる、または Rojo/Argon sync）。
3. `start_stop_play(is_start=true)` でPlay開始。
4. `execute_luau`（Server）でプレイヤー／搭乗ボードを `DummyTargets` の前へ `PivotTo`。狙撃テスト時は流されないようボードを一時 Anchor してよい。
5. `execute_luau`（Client）で `ReplicatedStorage.Shared.Remotes.FireMainGun:FireServer({ weaponId = "NewGun", aimPosition = 標的座標 })` を撃つ。
6. `execute_luau`（Server）で標的 Humanoid の `Health` 変化を監視（`HealthChanged` をprintするか前後比較）。`screen_capture` と `get_console_output` で着弾エフェクトとエラーを確認。
7. 確認後、Studio側の最終ソースを `src/` に書き戻す。

## 落とし穴（実際に踏んだもの・必読）

- **マウントは Anchored 厳禁**：装着武器パーツを `Anchored = true` にするとキャラ＆ボードの物理アセンブリ全体が固定され、WASD移動が完全に死ぬ。必ず weld 方式（`Anchored = false`、追従は物理エンジン）にする。
- **照準ズレは `aimYawOffsetDeg` で補正**：武器モデルの正面向きが種類ごとに違う（主砲 `-90`、横向きマウントのモデルは `-180` 等）。サーバー(WeaponService)とクライアント(WeaponClientController)が同じ profile 値を読むので、profile に入れれば両方直る。向き自体がおかしいときは `WEAPON_MOUNT_OFFSETS[mountedModelName]` を調整。
- **水面に当たらないことがある**：RAFTの海は Terrain水ではなく `CanQuery=false` のパーツのことがあり、海面着弾の水柱が出ない。地上・ターゲット直撃は問題なし。水面ヒットが要るなら別途判定を足す。
- **レガシー競合**：`CharacterSetup` / `WeaponEquipSystem` / `CombatServer` は旧装着・旧戦闘系。有効だと二重装着や自動前進で競合するので **Disabled を維持**。
- **テスト中の漂流**：マッチ中は自動巡航でプレイヤーが流れ、狙いがズレて「弾が消えた」ように見えることがある（実際は外れ）。撃つ前にボードごと再配置し、必要ならHRP/ボードを静止させる。

## 参照値

- 爆発音 `rbxassetid://165969964` / 機銃音 `rbxassetid://150295071`
- パーティクル `rbxasset://textures/particles/fire_main.dds` / `rbxasset://textures/particles/smoke_main.dds`
- 既存の shell 武器：`MainGun`（12.7cm/50 Type3, 初速300/重力55/半径12）、`Type98NavalGun`（初速320/重力55/半径8）を係数の出発点にする。
