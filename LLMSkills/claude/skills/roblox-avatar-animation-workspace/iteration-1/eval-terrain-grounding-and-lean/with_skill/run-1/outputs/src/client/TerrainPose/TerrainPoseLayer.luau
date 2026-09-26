-- TerrainPoseLayer (ModuleScript, client): draws every R15 body near the camera -- the local player, other players and
-- NPCs -- with feet fitted to slopes / stairs and a lean into turns, on top of the default Animate script.
-- Presentation only: it writes joint Transforms after the Animator. It never touches physics, the HumanoidRootPart,
-- input, replication, or the Animate script, and needs no uploaded animation.
--
-- Frame order (why): PreAnimation restores the Animator's last pose (joints no track animates would otherwise keep
-- our write and the correction would pile up); PreSimulation reads THIS frame's Animator pose and writes ours
-- (Transforms written in PreRender / RenderStepped are not drawn).
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.AvatarPoseKit)
local Core = require(script.Parent.TerrainPoseCore)

local Layer = {}
Layer.enabled = true
Layer.MAX_DISTANCE = 200 -- studs from the camera; farther bodies are left to Animate (cost, and nobody sees the feet)
Layer.RAY_REACH = 4 -- studs below the foot a floor may be
Layer.SUSPEND_PRIORITY = Enum.AnimationPriority.Action2 -- a playing track at this priority or higher owns the body
Layer.SUSPEND_ATTRIBUTE = "TerrainPoseSuspend" -- game code may set this on a character (cutscene, ragdoll, emote)
Layer.SUSPEND_STATES = {
	[Enum.HumanoidStateType.Climbing] = true, [Enum.HumanoidStateType.Swimming] = true,
	[Enum.HumanoidStateType.Seated] = true, [Enum.HumanoidStateType.PlatformStanding] = true,
	[Enum.HumanoidStateType.Ragdoll] = true, [Enum.HumanoidStateType.FallingDown] = true,
	[Enum.HumanoidStateType.Physics] = true,
}

local states = {} -- [model] = state
local ignoreList, ignoreDirty = {}, true

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
rayParams.RespectCanCollide = true -- decorative non-collidable parts (grass, props) are not floors
local clearanceParams = RaycastParams.new()

local function refreshIgnore()
	if not ignoreDirty then return end
	table.clear(ignoreList)
	for model in states do table.insert(ignoreList, model) end
	rayParams.FilterDescendantsInstances = ignoreList
	ignoreDirty = false
end

local function isR15(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.RigType == Enum.HumanoidRigType.R15
end

local function track(model)
	if states[model] or not model:IsA("Model") or not isR15(model) then return end
	local s = { entries = {}, joints = {}, body = nil, active = false, suspendCheckAt = 0, suspendedByTrack = false }
	local function add(joint)
		if not (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then return end
		local existing = s.joints[joint.Name]
		-- Server Authority rigs: the AnimationConstraint is the joint the Animator drives
		if existing and existing:IsA("AnimationConstraint") and joint:IsA("Motor6D") then return end
		s.joints[joint.Name] = joint
		s.entries[joint.Name] = { joint = joint }
		s.body = nil -- rebuild the solver when the rig changes (R15 feet can arrive after the first frame)
	end
	for _, d in model:GetDescendants() do add(d) end
	s.added = model.DescendantAdded:Connect(add)
	states[model] = s
	ignoreDirty = true
end

local function restore(s)
	for _, e in s.entries do
		if e.joint.Parent and e.base then e.joint.Transform = e.base end
	end
end

function Layer.untrack(model)
	local s = states[model]
	if not s then return end
	if s.added then s.added:Disconnect() end
	restore(s)
	states[model] = nil
	ignoreDirty = true
end

local function grounded(model, humanoid, root)
	if humanoid.FloorMaterial ~= Enum.Material.Air then return true end
	-- other bodies: the client's FloorMaterial flickers to Air on flat ground, so confirm with a short ray
	if model == (Players.LocalPlayer and Players.LocalPlayer.Character) then return false end
	local reach = humanoid.HipHeight + root.Size.Y * 0.5 + 0.6
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), rayParams) ~= nil
end

local function suspended(s, model, humanoid, now)
	if Layer.SUSPEND_STATES[humanoid:GetState()] then return true end
	if model:GetAttribute(Layer.SUSPEND_ATTRIBUTE) == true then return true end
	if now >= s.suspendCheckAt then -- a few times a second is enough
		s.suspendCheckAt = now + 0.2
		s.suspendedByTrack = false
		local animator = humanoid:FindFirstChildOfClass("Animator")
		if animator then
			for _, t in animator:GetPlayingAnimationTracks() do
				-- Core's enum Value is 1000 (not the lowest), so it is excluded explicitly
				if t.Priority ~= Enum.AnimationPriority.Core and t.Priority.Value >= Layer.SUSPEND_PRIORITY.Value
					and t.WeightCurrent > 0.3 then
					s.suspendedByTrack = true
					break
				end
			end
		end
	end
	return s.suspendedByTrack
