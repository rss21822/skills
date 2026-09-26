-- Offline harness for SwordCombo/Layer (the RunService-driven part): mocks RunService / Players / Workspace and a
-- Motor6D character, runs PreAnimation -> "Animator writes" -> PreSimulation per frame, and checks the wiring:
--   * idle: the layer never writes (Transform == the Animator's value every frame)
--   * local attack: combo drawn, Transform != Animator on the sword arm, feet planted (IK), then released exactly
--     back to the Animator's values and the layer stops writing
--   * other bodies: a server bump of SwordComboSeq / SwordComboHitSeq replays the combo + hit-stop; the local
--     player's own attribute bumps are ignored (its input is applied directly)
--   * a dead body is released to the Animator pose
--   lune run tests/test_layer_runtime.luau   (from the outputs folder)
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3 = rbx.CFrame, rbx.Vector3

local checks, failures = 0, {}
local function check(ok, label)
	checks += 1
	if not ok then failures[label] = (failures[label] or 0) + 1 end
end

-- signals
local function signal()
	local s = { fns = {} }
	function s:Connect(fn)
		table.insert(self.fns, fn)
		return { Disconnect = function() table.remove(self.fns, table.find(self.fns, fn)) end }
	end
	function s:Fire(...) for _, fn in table.clone(self.fns) do fn(...) end end
	return s
end
local RunService = { PreAnimation = signal(), PreSimulation = signal() }
local workspaceAttrs = {}
local Workspace = { GetAttribute = function(_, k) return workspaceAttrs[k] end }

-- character mock from the measured rig
local rigData = serde.decode("json", fs.readFile("tests/rig-r15.json"))
local function makeCharacter(name)
	local c = { Name = name, attrs = {}, AttributeChanged = signal(), Parent = Workspace, joints = {} }
	local humanoid = { Health = 100 }
	local root = { AssemblyLinearVelocity = Vector3.zero }
	for jn, d in rigData do
		if type(d) == "table" and d.c0 then
			local j = { Name = jn, C0 = CFrame.new(table.unpack(d.c0)), C1 = CFrame.new(table.unpack(d.c1)),
				Part1 = { Size = Vector3.new(table.unpack(d.s1)) }, Transform = CFrame.identity, Parent = c }
			j.IsA = function(_, cls) return cls == "Motor6D" end
			c.joints[jn] = j
		end
	end
	function c:GetDescendants() local t = {} for _, j in self.joints do table.insert(t, j) end return t end
	function c:GetAttribute(k) return self.attrs[k] end
	function c:SetAttribute(k, v) self.attrs[k] = v; self.AttributeChanged:Fire(k) end
	function c:FindFirstChildOfClass(cls) return cls == "Humanoid" and humanoid or nil end
	function c:FindFirstChild(n) return n == "HumanoidRootPart" and root or nil end
	c.humanoid, c.root = humanoid, root
	return c
end
local me, other = makeCharacter("Me"), makeCharacter("Other")
local Players = { LocalPlayer = { Character = me }, PlayerAdded = signal() }
function Players:GetPlayers() return {} end

-- module loader with the mocked services
local SRC = "src/shared/SwordCombo/"
local loaded = {}
local function load(name)
	if loaded[name] then return loaded[name] end
	local parent = setmetatable({}, { __index = function(_, k) return { __module = k } end })
	local services = { RunService = RunService, Players = Players, Workspace = Workspace }
	local env = {
		CFrame = CFrame, Vector3 = Vector3, Enum = rbx.Enum,
		typeof = function(v) return type(v) == "table" and "table" or typeof(v) end,
		script = { Parent = parent },
		require = function(ref) return load(ref.__module) end,
		game = { GetService = function(_, n) return services[n] end },
		task = { spawn = function(fn, ...) fn(...) end },
	}
	loaded[name] = luau.load(fs.readFile(SRC .. name .. ".luau"), { environment = env })()
	return loaded[name]
end
local Layer = load("Layer")
local Kit = load("AvatarPoseKit")
Layer.track(me)
Layer.track(other)

local events = {}
Layer.onEvent(function(character, kind, index) table.insert(events, character.Name .. ":" .. kind .. index) end)

-- the "Animator": a slow breathing idle on the arms / waist, identity legs
local function animatorPose(t)
	local b = math.sin(t * 2 * math.pi / 3.2)
	return { Waist = CFrame.Angles(math.rad(1.5 * b), 0, 0), RightShoulder = CFrame.Angles(0, 0, math.rad(4 + b)),
		LeftShoulder = CFrame.Angles(0, 0, math.rad(-4 - b)) }
end
local t, dt = 0, 1 / 60
local function frame()
	RunService.PreAnimation:Fire()
	local a = animatorPose(t)
	for _, c in { me, other } do
		for name, j in c.joints do j.Transform = a[name] or CFrame.identity end
	end
	RunService.PreSimulation:Fire(dt)
	t += dt
	return a
end
local function drawnDiffers(c, a)
	for name, j in c.joints do
		if Kit.angleBetween(j.Transform, a[name] or CFrame.identity) > 1e-6 then return true end
	end
	return false
end

-- 1. idle: never writes
local wroteIdle = false
for _ = 1, 30 do if drawnDiffers(me, frame()) then wroteIdle = true end end
check(not wroteIdle, "idle: the layer does not touch the Animator's pose")

-- 2. local attack x3 (mash), feet planted, released to the Animator afterwards
local neutral = Kit.neutralLow(me.joints)
local drew, sink, done = false, 0, false
for i = 1, 60 * 5 do
	if i % 6 == 1 and i < 60 * 2.4 then Layer.attack(me) end
	local a = frame()
	if drawnDiffers(me, a) then
		drew = true
		local pose = {}
		for name, j in me.joints do pose[name] = j.Transform end
		sink = math.min(sink, Kit.lowestSole(pose, me.joints) - neutral)
	end
end
check(drew, "attack: the combo is drawn over the Animator")
check(sink > -1e-3, string.format("attack: feet never below the floor while drawn (min %.4f)", sink))
local a = frame()
check(not drawnDiffers(me, a), "after the combo: exactly the Animator's pose again")
local joined = table.concat(events, ",")
check(joined:find("Me:strike1") and joined:find("Me:strike2") and joined:find("Me:strike3") and joined:find("Me:done"), "events: 3 strikes then done (" .. joined .. ")")
check(joined:find("Me:hit") == nil, "no hit reported -> no hit event")
check(me:GetAttribute("SwordComboStrike") == nil, "strike attribute cleared when done")

-- 3. other body: replay from server counters, including a confirmed hit (hit-stop)
table.clear(events)
other:SetAttribute("SwordComboSeq", 1)
local frozenFrames, prevPose = 0, nil
for i = 1, 60 * 2 do
	if i == 10 then other:SetAttribute("SwordComboHitSeq", 1) end -- server confirmed the hit before contact
	local a2 = frame()
	local st = Layer.status(other)
	if st and st.frozen then frozenFrames += 1 end
end
joined = table.concat(events, ",")
check(joined:find("Other:strike1") and joined:find("Other:hit1") and joined:find("Other:done"), "other body replays strike + hit + release (" .. joined .. ")")
check(frozenFrames >= 3 and frozenFrames <= 4, "other body: hit-stop 0.06 s = 3-4 frames at 60 fps (got " .. frozenFrames .. ")")

-- 4. the local player's own attribute bump is ignored (input already applied locally)
table.clear(events)
me:SetAttribute("SwordComboSeq", 5)
for _ = 1, 10 do frame() end
check(#events == 0, "local character: server echo does not start a second combo")

-- 5. death mid-combo releases the body to the Animator pose
Layer.attack(other)
for _ = 1, 20 do frame() end
other.humanoid.Health = 0
local a3 = frame()
check(not drawnDiffers(other, a3), "dead body: released to the Animator pose")

local labels = {}
for label, n in failures do table.insert(labels, label .. " x" .. n) end
table.sort(labels)
for _, label in labels do print("FAIL " .. label) end
if #labels > 0 then error("layer runtime: " .. #labels .. " failing contracts") end
print("PASS layer runtime checks=" .. checks)
