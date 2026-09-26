-- PoseLayerTemplate: a client-side procedural pose layer for R15 avatars, built on AvatarPoseKit.
-- Copy next to AvatarPoseKit (e.g. StarterPlayerScripts/Anim/), rename, and fill Layer.MODES.
-- Presentation only: it writes joint Transforms after the Animator; it never touches physics, the HumanoidRootPart,
-- input or replication. The same code draws the local player, NPCs and remote players.
--
-- Frame order (PreSimulation, after the Animator):
--   read the Animator's pose (base) -> pick the mode -> sample targets -> blend (carried velocity + angular budget)
--   -> contact (ground both feet / plant the live track / airborne floor clamp) -> secondary motion -> final raise-only
--   guard -> write. Every step uses the pose rendered by the previous step, never the raw target.
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.AvatarPoseKit)

local Layer = {}
Layer.ENABLED_PLANT = true -- put the feet of raw (Animator-only) frames and grounded modes on the floor
Layer.TERRAIN_FIT = true -- ray under each foot (slopes, stairs); false = one flat floor under the root (cheaper)
-- Stairs trade-offs measured in the sandbox (stock Animate, 60 fps, moving on 1-stud stairs; sink / float frames):
--   layer off 53% / 22%; FLOOR_RATE 12 + 720 deg/s 24% / 16%; 40 + 1440 deg/s 16% / 14% (max joint step 76 deg);
--   no limits 16% / 15% but joints snap up to 128-160 deg. The residual is the Humanoid's step-up happening in the
--   physics step after the write, not the limits.
Layer.FLOOR_RATE = 40 -- studs/s: how fast a foot's floor height may change (a step edge becomes a 2-3 frame ramp)
Layer.CORRECTION_RATE = math.rad(1440) -- contact corrections (IK) may move a leg joint this much faster than the animation
Layer.PLANT_TAU = 0.06 -- seconds; how fast planting fades in on landing / out on take-off
Layer.DEFAULT_FADE = 0.18
Layer.RATE = Kit.DEFAULT_RATE -- 360 deg/s budget for grounded hand-offs
-- Mode samplers: MODES[name](elapsed, context, base) -> { [joint] = Transform } (joints you do not return stay on base).
-- Keep them pure (no Instances) so the same function runs in the offline tests.
Layer.MODES = {}
-- Per-mode settings: fade (s), fast = skip the angular budget (impacts, landings), grounded = put both feet on the floor,
-- secondary = Kit.Secondary weights ({bank, pitch, head, arms} 0..1; Kit.Secondary.OFF for whole-body moves).
Layer.SETTINGS = {}

local states = {}
Layer.enabled = true

local function ensure(character)
	local s = states[character]
	if s then return s end
	s = { entries = {}, joints = {}, secondary = Kit.Secondary.new(), mode = nil, changedAt = os.clock(), plantW = 1 }
	local function add(joint)
		if not (joint:IsA("Motor6D") or joint:IsA("AnimationConstraint")) then return end
		local existing = s.joints[joint.Name]
		-- Server Authority rigs: the AnimationConstraint is the joint the Animator drives
		if existing and existing:IsA("AnimationConstraint") and joint:IsA("Motor6D") then return end
		s.joints[joint.Name] = joint
		s.entries[joint.Name] = { joint = joint }
	end
	for _, d in character:GetDescendants() do add(d) end
	s.added = character.DescendantAdded:Connect(add) -- R15 feet can arrive after the first frame
	states[character] = s
	return s
end

function Layer.untrack(character)
	local s = states[character]
	if not s then return end
	if s.added then s.added:Disconnect() end
	for _, e in s.entries do
		if e.joint.Parent and e.base then e.joint.Transform = e.base end
	end
	states[character] = nil
end

