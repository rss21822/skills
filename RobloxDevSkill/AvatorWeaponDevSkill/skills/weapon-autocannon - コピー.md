---
description: 武器を「本格的な機銃（機関砲・対空機銃）」のような連射にする手順。既存武器の機銃化や新規の機銃の追加で、ユーザーが「機銃」「機関砲」「20mm」「連射」「フルオート」「曳光弾」「掃射」「対空」等に言及したら必ずこのスキルを使う。
---

「機銃」「機関砲」「連射」「フルオート」「曳光弾」等を含む武器依頼で実行する。

# Weapon — Autocannon (機銃) 連射化

このゲームの武器を **高初速の曳光弾を低伸弾道で連射し、押しっぱなしでフルオート、着弾で火花/水しぶき（範囲ダメージなし）** にする標準手順。
大砲(shell)・機銃(autocannon)・魚雷(torpedo)は同じ枠組み（profileの `fireMode` 分岐）で動く。このスキルは `fireMode = "autocannon"` 専用。大砲の作り方は `weapon-cannon.md` 参照。**大砲との最大の違いは「クライアント側のホールド連射」と「範囲ダメージなしの直撃のみ」**。

## アーキテクチャ（最初に頭に入れる）

- **WeaponConfig** `src/ReplicatedStorage/Shared/Config/WeaponConfig.luau` — profile の `fireMode` で射撃方式を切替。
- **WeaponService** `src/ServerScriptService/Game/Services/WeaponService.luau` — `FireMainGun` が `fireMode` で `FireBullet` に分岐。弾は `activeShells` に `kind = "bullet"` で積まれ、`StepShells` で前進＋raycast、衝突で `ExplodeShell`（bullet枝＝直撃ダメージ＋火花のみ、爆風なし）。
- **クライアント連射** `WeaponClientController` / `InputController` / `ClientBootstrap` — 左クリック/タッチを押している間だけ `cooldown` 間隔で自動発射する。**これが機銃の肝**。大砲は1発ずつなので不要だが、機銃は必須。
- bullet の本体ロジックは実装済み。新しい機銃を作るなら原則 **WeaponConfig に profile を足すだけ**。連射機構は武器IDに依存しないので自動で効く。

## 手順

### 1. WeaponConfig に profile を追加（または既存武器を書き換え）

```lua
NewMG = {
    id = "NewMG",
    displayName = "表示名",
    slotIndex = 5,
    fireMode = "autocannon",       -- ← これで機銃になる
    damage = 6,                    -- 1発の直撃ダメージ（小さめ。DPS=damage/cooldown）
    cooldown = 0.13,               -- 発射間隔(秒)。0.13≒450発/分
    range = 600,
    spreadDeg = 1.2,               -- 散布(度)。連射武器は1〜3程度でばらけさせる
    projectileSpeed = 600,         -- 初速(stud/s)。高初速＝低伸弾道
    projectileGravity = 20,        -- 軽い重力でほぼ直進（0だと完全直線）
    shellLifetime = 3,             -- 曳光弾の寿命(秒)。短くてよい
    maxAimAngleDeg = 50,
    tracerColor = Color3.fromRGB(255, 211, 115),  -- 曳光弾の色
    muzzlePartName = "FlashPos",   -- モデル内の銃口パーツ/Attachment名（無ければ"Muzzle"を自動探索）
    aimYawOffsetDeg = -180,        -- マウント向き補正（後述・重要）
    assetModelName = "OerlikonAA",
    mountedModelName = "MountedNewMG",
}
```

`WeaponConfig.SlotOrder` と `InventorySlots` にも登録する。装着は `WeaponService:BindCharacter` が weld方式で自動。

### 2. （挙動カスタム時のみ）WeaponService

bullet系は実装済みで流用可能。流れ：

- `FireBullet(player, character, profile, origin, aimPosition)`
  `solveBallisticVelocity` で弾速ベクトル算出 → `applySpread` で散布 → `createBulletPart`（細いネオンの曳光弾＋PointLight）→ `activeShells` に `kind = "bullet"` で積む → `emitAutocannonMuzzle`（小さい銃口炎＋薄煙＋光＋実銃発射音、ピッチをランダム化して連射感）→ `SetWeaponCooldown`。
