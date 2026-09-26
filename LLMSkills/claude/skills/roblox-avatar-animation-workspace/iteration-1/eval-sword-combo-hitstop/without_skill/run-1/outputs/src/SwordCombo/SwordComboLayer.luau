--!strict
-- SwordComboLayer: 既定の Animate（Animator の AnimationTrack）の上に、剣の 3 連撃を Motor6D.Transform で重ねる手続き的レイヤー。
--
-- 共存の仕組み
--   * Animator は毎フレーム「アニメーション段階」で Motor6D.Transform を書く。その直後に来る
--     RunService.PreSimulation で、本レイヤーが Transform を上書き（重み付き）する。Animate は止めない。
--   * 上半身（Waist/Neck/両腕）: 攻撃中は重み 1 で上書き。終了後 0.2 秒で Animate の姿勢へフェードアウト。
--   * 骨盤（Root）と脚: 立ち止まっている時だけ上書き（沈み込み＋脚 IK で足裏を床に固定）。
--     歩行中・空中は重み 0 へ 0.12 秒で落とし、脚は Animate の歩き/落下のまま。
--   * 1 本目のキーは「いま見えている姿勢」から始まるので、Animate のどの瞬間から押しても関節が跳ばない。
--
-- ヒットストップ
--   * 当たり判定区間（ComboData.active）中に刃が他の Humanoid に触れた最初のフレームで、
--     アニメ時計を ComboData.hitStop 秒止める（姿勢は完全停止、右肩に ±1.2° 以下の減衰振動）。
--   * 3 撃目は groundImpact: 刃先が地面に当たっても止める（叩きつけ）。
--   * onHit コールバックで被弾側の停止・SE・カメラ揺れ等をゲーム側が足せる。
--
-- 注意: Transform の書き込みは複製されない（このクライアントの見た目だけ）。REPORT.md「制限」参照。

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PoseMath = require(script.Parent:WaitForChild("PoseMath"))
local ComboData = require(script.Parent:WaitForChild("ComboData"))
local ComboPlayer = require(script.Parent:WaitForChild("ComboPlayer"))