-- Called by whatever knows the style: the local controller, an NPC attribute watcher, or remote-player inference.
function Layer.setMode(character, mode, context)
	local s = ensure(character)
	s.nextMode, s.context = mode, context
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
-- Stepping down a stair or a kerb makes the Humanoid briefly fall (FloorMaterial = Air). Keep fitting the feet while the
-- floor is close below and the fall is slow; otherwise the planted foot is released for a few frames on every step.
Layer.STEP_DOWN_REACH = 1.3 -- studs below standing height still treated as "on the ground" for foot fitting
Layer.STEP_DOWN_MAX_FALL = 35 -- studs/s; faster falls are real jumps/drops
local function nearFloor(character, humanoid, root)
	if root.AssemblyLinearVelocity.Y < -Layer.STEP_DOWN_MAX_FALL then return false end
	groundParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y * 0.5 + Layer.STEP_DOWN_REACH
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), groundParams) ~= nil
end

local function onGround(character, humanoid, root)
	if humanoid.FloorMaterial ~= Enum.Material.Air then return true end
	-- Other bodies: the client's FloorMaterial flickers to Air on flat ground, so confirm with a short ray.
	if character == (Players.LocalPlayer and Players.LocalPlayer.Character) then return false end
	groundParams.FilterDescendantsInstances = { character }
	local reach = humanoid.HipHeight + root.Size.Y * 0.5 + 0.6
	return Workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), groundParams) ~= nil
end

local function currentPose(s)
	local pose = {}
	for name, e in s.entries do
		if e.joint.Parent then pose[name] = e.joint.Transform end
	end
	return pose
end

local function writePose(s, pose)
	for name, cf in pose do
		local e = s.entries[name]
		if e and e.joint.Parent then e.joint.Transform = cf end
	end
end

-- Restore the Animator's last output before it runs, so PreSimulation reads THIS frame's Animator pose (joints no
-- track animates would otherwise keep our previous write and accumulate corrections).
RunService.PreAnimation:Connect(function()
	if not Layer.enabled then return end
	for _, s in states do
		for _, e in s.entries do
			if e.joint.Parent and e.base then e.joint.Transform = e.base end
		end
	end
end)