- `StepShells`：重力加算→raycast→当たれば `ExplodeShell`。
- `ExplodeShell`（**bullet枝**）：直撃 Humanoid に `DamageService:ApplyDamage`（チーム/自傷は自動で弾く）→ `spawnBulletImpact`（対物=火花スパーク、水面=小さな水しぶき）→ 弾を破棄。**`splashRadius` は使わない＝範囲ダメージなし**。これが大砲(shell)との違い。

発射音は `AUTOCANNON_SOUND_ID`（既定 `rbxassetid://150295071`）。モデル内に固有の発射音があるならそのIDを使うと馴染む。

### 3. クライアント・ホールド連射（機銃で最重要・既存実装を流用）

押しっぱなしフルオートは以下の3ファイル連携で実現済み。**新しい機銃を足すだけなら触る必要はない**（武器IDに依存しない汎用機構）。仕組みを把握しておく：

- `InputController`：左クリック/タッチ Down で `fireHeldHandler(true)`、Up で `fireHeldHandler(false)`。
- `ClientBootstrap`：`inputController:SetFireHeldHandler(isHeld → weaponClientController:SetFireHeld(isHeld))` で配線。
- `WeaponClientController`：
  - `SetFireHeld(isHeld)` で `self.fireHeld` を保持。
  - `_stepAutoFire()` が RenderStepped 毎に走り、`fireHeld` かつ `cooldownEndAt` 経過なら `RequestFire(マウス位置, silent=true)` を撃つ。
  - `RequestFire(screenPosition, silent)` の `silent` 引数は **連射中のログ洪水を抑える**ため。自動連射からは `silent=true` で呼ぶ。

新たに連射の効く武器を増やしたいだけなら profile を足すだけ。連射の挙動自体を変えたいときだけここを触る。

### 4. 反映 → テスト（fix-and-restart 準拠）

1. ローカル `src/` を編集（Rojoなので src が正）。
2. 同じ編集を Studio へ反映（`mcp__roblox-built-in__multi_edit`、または Rojo/Argon sync）。
3. `start_stop_play(true)` → `execute_luau`(Server) でプレイヤーを `DummyTargets` の前へ `PivotTo`。
4. **連射テスト**：`execute_luau`(Client) で `for i=1,6 do FireMainGun:FireServer({weaponId="NewMG", aimPosition=標的}) ; task.wait(cooldown) end` のように連続発射するか、`user_mouse_input` で左ボタン Down→数秒保持→Up。
5. `execute_luau`(Server) で標的 Humanoid の `HealthChanged` を監視し、連続でダメージが入る（例: 120→114→108…）ことを確認。`screen_capture` で曳光弾、`get_console_output` でエラー確認。
6. 確認後、Studio側ソースを `src/` に書き戻す。

## 落とし穴（実際に踏んだもの・必読）

- **マウントは Anchored 厳禁**：装着武器パーツを `Anchored = true` にするとキャラ＆ボードの物理アセンブリ全体が固定され移動不能になる。weld方式（`Anchored = false`）で追従させる。
- **照準ズレは `aimYawOffsetDeg`**：機銃モデルは横向きマウントが多く `-180` で合うことが多い（主砲は `-90`）。サーバーとクライアントが同じ profile 値を読むので profile に入れれば両方直る。
- **範囲ダメージは出さない**：機銃は `ExplodeShell` の bullet 枝で直撃のみ処理。`splashRadius` を入れても bullet 枝では使われない。範囲攻撃が欲しいなら shell（大砲）にする。
- **連射ログ洪水**：自動連射で `RequestFire` を毎フレーム呼ぶとログが溢れる。必ず `silent=true` で呼ぶ（実装済み）。
- **水面は当たらないことがある**：RAFTの海は `CanQuery=false` パーツのことがあり、水面の水しぶきが出ない。対物・標的直撃は問題なし。
- **レガシー競合**：`CharacterSetup` / `WeaponEquipSystem` / `CombatServer` は旧系。Disabled を維持。
- **テスト時の漂流**：マッチ中は自動巡航で流される。撃つ前にボードごと再配置、必要ならHRP/ボードを静止させてから連射する。

## 参照値

- 機銃発射音 `rbxassetid://150295071`（OerlikonAAモデル付属）/ 爆発音 `rbxassetid://165969964`
- パーティクル `rbxasset://textures/particles/fire_main.dds` / `rbxasset://textures/particles/smoke_main.dds`
- 既存の autocannon 武器：`SecondaryGun`（Oerlikon 20mm: 初速600/重力20/cooldown0.13/damage6/spread1.2）を係数の出発点にする。