local ALL_JOINTS = {
	"Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist",
	"LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle",
	"LeftHip", "LeftKnee", "LeftAnkle",
}
local UPPER = { "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
local LEGS = { "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }

local GRIP = Vector3.new(ComboData.GRIP_OFFSET[1], ComboData.GRIP_OFFSET[2], ComboData.GRIP_OFFSET[3])
local BLADE = ComboData.BLADE_LENGTH

export type Options = {
	createSword: boolean?, -- 見た目用の剣を右手に溶接する（ローカルのみ）
	hitShake: boolean?,
	onHit: ((strikeIndex: number, hit: Instance, position: Vector3, hitStop: number) -> ())?,
	onStrikeStart: ((strikeIndex: number) -> ())?,
	debugDraw: boolean?, -- 刃のレイを可視化
}

local Layer = {}
Layer.__index = Layer

local function findMotors(character: Model): { [string]: Motor6D }
	local out: { [string]: Motor6D } = {}
	for _, d in character:GetDescendants() do
		if d:IsA("Motor6D") and table.find(ALL_JOINTS, d.Name) then
			out[d.Name] = d
		end
	end
	return out
end

local function makeSword(character: Model, hand: BasePart): Model
	local model = Instance.new("Model")
	model.Name = "ComboSword"
	local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, c0: CFrame)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = material
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		p.CFrame = hand.CFrame * c0
		local w = Instance.new("Weld")
		w.Part0 = hand
		w.Part1 = p
		w.C0 = c0
		w.Parent = p
		p.Parent = model
		return p
	end
	local g = CFrame.new(GRIP)
	-- 刃は RightHand の -Z 方向（ComboData / テストと同じ定義）
	part("Grip", Vector3.new(0.2, 0.2, 0.9), Color3.fromRGB(60, 40, 30), Enum.Material.Fabric, g * CFrame.new(0, 0, 0.2))
	part("Guard", Vector3.new(0.9, 0.14, 0.18), Color3.fromRGB(190, 160, 90), Enum.Material.Metal, g * CFrame.new(0, 0, -0.3))
	part("Blade", Vector3.new(0.08, 0.32, BLADE - 0.4), Color3.fromRGB(215, 225, 235), Enum.Material.Metal, g * CFrame.new(0, 0, -(0.4 + (BLADE - 0.4) / 2)))
	model.Parent = character
	return model
end

function Layer.new(character: Model, opts: Options?)
	local o = opts or {}
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	-- R15 の 15 関節が揃うまで待つ（アバター読み込み直後は欠けることがある）
	local motors = findMotors(character)
	local waited = 0
	while waited < 5 do
		local n = 0
		for _ in motors do n += 1 end
		if n >= #ALL_JOINTS then break end
		task.wait(0.1)
		waited += 0.1
		motors = findMotors(character)
	end
	for _, j in ALL_JOINTS do
		assert(motors[j], "SwordComboLayer: R15 Motor6D が見つからない: " .. j)
	end

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		hrp = hrp,
		motors = motors,
		opts = o,
		player = ComboPlayer.new(ComboData, PoseMath, { hitShake = o.hitShake }),
		lowerW = 1,
		lastWritten = {} :: { [string]: CFrame },
		lastBase = {} :: { [string]: CFrame },
		prevBlade = nil :: { Vector3 }?,
		psi = nil :: number?,
		conn = nil :: RBXScriptConnection?,
		sword = nil :: Model?,
		params = RaycastParams.new(),
	}, Layer)
	self.params.FilterType = Enum.RaycastFilterType.Exclude
	self.params.FilterDescendantsInstances = { character }
	if o.createSword then
		local hand = character:FindFirstChild("RightHand") :: BasePart?
		if hand then
			self.sword = makeSword(character, hand)
		end
	end
	self.conn = RunService.PreSimulation:Connect(function(dt: number)
		self:_update(dt)
	end)
	return self
end

-- 実機の C0/C1 からリグ表を作る（アバターのスケール変更にも追従させるため毎フレーム読む）
function Layer:_rig(): { [string]: any }
	local rig = {}
	for name, m in self.motors do
		rig[name] = {
			C0 = m.C0,
			C1 = m.C1,
			p0 = if m.Part0 then m.Part0.Name else "",
			p1 = if m.Part1 then m.Part1.Name else "",
		}
	end
	return rig
end

-- いま画面に出ている Transform（押した瞬間の開始姿勢）
function Layer:_visiblePose(): { [string]: CFrame }
	local out = {}
	for _, j in ComboData.JOINTS do
		out[j] = self.motors[j].Transform
	end
	return out
end

function Layer:press(): boolean
	if self.humanoid.Health <= 0 then
		return false
	end
	return self.player:press(self:_visiblePose())
end

function Layer:isBusy(): boolean
	return self.player:isBusy()
end

function Layer:_readBases(): { [string]: CFrame }
	-- Animator が今フレーム書いた値を取る。書かれていない（= 前フレームの自分の値のまま）なら
	-- 前回の Animator 値を使い、自分の出力を基準にしてしまう自己増幅を防ぐ。
	local bases = {}
	for _, j in ALL_JOINTS do
		local cur = self.motors[j].Transform
		local lw = self.lastWritten[j]
		if lw and cur == lw then
			bases[j] = self.lastBase[j] or CFrame.identity
		else
			bases[j] = cur
			self.lastBase[j] = cur
		end
	end
	return bases
end

