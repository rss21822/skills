-- SwordCombo/Layer (client only): draws the sword combo on R15 characters over the default Animate script.
-- Presentation only: writes joint Transforms after the Animator (PreSimulation); never touches physics, the
-- HumanoidRootPart, WalkSpeed/AutoRotate, input or replication. Animate keeps running underneath; when the combo is not
-- drawing, this layer writes nothing and Animate's pose is shown unchanged.
--
-- Who drives which body:
--   local player : SwordComboClient calls Layer.attack(character) on input (instant, no round trip).
--   other bodies : the server bumps the character attributes SwordComboSeq / SwordComboHitSeq (SwordComboRelay or your
--                  NPC AI); every client replays them here. Only the attribute numbers replicate, never the pose.
-- Hit-stop: Layer.reportHit(character) (or a hit-test callback run on the contact frame, Layer.setHitTest) freezes the
-- pose clock for Spec hitStop seconds. Studio preview: workspace attribute SwordComboPreviewHits = true makes every
-- strike "hit". Slow motion for inspection: workspace attribute SwordComboTimeScale (e.g. 0.1).
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local Kit = require(script.Parent.AvatarPoseKit)
local Player = require(script.Parent.Player)

local Layer = {}
Layer.enabled = true

local JOINTS = Kit.R15_JOINTS
local states = {}
local eventHandlers = {}
local hitTest = nil

local function collect(character)
	local joints = {}
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			joints[d.Name] = d -- Server Authority rigs: the constraint is what the Animator drives
		elseif d:IsA("Motor6D") and not joints[d.Name] then
			joints[d.Name] = d
		end
	end
	for _, name in JOINTS do
		if not joints[name] then return nil end -- R15 parts can arrive after the first frame; retry next frame
	end
	return joints
end

local function ensure(character)
	local s = states[character]
	if s then return s end
	s = { character = character, pending = {} }
	states[character] = s
	-- other bodies: replay the server's counters (the local player's own input is applied immediately instead)
	local function watch(attr, fn)
		local last = character:GetAttribute(attr)
		s[attr] = character.AttributeChanged:Connect(function(name)
			if name ~= attr then return end
			local now = character:GetAttribute(attr)
			if character == (Players.LocalPlayer and Players.LocalPlayer.Character) then last = now return end
			if typeof(now) == "number" and (typeof(last) ~= "number" or now > last) then fn() end
			last = now
		end)
	end
	watch("SwordComboSeq", function() Layer.attack(character) end)
	watch("SwordComboHitSeq", function() Layer.reportHit(character) end)
	return s
end

-- restore = put the Animator's last pose back. Not from PreSimulation: PreAnimation already restored it and the
-- Animator has written THIS frame's values since, which a restore would overwrite with last frame's.
local function untrack(character, restore)
	local s = states[character]
	if not s then return end
	for _, key in { "SwordComboSeq", "SwordComboHitSeq" } do
		if s[key] then s[key]:Disconnect() end
	end
	if restore ~= false and s.wrote and s.joints then
		for name, joint in s.joints do
			if joint.Parent and s.base and s.base[name] then joint.Transform = s.base[name] end
		end
	end
	states[character] = nil
end

local function ready(s)
	if s.player then return true end
	local joints = s.character and collect(s.character)
	if not joints then return false end
	s.joints = joints
	s.player = Player.new(joints, {
		hitTest = function(strikeIndex)
			return hitTest ~= nil and hitTest(s.character, strikeIndex) == true
		end,
	})
	for _, fn in s.pending do fn() end
	s.pending = {}
	return true
end

-- Attack input for a character. Returns true when it started or buffered a strike.
function Layer.attack(character)
	local s = ensure(character)
	if not ready(s) then
		table.insert(s.pending, function() Player.attack(s.player) end)
		return true
	end
	s.player.autoHit = Workspace:GetAttribute("SwordComboPreviewHits") == true
	return Player.attack(s.player)
end

-- Gameplay confirmed a hit on the current strike: freeze on the contact frame (or now, if up to HIT_LATE after it).
function Layer.reportHit(character)
	local s = states[character]
	return s ~= nil and s.player ~= nil and Player.reportHit(s.player)
end

-- fn(character, strikeIndex) -> bool, called on the contact frame when no hit was reported yet (client-side prediction
-- for the local player: e.g. a GetPartBoundsInBox in front of the blade). Keep it cheap; it runs inside PreSimulation.
function Layer.setHitTest(fn)
	hitTest = fn
end

-- fn(character, kind, strikeIndex); kind = "strike" | "contact" | "hit" | "exit" | "done" (SFX, VFX, camera shake)
function Layer.onEvent(fn)
	table.insert(eventHandlers, fn)
end

function Layer.status(character)
	local s = states[character]
	return s and s.player and Player.status(s.player) or nil
end

-- Put the Animator's last output back before it runs, so PreSimulation reads THIS frame's Animator pose.
RunService.PreAnimation:Connect(function()
	if not Layer.enabled then return end
	for _, s in states do
		if s.wrote and s.base then
			for name, joint in s.joints do
				if joint.Parent and s.base[name] then joint.Transform = s.base[name] end
			end
		end
	end
end)

RunService.PreSimulation:Connect(function(dt)
	if not Layer.enabled then return end
	local timeScale = Workspace:GetAttribute("SwordComboTimeScale")
	timeScale = (typeof(timeScale) == "number" and timeScale > 0) and math.min(timeScale, 1) or 1
	for character, s in states do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		if not character.Parent or not humanoid or humanoid.Health <= 0 or not root then
			untrack(character, false)
			continue
		end
		if not ready(s) then continue end
		if not s.player.active and not s.player.startPending then
			s.wrote = false
			continue -- idle: Animate draws, we write nothing
		end
		-- 1. the Animator's pose this frame
		local base = s.base or {}
		for name, joint in s.joints do base[name] = joint.Transform end
		s.base = base
		-- 2. step the combo (pure; same code as the offline test)
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local pose = Player.step(s.player, dt * timeScale, base, speed)
		-- 3. write (only joints the combo owns) and dispatch events
		if pose then
			for name, cf in pose do
				local joint = s.joints[name]
				if joint and joint.Parent then joint.Transform = cf end
			end
		end
		s.wrote = pose ~= nil
		for _, e in s.player.events do
			if e.kind == "done" then character:SetAttribute("SwordComboStrike", nil)
			elseif e.kind == "strike" then character:SetAttribute("SwordComboStrike", e.value) end -- only on change
			for _, fn in eventHandlers do task.spawn(fn, character, e.kind, e.value) end
		end
	end
end)

-- Track every player character (the local player, other players) and any NPC model passed to Layer.track.
function Layer.track(character)
	ensure(character)
end

function Layer.trackAll()
	local function hook(p)
		if p.Character then ensure(p.Character) end
		p.CharacterAdded:Connect(ensure)
		p.CharacterRemoving:Connect(function(c) untrack(c, true) end)
	end
	for _, p in Players:GetPlayers() do hook(p) end
	Players.PlayerAdded:Connect(hook)
end

-- A/B in Studio: Layer.setEnabled(false) restores every joint to the Animator's pose and stops drawing.
function Layer.setEnabled(enabled)
	if enabled == Layer.enabled then return end
	Layer.enabled = enabled
	if not enabled then
		local tracked = {}
		for character in states do table.insert(tracked, character) end
		for _, character in tracked do untrack(character, true) end
	end
end

return Layer