RunService.PreSimulation:Connect(function(dt)
	if not Layer.enabled then return end
	for character, s in states do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not character.Parent or not humanoid or humanoid.Health <= 0 or not root then
			Layer.untrack(character)
			continue
		end
		Kit.Secondary.measure(s.secondary, root.AssemblyLinearVelocity, dt)
		local grounded = onGround(character, humanoid, root) or nearFloor(character, humanoid, root)

		-- 1. the Animator's pose this frame
		for name, e in s.entries do
			if e.joint.Parent then e.base = e.joint.Transform end
		end

		-- 2. mode switch: remember where every joint was and how fast it moved, to carry it through the blend
		local mode = s.nextMode
		if mode ~= s.mode then
			s.mode, s.changedAt = mode, os.clock()
			for _, e in s.entries do
				e.from = e.last or e.base
				e.velocity = Kit.jointVelocity(e.previous or e.from, e.from, dt, Layer.RATE)
			end
			character:SetAttribute("PoseMode", mode) -- only on change (replication / change signals are not free)
		end
		local settings = (mode and Layer.SETTINGS[mode]) or {}
		local elapsed = os.clock() - s.changedAt
		local sampler = mode and Layer.MODES[mode]
		local targets = sampler and sampler(elapsed, s.context, s.base) or {}
		local fade = settings.fade or Layer.DEFAULT_FADE
		local a = Kit.smoothstep(elapsed / fade)

		-- 3. blend toward the targets (or back to the Animator), within the angular budget
		local pose = {}
		for name, e in s.entries do
			if e.joint.Parent then
				local target = targets[name] or e.base
				local desired = target
				if e.from and a < 1 then
					desired = Kit.carriedStart(e.from, e.velocity, elapsed, fade):Lerp(target, a)
				end
				if not settings.fast then desired = Kit.limitRotation(e.last, desired, Layer.RATE * dt) end
				if a >= 1 and not mode and Kit.angleBetween(desired, e.base) < 1e-5 then e.from = nil end
				pose[name] = desired
			end
		end

		local uncorrected = {}
		for _, name in Kit.LEG_JOINTS do uncorrected[name] = pose[name] end

		-- 4. contact: feet on the floor while grounded (weighted in/out around take-off and landing), clamp while airborne
		local plantTarget = grounded and 1 or 0
		s.plantW += (plantTarget - s.plantW) * Kit.expAlpha(dt, Layer.PLANT_TAU)
		local fitWeight = mode and (grounded and settings.grounded and 1 or 0) or s.plantW
		local floorL, floorR
		if Layer.ENABLED_PLANT and fitWeight > 1e-3 then
			if Layer.TERRAIN_FIT then
				groundParams.FilterDescendantsInstances = { character }
				floorL, floorR = Kit.floorUnderFeet(character, root, pose, s.joints, groundParams)
			end
			if floorL and floorR then
				-- floors in root space move when the root moves; smooth them in world space (root Y + floor)
				local rootY = root.Position.Y
				s.floorWL = Kit.smoothFloor(s.floorWL, rootY + floorL, dt, Layer.FLOOR_RATE)
				s.floorWR = Kit.smoothFloor(s.floorWR, rootY + floorR, dt, Layer.FLOOR_RATE)
				floorL, floorR = s.floorWL - rootY, s.floorWR - rootY
				pose = Kit.fitFeetToFloor(pose, s.joints, floorL, floorR, fitWeight)
			else
				-- flat: move the body vertically so the lower foot is at standing height (never rotates a joint)
				local planted = Kit.groundLowest(pose, s.joints)
				local rootName = Kit.rootName(s.joints)
				if rootName and planted[rootName] and pose[rootName] then
					pose[rootName] = pose[rootName] + (planted[rootName].Position - pose[rootName].Position) * fitWeight
				end
			end
		end
		if not grounded or s.plantW < 0.999 then
			local clearance = Kit.floorClearance(character, humanoid, root, dt)
			local neutral = clearance and Kit.neutralLow(s.joints)
			if neutral then pose = Kit.raiseLowest(pose, s.joints, neutral - clearance) end
		end

		-- contact corrections ease in/out: a leg joint moves at most as far as the animation moved it + CORRECTION_RATE
		for _, name in Kit.LEG_JOINTS do
			local e = s.entries[name]
			if e and pose[name] and uncorrected[name] then
				pose[name] = Kit.carryLimit(e.last, e.uncorrected, uncorrected[name], pose[name], dt, Layer.CORRECTION_RATE)
				e.uncorrected = uncorrected[name]
			end
		end

		-- 5. secondary motion from the body's own velocity
		Kit.Secondary.settle(s.secondary, dt, Workspace.Gravity, settings.secondary or Kit.Secondary.FULL)
		if s.secondary.active then
			for name, cf in Kit.Secondary.apply(s.secondary, pose, s.joints) do pose[name] = cf end
		end

		-- 6. last safety net: never draw the lower foot inside the floor while grounded (raise only)
		if grounded then
			local floor = (floorL and floorR) and math.min(floorL, floorR) or Kit.neutralLow(s.joints)
			if floor then pose = Kit.raiseLowest(pose, s.joints, floor) end
		end

		-- 7. write and remember
		for name, e in s.entries do
			if pose[name] then
				e.previous = e.last or pose[name]
				e.last = pose[name]
			end
		end
		writePose(s, pose)
	end
end)

-- Track every character that should be drawn by this layer. Do NOT untrack a body just because its driver stopped
-- sending modes (e.g. the local player is dead and the controller returns early): it would fall back to the raw track.
function Layer.trackAll()
	local function hook(player)
		if player.Character then ensure(player.Character) end
		player.CharacterAdded:Connect(ensure)
	end
	for _, p in Players:GetPlayers() do hook(p) end
	Players.PlayerAdded:Connect(hook)
end

-- Switch the whole layer off (A/B comparisons in Studio) or back on. Off restores every joint to the Animator's pose.
function Layer.setEnabled(enabled)
	if enabled == Layer.enabled then return end
	Layer.enabled = enabled
	if not enabled then
		local tracked = {}
		for character in states do table.insert(tracked, character) end
		for _, character in tracked do Layer.untrack(character) end
		Layer.untracked = tracked
	else
		for _, character in Layer.untracked or {} do
			if character.Parent then ensure(character) end
		end
	end
end

Layer.currentPose = currentPose
return Layer