end

RunService.PreAnimation:Connect(function()
	if not Layer.enabled then return end
	for _, s in states do
		if s.active then
			for _, e in s.entries do
				if e.joint.Parent and e.base then e.joint.Transform = e.base end
			end
		end
	end
end)

RunService.PreSimulation:Connect(function(dt)
	if not Layer.enabled then return end
	refreshIgnore()
	local camera = Workspace.CurrentCamera
	local eye = camera and camera.CFrame.Position
	local now = os.clock()
	local gravity = Workspace.Gravity
	for model, s in states do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if not model.Parent or not humanoid or humanoid.Health <= 0 or not root then
			Layer.untrack(model)
			continue
		end
		-- distance LOD: far bodies are drawn by Animate alone (restore once when leaving range)
		if eye and (root.Position - eye).Magnitude > Layer.MAX_DISTANCE then
			if s.active then restore(s) s.active = false s.body = nil end
			continue
		end
		if not s.body then
			s.body = Core.newBody(s.joints)
			if not s.body.neutral then continue end -- feet not there yet
		end
		s.active = true

		-- 1. the Animator's pose this frame
		local base = {}
		for name, e in s.entries do
			if e.joint.Parent then
				e.base = e.joint.Transform
				base[name] = e.base
			end
		end

		-- 2. floors under the feet: rays straight down from the root's height (not from just above the foot)
		local rootCF = root.CFrame
		local velocity = root.AssemblyLinearVelocity
		local samples = Core.plan(s.body, base, rootCF:VectorToObjectSpace(velocity))
		local heights = {}
		for i, sample in samples do
			local world = rootCF:PointToWorldSpace(sample.point)
			local start = Vector3.new(world.X, root.Position.Y, world.Z)
			local hit = Workspace:Raycast(start, Vector3.new(0, -(root.Position.Y - world.Y + Layer.RAY_REACH), 0), rayParams)
			if hit then heights[i] = rootCF:PointToObjectSpace(hit.Position).Y end
		end
		local floorL, floorR = Core.resolveFloors(s.body, base, samples, heights)

		-- 3. contact state
		local isGrounded = grounded(model, humanoid, root)
		local clearance
		if not isGrounded or s.body.plantW < 0.999 then
			clearance = Kit.floorClearance(model, humanoid, root, dt, { params = clearanceParams, ignore = ignoreList })
		end

		-- 4. solve (pure; identical to the offline test) and write
		local pose = Core.step(s.body, { base = base, dt = dt, grounded = isGrounded, floorL = floorL, floorR = floorR,
			velocity = velocity, gravity = gravity, clearance = clearance, suspend = suspended(s, model, humanoid, now),
			rootHeight = root.Position.Y })
		for name, cf in pose do
			local e = s.entries[name]
			if e and e.joint.Parent then e.joint.Transform = cf end
		end
	end
end)

-- Track the local player, other players and every R15 NPC (Humanoid models anywhere in Workspace, including ones
-- streamed in later). A body is only untracked when it is removed or dies -- never because its driver went quiet.
function Layer.trackAll()
	local function hookPlayer(player)
		if player.Character then track(player.Character) end
		player.CharacterAdded:Connect(function(character)
			character:WaitForChild("Humanoid", 10)
			track(character)
		end)
	end
	for _, p in Players:GetPlayers() do hookPlayer(p) end
	Players.PlayerAdded:Connect(hookPlayer)
	local function consider(inst)
		if inst:IsA("Humanoid") and inst.Parent then
			task.defer(function() -- let the rest of the model arrive
				if inst.Parent then track(inst.Parent) end
			end)
		end
	end
	for _, d in Workspace:GetDescendants() do consider(d) end
	Workspace.DescendantAdded:Connect(consider)
end

-- A/B in Studio: off restores every joint to Animate's pose; on re-tracks.
function Layer.setEnabled(enabled)
	if enabled == Layer.enabled then return end
	Layer.enabled = enabled
	if not enabled then
		local tracked = {}
		for model in states do table.insert(tracked, model) end
		for _, model in tracked do Layer.untrack(model) end
		Layer.untracked = tracked
	else
		for _, model in Layer.untracked or {} do
			if model.Parent then track(model) end
		end
	end
end

function Layer.trackedCount()
	local n = 0
	for _ in states do n += 1 end
	return n
end

return Layer
