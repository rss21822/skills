--[[
	ProceduralGrounding (ModuleScript)
	既定の Animate が書いた Motor6D.Transform の「上に」毎フレーム補正を重ねるクライアント専用レイヤー。
	- 足: 足下へ鉛直レイ (1 足 3 本) → 骨盤を下げる + 2 ボーン IK + 足首を面に合わせる
	- 旋回: HRP のヨー角速度 × 水平速度 から内側へ傾ける (足元が支点, 頭は水平寄りに保つ)
	Transform はレプリケートされないので、各クライアントが自分・他プレイヤー・NPC 全員に同じ処理をかける。

	タイミング: Animator はアニメ評価後 (PreAnimation と PreSimulation の間) に Transform を書く。
	PreSimulation で読んで書き戻すと、その値が今フレームの描画・物理に使われる。
]]

local Solver = require(script.Solver)
local DefaultConfig = require(script.Config)

-- Motor6D 名 -> そのモーターが入っている Part1 の名前 (標準 R15)
local MOTOR_PARENT = {
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftHip = "LeftUpperLeg",
	LeftKnee = "LeftLowerLeg",
	LeftAnkle = "LeftFoot",
	RightHip = "RightUpperLeg",
	RightKnee = "RightLowerLeg",
	RightAnkle = "RightFoot",
}
local REQUIRED = { "Root", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }

local NOT_GROUNDED = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Flying] = true,
	[Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Climbing] = true,
	[Enum.HumanoidStateType.Seated] = true,
	[Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
	[Enum.HumanoidStateType.Physics] = true,
	[Enum.HumanoidStateType.Dead] = true,
}

local Controller = {}
Controller.__index = Controller

function Controller.new(configOverrides: { [string]: any }?)
	local cfg = table.clone(DefaultConfig)
	if configOverrides then
		for k, v in configOverrides do
			cfg[k] = v
		end
	end
	local self = setmetatable({
		config = cfg,
		_records = {} :: { [Model]: any },
		_connections = {} :: { RBXScriptConnection },
		_rayParams = RaycastParams.new(),
		_filterDirty = true,
	}, Controller)
	self._rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self._rayParams.IgnoreWater = true
	self._rayParams.RespectCanCollide = true
	self._sample = function(x: number, z: number, yTop: number, yBottom: number)
		local result = workspace:Raycast(Vector3.new(x, yTop, z), Vector3.new(0, yBottom - yTop, 0), self._rayParams)
		if result then
			return result.Position.Y, result.Normal
		end
		return nil, nil
	end
	return self
end

-- キャラクター (プレイヤー / NPC の Model) を対象に加える
function Controller:addCharacter(model: Instance)
	if not model:IsA("Model") or self._records[model] then
		return
	end
	local rec = {
		model = model,
		bound = false,
		state = Solver.newState(),
		cache = {}, -- [jointName] = { written: CFrame?, base: CFrame? }
		input = { joints = {}, footSize = {} },
	}
	self._records[model] = rec
	self._filterDirty = true
	rec.ancestryConn = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then
			self:removeCharacter(model)
		end
	end)
end

function Controller:removeCharacter(model: Instance)
	local rec = self._records[model]
	if not rec then
		return
	end
	self:_release(rec)
	if rec.ancestryConn then
		rec.ancestryConn:Disconnect()
	end
	self._records[model] = nil
	self._filterDirty = true
end

-- パーツ / モーターを探す。スケール変更等で Motor6D が作り直されたら再バインド
function Controller:_bind(rec): boolean
	if rec.bound then
		local root = rec.motors.Root
		if root.Parent ~= nil and rec.hrp.Parent ~= nil and rec.humanoid.Parent ~= nil then
			return true
		end
		self:_release(rec)
		rec.bound = false
	end
	local model = rec.model
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not hrp or humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		return false
	end
	local motors = {}
	for name, partName in MOTOR_PARENT do
		local part = model:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(name)
		if motor and motor:IsA("Motor6D") then
			motors[name] = motor
		end
	end
	for _, name in REQUIRED do
		if not motors[name] then
			return false
		end
	end
	local leftFoot, rightFoot = model:FindFirstChild("LeftFoot"), model:FindFirstChild("RightFoot")
	if not (leftFoot and rightFoot) then
		return false
	end
	rec.humanoid, rec.hrp, rec.motors = humanoid, hrp, motors
	rec.feet = { Left = leftFoot, Right = rightFoot }
	rec.cache = {}
	rec.input.joints = {}
	for name in motors do
		rec.cache[name] = { written = nil, base = nil }
		rec.input.joints[name] = { c0 = CFrame.identity, c1 = CFrame.identity, base = CFrame.identity }
	end
	rec.state = Solver.newState()
	rec.bound = true
	return true