function Layer:_update(dt: number)
	if not self.character.Parent or self.humanoid.Health <= 0 then
		return
	end
	local bases = self:_readBases()
	self.player:step(dt)
	local pose, lh, weight, shake = self.player:sample()
	for _, ev in self.player:popEvents() do
		if ev.kind == "start" and self.opts.onStrikeStart then
			self.opts.onStrikeStart(ev.index)
		end
	end
	if not pose or weight <= 0 then
		table.clear(self.lastWritten)
		self.prevBlade = nil
		self.psi = nil
		return
	end
	local rig = self:_rig()
	local T: { [string]: CFrame } = {}
	for j, cf in pose do
		T[j] = cf
	end
	if shake ~= 0 then
		T.RightShoulder = T.RightShoulder * CFrame.Angles(math.rad(shake), 0, math.rad(shake * 0.5))
	end
	-- 両手持ち区間: 左手を柄へ（FK と IK を lh で混ぜる）
	if lh > 0 then
		local ik, _, psi = PoseMath.solveLeftOnHilt(rig, T, GRIP, ComboData.POMMEL_BACK, self.psi)
		self.psi = psi
		for j, cf in ik do
			T[j] = T[j]:Lerp(cf, lh)
		end
	else
		self.psi = nil
	end
	-- 下半身の重み: 歩行中・空中は Animate に返す
	local moving = self.humanoid.MoveDirection.Magnitude > 0.1
	local airborne = self.humanoid.FloorMaterial == Enum.Material.Air
	local targetLower = if moving or airborne then 0 else 1
	self.lowerW += (targetLower - self.lowerW) * math.min(1, dt / 0.12)
	local legs = PoseMath.solveLegs(rig, T.Root, PoseMath.legRestTargets(rig))

	local final: { [string]: CFrame } = {}
	for _, j in UPPER do
		final[j] = bases[j]:Lerp(T[j], weight)
	end
	local lw = weight * self.lowerW
	final.Root = bases.Root:Lerp(T.Root, lw)
	for _, j in LEGS do
		final[j] = bases[j]:Lerp(legs[j], lw)
	end
	for j, cf in final do
		self.motors[j].Transform = cf
		self.lastWritten[j] = cf
	end

	self:_detectHit(rig, final)
end

function Layer:_detectHit(rig: { [string]: any }, final: { [string]: CFrame })
	if not self.player:isActive() then
		self.prevBlade = nil
		return
	end
	local parts = PoseMath.forwardKinematics(rig, final, self.hrp.CFrame)
	local hand = parts.RightHand
	local grip = hand:PointToWorldSpace(GRIP)
	local dir = hand:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local samples = {}
	for k = 0, 5 do
		table.insert(samples, grip + dir * (BLADE * (0.2 + 0.8 * k / 5)))
	end
	local strike = self.player:strike()
	local function tryHit(result: RaycastResult?, isTip: boolean): boolean
		if not result then
			return false
		end
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		local hum = model and model:FindFirstChildOfClass("Humanoid")
		local isTarget = hum ~= nil and hum.Health > 0
		local isGround = (not isTarget) and isTip and strike and strike.groundImpact
		if isTarget or isGround then
			if self.player:registerHit({ instance = result.Instance }) then
				if self.opts.onHit then
					self.opts.onHit(self.player.index, result.Instance, result.Position, strike.hitStop)
				end
				return true
			end
		end
		return false
	end
	-- 刃そのもの（根元→切っ先）
	if tryHit(Workspace:Raycast(samples[1], samples[#samples] - samples[1], self.params), false) then
		self.prevBlade = nil
		return
	end
	-- 前フレームからの掃引（速い振りのすり抜け防止）
	if self.prevBlade then
		for k, p in samples do
			local q = self.prevBlade[k]
			local d = p - q
			if d.Magnitude > 1e-3 then
				if self.opts.debugDraw then
					local b = Instance.new("Part")
					b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
					b.Size = Vector3.new(0.05, 0.05, d.Magnitude)
					b.CFrame = CFrame.lookAt(q + d / 2, p)
					b.Color = Color3.new(1, 0.3, 0.2)
					b.Parent = Workspace
					game:GetService("Debris"):AddItem(b, 0.5)
				end
				if tryHit(Workspace:Raycast(q, d, self.params), k == #samples) then
					self.prevBlade = nil
					return
				end
			end
		end
	end
	self.prevBlade = samples
end

function Layer:Destroy()
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	if self.sword then
		self.sword:Destroy()
		self.sword = nil
	end
end

return Layer