end

-- 補正をやめる: 自分が書いた値を素の値へ戻す (Animator が触らない関節に補正が残らないように)
function Controller:_release(rec)
	if not rec.motors then
		return
	end
	for name, motor in rec.motors do
		local c = rec.cache[name]
		if c and c.written and motor.Parent ~= nil and c.base then
			motor.Transform = c.base
		end
		if c then
			c.written, c.base = nil, nil
		end
	end
	rec.state = Solver.newState()
end

function Controller:_solveOne(rec, dt: number)
	local cfg = self.config
	local humanoid: Humanoid = rec.humanoid
	local hrp: BasePart = rec.hrp
	local input = rec.input
	for name, motor in rec.motors do
		local c = rec.cache[name]
		local base = Solver.resolveBase(motor.Transform, c.written, c.base)
		c.base = base
		local j = input.joints[name]
		j.c0, j.c1, j.base = motor.C0, motor.C1, base
	end
	input.dt = dt
	input.rootCFrame = hrp.CFrame
	input.rootSizeY = hrp.Size.Y
	input.hipHeight = humanoid.HipHeight
	input.footSize.Left = rec.feet.Left.Size
	input.footSize.Right = rec.feet.Right.Size
	input.velocity = hrp.AssemblyLinearVelocity
	input.gravity = workspace.Gravity
	input.grounded = humanoid.Health > 0
		and not NOT_GROUNDED[humanoid:GetState()]
		and not humanoid.Sit
		and not humanoid.PlatformStand
	input.sample = self._sample

	local result = Solver.solve(input, rec.state, cfg)
	for name, motor in rec.motors do
		local t = result.transforms[name]
		if t then
			motor.Transform = t
			rec.cache[name].written = t
		end
	end
	if cfg.debugAttributes then
		rec.model:SetAttribute("PG_Lean", math.deg(result.debug.lean))
		rec.model:SetAttribute("PG_Drop", result.debug.drop)
		rec.model:SetAttribute("PG_Weight", result.debug.weight)
	end
end

function Controller:step(dt: number)
	local cfg = self.config
	if self._filterDirty then
		local list = {}
		for model in self._records do
			table.insert(list, model)
		end
		self._rayParams.FilterDescendantsInstances = list
		self._filterDirty = false
	end
	local camera = workspace.CurrentCamera
	local camPos = if camera then camera.CFrame.Position else Vector3.zero
	local candidates = {}
	for model, rec in self._records do
		if self:_bind(rec) then
			local dist = (rec.hrp.Position - camPos).Magnitude
			if dist <= cfg.maxDistance and model:GetAttribute(cfg.disableAttribute) ~= true then
				table.insert(candidates, { rec = rec, dist = dist })
			else
				self:_release(rec)
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.dist < b.dist
	end)
	for i, item in candidates do
		if i <= cfg.maxCharacters then
			self:_solveOne(item.rec, dt)
		else
			self:_release(item.rec)
		end
	end
end

local function watchHumanoid(self, humanoid: Instance)
	if humanoid:IsA("Humanoid") and humanoid.Parent and humanoid.Parent:IsA("Model") then
		self:addCharacter(humanoid.Parent)
	end
end

-- プレイヤー全員 + NPC (自動検出 or タグ) を登録して PreSimulation で回し始める
function Controller:start()
	local Players = game:GetService("Players")
	local RunService = game:GetService("RunService")
	local CollectionService = game:GetService("CollectionService")
	local cfg = self.config

	local function onPlayer(player: Player)
		table.insert(self._connections, player.CharacterAdded:Connect(function(character)
			self:addCharacter(character)
		end))
		if player.Character then
			self:addCharacter(player.Character)
		end
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	table.insert(self._connections, Players.PlayerAdded:Connect(onPlayer))

	for _, model in CollectionService:GetTagged(cfg.tagName) do
		self:addCharacter(model)
	end
	table.insert(self._connections, CollectionService:GetInstanceAddedSignal(cfg.tagName):Connect(function(model)
		self:addCharacter(model)
	end))

	if cfg.autoDetectHumanoids then
		for _, d in workspace:GetDescendants() do
			watchHumanoid(self, d)
		end
		table.insert(self._connections, workspace.DescendantAdded:Connect(function(d)
			watchHumanoid(self, d)
		end))
	end

	table.insert(self._connections, RunService.PreSimulation:Connect(function(dt)
		self:step(dt)
	end))
end

function Controller:destroy()
	for _, c in self._connections do
		c:Disconnect()
	end
	table.clear(self._connections)
	for model in table.clone(self._records) do
		self:removeCharacter(model)
	end
end

return Controller
