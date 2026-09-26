-- Offline contracts for the SwordCombo modules (Spec / Player / AvatarPoseKit) on the measured rig (rig-r15.json),
-- at body scales 0.8 / 1.0 / 1.3 and 30 / 60 / 144 fps.
--
--   lune run tests/test_sword_combo.luau [--dump]      (run from the outputs folder)
-- Prints "PASS sword combo checks=N" or the failing labels. --dump prints the per-key table used for SPEC.md.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3 = rbx.CFrame, rbx.Vector3

local DUMP = table.find(process.args, "--dump") ~= nil
local SRC = "src/shared/SwordCombo/"

---------------------------------------------------------------- module loading (script.Parent.X / require shim)
local loaded = {}
local function load(name)
	if loaded[name] then return loaded[name] end
	local parent = setmetatable({}, { __index = function(_, k) return { __module = k } end })
	local env = {
		CFrame = CFrame, Vector3 = Vector3, Enum = rbx.Enum,
		typeof = function(v) return type(v) == "table" and "table" or typeof(v) end,
		script = { Parent = parent },
		require = function(ref) return load(ref.__module) end,
	}
	loaded[name] = luau.load(fs.readFile(SRC .. name .. ".luau"), { environment = env })()
	return loaded[name]
end
local Kit, Spec, Player = load("AvatarPoseKit"), load("Spec"), load("Player")

local checks, failures = 0, {}
local function check(ok, label)
	checks += 1
	if not ok then failures[label] = (failures[label] or 0) + 1 end
end
local function deg(x) return math.deg(x) end
local stats = {}

---------------------------------------------------------------- rig
local rigData = serde.decode("json", fs.readFile("tests/rig-r15.json"))
local function rig(scale)
	local joints = {}
	for name, d in rigData do
		if type(d) == "table" and d.c0 then
			local c0, c1 = CFrame.new(table.unpack(d.c0)), CFrame.new(table.unpack(d.c1))
			joints[name] = { Name = name, C0 = c0 + c0.Position * (scale - 1), C1 = c1 + c1.Position * (scale - 1),
				Part1 = { Size = Vector3.new(table.unpack(d.s1)) * scale }, p0 = d.p0, p1 = d.p1 }
		end
	end
	return joints
end

-- Forward kinematics: every part's CFrame in HumanoidRootPart space for a pose.
local function partFrames(pose, joints)
	local frames = { HumanoidRootPart = CFrame.identity }
	local remaining = {}
	for name, j in joints do remaining[name] = j end
	local progress = true
	while progress do
		progress = false
		for name, j in remaining do
			local parent = frames[j.p0]
			if parent then
				frames[j.p1] = parent * j.C0 * (pose[name] or CFrame.identity) * j.C1:Inverse()
				remaining[name] = nil
				progress = true
			end
		end
	end
	return frames
end
local function bladeTip(pose, joints)
	local hand = partFrames(pose, joints).RightHand
	return hand.Position + hand.LookVector * Spec.BLADE_LENGTH, hand.Position, hand.LookVector
end

---------------------------------------------------------------- 1. sign conventions by FK on this rig
do
	local j = rig(1)
	local function handAt(p) return partFrames(p, j).RightHand.Position end
	local rest = handAt({})
	check(handAt({ RightShoulder = CFrame.Angles(math.rad(30), 0, 0) }).Z < rest.Z - 0.3, "sign: Shoulder +X swings the arm forward (-Z)")
	check(handAt({ RightShoulder = CFrame.Angles(0, 0, math.rad(30)) }).X > rest.X + 0.3, "sign: RightShoulder +Z opens the arm out (+X)")
	local flexPlus = handAt({ RightElbow = CFrame.Angles(math.rad(30), 0, 0) })
	local flexMinus = handAt({ RightElbow = CFrame.Angles(math.rad(-30), 0, 0) })
	check(flexPlus.Z < rest.Z - 0.1 and flexMinus.Z > rest.Z + 0.1, "sign: Elbow +X brings the hand forward (flexion), -X backward")
	local head = function(p) return partFrames(p, j).Head end
	check(head({ Waist = CFrame.Angles(math.rad(-20), 0, 0) }).Position.Z < head({}).Position.Z - 0.2, "sign: Waist -X leans forward")
	check(head({ Neck = CFrame.Angles(math.rad(20), 0, 0) }).LookVector.Y > 0.3, "sign: Neck +X looks up")
	check(head({ Root = CFrame.Angles(0, math.rad(30), 0) }).LookVector.X < -0.4, "sign: Root +Y turns left (-X)")
	check(head({ Root = CFrame.Angles(0, 0, math.rad(20)) }).Position.X < -0.4, "sign: Root +Z leans to the character's left")
	if DUMP then
		print(string.format("FK elbow check: rest hand z=%.3f, elbow +30 z=%.3f, elbow -30 z=%.3f", rest.Z, flexPlus.Z, flexMinus.Z))
	end
end

---------------------------------------------------------------- 2. choreography: blade arcs per strike (FK tip, root space)
do
	local joints = rig(1)
	local function tipAt(index, t)
		local upper, dy = Spec.sample(index, t)
		local pose = table.clone(upper)
		pose.Root = CFrame.new(Kit.jointData(joints.Root).c0:VectorToObjectSpace(Vector3.new(0, dy, 0))) * pose.Root
		return (bladeTip(pose, joints)), pose
	end
	local function report(index)
		local strike = Spec.STRIKES[index]
		for _, key in strike.keys do
			local tip, pose = tipAt(index, key.t)
			local hand = partFrames(pose, joints).RightHand
			if DUMP then
				print(string.format("S%d %-8s t=%.2f tip=(%6.2f,%6.2f,%6.2f) hand=(%6.2f,%6.2f,%6.2f) blade=(%5.2f,%5.2f,%5.2f)",
					index, strike.name, key.t, tip.X, tip.Y, tip.Z, hand.Position.X, hand.Position.Y, hand.Position.Z,
					hand.LookVector.X, hand.LookVector.Y, hand.LookVector.Z))
			end
		end
	end
	for i = 1, 3 do report(i) end
	-- Criteria on the HAND path (where the cut travels) + the tip for "in front / behind"; with the torso coiled the
	-- blade of a cocked sword points behind the body, so the tip alone is not "upper right".
	local function handAt(index, t)
		local _, pose = tipAt(index, t)
		return partFrames(pose, joints).RightHand.Position
	end
	local floor = Kit.neutralLow(joints)
	local s1 = Spec.STRIKES[1]
	local hw1, he1, c1 = handAt(1, 0.34), handAt(1, 0.48), tipAt(1, s1.contact)
	check(hw1.X > 0.2 and hw1.Y > 0.3, "S1 windup: hand high on the RIGHT")
	check(he1.X < -0.5 and he1.Y < hw1.Y - 1.5, "S1 end: hand low on the LEFT (diagonal cut)")
	check(c1.Z < -1.0, "S1 contact: tip in front of the body")
	local s2 = Spec.STRIKES[2]
	local hw2, he2, c2 = handAt(2, 0.23), handAt(2, 0.37), tipAt(2, s2.contact)
	check(hw2.X < -0.6 and he2.X > 1.0, "S2: hand travels LEFT -> RIGHT")
	check(c2.Z < -1.5, "S2 contact: tip in front")
	local lo, hi, tlo, thi = math.huge, -math.huge, math.huge, -math.huge
	for t = 0.23, 0.37, 0.005 do
		local h, tip = handAt(2, t), tipAt(2, t)
		lo, hi = math.min(lo, h.Y), math.max(hi, h.Y)
		tlo, thi = math.min(tlo, tip.Y), math.max(thi, tip.Y)
	end
	check(hi - lo < 0.65, string.format("S2 sweep: hand stays level (height range %.2f)", hi - lo))
	stats.s2Level = { hi - lo, thi - tlo }
	local s3 = Spec.STRIKES[3]
	local hw3, tw3, c3 = handAt(3, 0.38), tipAt(3, 0.38), tipAt(3, s3.contact)
	check(hw3.Y > 0.8 and tw3.Z > 2, "S3 windup: hands overhead, blade hanging behind the head")
	check(c3.Z < -1.5 and c3.Y < floor + 1.5, string.format("S3 impact: tip low in front (%.2f above the floor)", c3.Y - floor))
	-- the blade never goes into the floor (root space, standing sole height = floor), sampled every 5 ms of each strike
	local deepest = math.huge
	for i, strike in Spec.STRIKES do
		local worstT, worstD = 0, math.huge
		for t = 0, strike.duration, 0.005 do
			local d = (tipAt(i, t)).Y - floor
			if d < worstD then worstD, worstT = d, t end
		end
		deepest = math.min(deepest, worstD)
		if DUMP then print(string.format("S%d lowest tip %.3f above the floor at t=%.3f", i, worstD, worstT)) end
	end
	check(deepest > -0.05, string.format("sword tip never below the floor (min %.3f)", deepest))
	stats.tipAboveFloor = deepest
	-- no key segment asks a joint to rotate >= 170 deg (Lerp takes the short way; >180 would flip)
	for i, strike in Spec.STRIKES do
		for k = 1, #strike.keys - 1 do
			for _, name in Spec.UPPER do
				local a = Spec.jointCFrame(strike.keys[k].pose[name])
				local b = Spec.jointCFrame(strike.keys[k + 1].pose[name])
				check(Kit.angleBetween(a, b) < math.rad(170), string.format("S%d segment %d %s < 170 deg", i, k, name))
			end
		end
	end
end

---------------------------------------------------------------- 3. simulated play: a base (Animate idle) stream + combo
local function idleBase(t)
	-- a small breathing idle like Animate's (so the layer is tested against a moving base)
	local b = math.sin(t * 2 * math.pi / 3.2)
	return {
		Root = CFrame.identity, Waist = CFrame.Angles(math.rad(1.5 * b), 0, 0), Neck = CFrame.Angles(math.rad(-1 * b), 0, 0),
		RightShoulder = CFrame.Angles(0, 0, math.rad(4 + b)), LeftShoulder = CFrame.Angles(0, 0, math.rad(-4 - b)),
		RightElbow = CFrame.identity, LeftElbow = CFrame.identity, RightWrist = CFrame.identity, LeftWrist = CFrame.identity,
		LeftHip = CFrame.identity, LeftKnee = CFrame.identity, LeftAnkle = CFrame.identity,
		RightHip = CFrame.identity, RightKnee = CFrame.identity, RightAnkle = CFrame.identity,
	}
end

-- presses: list of times (s) at which attack() is called; hits = true -> autoHit
local function run(scale, fps, presses, opts)
	opts = opts or {}
	local joints = rig(scale)
	local s = Player.new(joints, { autoHit = opts.hits ~= false })
	local dt = 1 / fps
	local frames = {}
	local pi = 1
	local t = 0
	while t < (opts.duration or 4.5) do
		while presses[pi] and presses[pi] <= t + 1e-9 do
			Player.attack(s)
			pi += 1
		end
		local base = idleBase(t)
		local pose = Player.step(s, dt, base, opts.speed and opts.speed(t) or 0)
		local events = table.clone(s.events)
		table.insert(frames, { t = t, pose = pose, base = base, strike = s.strike, clock = s.t, freeze = s.freeze,
			exiting = s.exiting, active = s.active, events = events, feet = s.feet })
		t += dt
	end
	return frames, joints, s
end

local UPPER = Spec.UPPER
local ALL = table.clone(UPPER)
for _, n in Player.LEG_JOINTS do table.insert(ALL, n) end

for _, scale in { 0.8, 1, 1.3 } do
	for _, fps in { 30, 60, 144 } do
		local tag = string.format(" @x%.1f %dfps", scale, fps)
		-- mash: press every 0.1 s -> full 3-strike combo
		local presses = {}
		for p = 0, 2.2, 0.1 do table.insert(presses, p) end
		local frames, joints, s = run(scale, fps, presses)
		local neutral = Kit.neutralLow(joints)
		local dt = 1 / fps

		-- events: 3 strikes in order, 3 hits, exit, done
		local seq = {}
		for _, f in frames do for _, e in f.events do table.insert(seq, e.kind .. (e.value ~= 0 and tostring(e.value) or "")) end end
		local joined = table.concat(seq, ",")
		check(joined == "strike1,contact1,hit1,strike2,contact2,hit2,strike3,contact3,hit3,exit3,done", "event order" .. tag .. " got " .. joined)

		-- per-frame metrics
		local worstExcess, worstSink, worstFootErr, worstSlide, nan = 0, 0, 0, 0, false
		local prev, prevTarget
		local lastFeet
		for i, f in frames do
			local pose = f.pose or f.base
			for _, n in ALL do
				local cf = pose[n]
				if cf then for _, v in { cf:GetComponents() } do if v ~= v or math.abs(v) > 1e6 then nan = true end end end
			end
			-- contact with the floor: lower sole never below the standing sole height; planted feet do not slide
			if f.pose then
				local low = Kit.lowestSole(f.pose, joints)
				worstSink = math.min(worstSink, low - neutral)
				local feet = { Left = (Kit.footFrame(f.pose, joints, "Left")), Right = (Kit.footFrame(f.pose, joints, "Right")) }
				for _, side in { "Left", "Right" } do
					local sole = Kit.soleLow(f.pose, joints, side)
					feet[side .. "Down"] = sole < neutral + 0.01
					-- a slide = the foot is on the floor in the previous AND this frame and moved sideways
					if lastFeet and feet[side .. "Down"] and lastFeet[side .. "Down"] then
						local d = feet[side].Position - lastFeet[side].Position
						worstSlide = math.max(worstSlide, Vector3.new(d.X, 0, d.Z).Magnitude)
					end
				end
				lastFeet = feet
			else
				lastFeet = nil
			end
			prev = pose
		end
		check(not nan, "finite" .. tag)
		check(worstSink >= -1e-3, string.format("feet never below the floor (min %.4f)", worstSink) .. tag)
		check(worstSlide < 2e-3 * scale, string.format("a foot on the floor never slides (max %.4f stud/frame)", worstSlide) .. tag)

		-- hit-stop: real time during which the pose clock did not advance inside strike idx == hitStop (exact), the clock
		-- sits exactly on the contact time, and the drawn pose only moves by the decaying shake
		for idx = 1, 3 do
			local strike = Spec.STRIKES[idx]
			local stalled, first, maxDev = 0, nil, 0
			for i = 2, #frames do
				local a, f = frames[i - 1], frames[i]
				if f.strike == idx and a.strike == idx and not f.exiting and f.active and a.active then
					stalled += dt - (f.clock - a.clock)
				end
				if f.strike == idx and not f.exiting and f.freeze > 0 then
					first = first or f
					for _, n in UPPER do maxDev = math.max(maxDev, Kit.angleBetween(f.pose[n], first.pose[n])) end
					check(math.abs(f.clock - strike.contact) < 1e-9, "clock held at contact S" .. idx .. tag)
				end
			end
			check(math.abs(stalled - strike.hitStop) < 1e-6, string.format("hit-stop S%d = %.3f s of real time (got %.4f)", idx, strike.hitStop, stalled) .. tag)
			check(deg(maxDev) <= strike.shake * 2 + 1e-3, string.format("S%d frozen pose moves only by the shake (%.2f deg)", idx, deg(maxDev)) .. tag)
			if fps == 60 and scale == 1 then stats["hitstop" .. idx] = { stalled, deg(maxDev) } end
		end

		-- activation / release frames (Animate <-> combo): the step between the Animator pose and the first / last
		-- combo frame stays within 360 deg/s * dt (+ the Animator's own motion, tiny here)
		local worstOver, worstAt = 0, ""
		for i = 2, #frames do
			local a, b = frames[i - 1], frames[i]
			if (a.pose == nil) ~= (b.pose == nil) then
				local pa, pb = a.pose or a.base, b.pose or b.base
				for _, n in ALL do
					local moved = Kit.angleBetween(pa[n], pb[n])
					if moved > worstOver then worstOver, worstAt = moved, n .. string.format(" t=%.3f", b.t) end
				end
			end
		end
		check(deg(worstOver) <= 360 * dt + 0.5,
			string.format("activation/release frames move <= budget (%.2f deg at %s)", deg(worstOver), worstAt) .. tag)
		if fps == 60 and scale == 1 then stats.release = deg(worstOver) end
	end
end

-- 3b. correction budget (exact): re-run at 60 fps and compare rendered motion with the goal motion inside the Player
do
	local joints = rig(1)
	local s = Player.new(joints, { autoHit = true })
	local dt = 1 / 60
	local presses = { 0, 0.35, 0.85 }
	local pi, t = 1, 0
	local worst, worstAt = 0, ""
	local prevR, prevG
	local peak = {}
	while t < 4 do
		if presses[pi] and presses[pi] <= t + 1e-9 then Player.attack(s); pi += 1 end
		local base = idleBase(t)
		local pose = Player.step(s, dt, base, 0)
		if pose and prevR and s.target and prevG then
			for _, n in UPPER do
				local over = Kit.angleBetween(prevR[n], pose[n]) - Kit.angleBetween(prevG[n], s.target[n])
				if over > worst then worst, worstAt = over, string.format("%s t=%.3f strike=%d", n, t, s.strike) end
			end
		end
		if pose and prevR and not s.exiting and s.freeze <= 0 then
			-- hand speed (studs/s, root space): anticipation slow, swing fast = weight
			local w = (partFrames(pose, joints).RightHand.Position - partFrames(prevR, joints).RightHand.Position).Magnitude / dt
			local strike = Spec.STRIKES[s.strike]
			local key = strike.name
			peak[key] = peak[key] or { windup = 0, strike = 0 }
			if s.t < strike.keys[3].t then peak[key].windup = math.max(peak[key].windup, w)
			elseif s.t <= strike.contact then peak[key].strike = math.max(peak[key].strike, w) end
		end
		prevR = pose and table.clone(pose) or nil
		prevG = s.target and table.clone(s.target) or nil
		t += dt
	end
	check(deg(worst) <= 6 + 0.05, string.format("hand-off correction <= 6 deg/frame above the authored motion (%.2f at %s)", deg(worst), worstAt))
	for name, p in peak do
		check(p.strike >= 2 * p.windup, string.format("weight %s: hand speed into contact %.1f >= 2 x anticipation %.1f stud/s", name, p.strike, p.windup))
	end
	stats.correction = deg(worst)
	stats.handSpeed = peak
end

-- 4. no hit -> no hit-stop; late hit report freezes; early presses before inputOpen are ignored; stop after 1 strike
do
	local frames = run(1, 60, { 0 }, { hits = false, duration = 2 })
	local frozen, strikes = false, 0
	for _, f in frames do
		if f.freeze > 0 then frozen = true end
		for _, e in f.events do if e.kind == "strike" then strikes += 1 end end
	end
	check(not frozen, "no hit reported -> no hit-stop")
	check(strikes == 1, "single press -> single strike then exit")
	local last = frames[#frames]
	check(last.pose == nil and not last.active, "combo releases to Animate after one strike")

	local joints = rig(1)
	local s = Player.new(joints)
	Player.attack(s)
	local t = 0
	local pressedEarly
	while s.t < 0.1 or t == 0 do Player.step(s, 1 / 60, idleBase(t), 0); t += 1 / 60 end
	pressedEarly = Player.attack(s)
	check(pressedEarly == false and not s.queued, "press before inputOpen is ignored (mash guard)")
	while s.t < Spec.STRIKES[1].contact + 0.02 do Player.step(s, 1 / 60, idleBase(t), 0); t += 1 / 60 end
	check(Player.reportHit(s) == true, "late hit (<= HIT_LATE after contact) accepted")
	Player.step(s, 1 / 60, idleBase(t), 0)
	check(s.freeze > 0 and s.hitDone, "late hit freezes immediately")
end

-- 5. walking during the combo: legs + Root hand back to the Animator, upper body keeps the combo
do
	local frames, joints = run(1, 60, { 0 }, { speed = function() return 12 end, duration = 0.5 })
	local f = frames[#frames - 2]
	check(f.pose and Kit.angleBetween(f.pose.LeftHip, f.base.LeftHip) < math.rad(0.5), "walking: legs follow the Animator")
	check(f.pose and Kit.angleBetween(f.pose.RightShoulder, f.base.RightShoulder) > math.rad(20), "walking: sword arm keeps the combo")
end

-- 6. leg IK exactness and stance reach margins (all frames of a full combo at 1.0x)
do
	local joints = rig(1)
	local s = Player.new(joints, { autoHit = true })
	local worstErr, worstReach = 0, 0
	local presses = { 0, 0.35, 0.85 }
	local pi, t = 1, 0
	local leg = Kit.legLength(joints, "Left")
	while t < 4 do
		if presses[pi] and presses[pi] <= t + 1e-9 then Player.attack(s); pi += 1 end
		local pose = Player.step(s, 1 / 60, idleBase(t), 0)
		if pose and s.feet and not s.exiting then
			for _, side in { "Left", "Right" } do
				local f = s.feet[side]
				local want = (not f.step) and f.planted or nil
				if want then
					local got = Kit.footFrame(pose, joints, side)
					local e = (got.Position - want.Position).Magnitude
					if e > worstErr then worstErr = e; stats.ikAt = string.format("%s strike=%d t=%.3f", side, s.strike, s.t) end
				end
				local hipBase = Kit.jointData(joints.Root).c0 * pose.Root * Kit.jointData(joints.Root).c1:Inverse() * joints[side .. "Hip"].C0
				local ankle = (Kit.footFrame(pose, joints, side) * joints[side .. "Ankle"].C1).Position
				worstReach = math.max(worstReach, (ankle - hipBase.Position).Magnitude / leg)
			end
		end
		t += 1 / 60
	end
	check(worstErr < 1e-3, string.format("IK puts planted feet exactly on target (max err %.5f)", worstErr))
	check(worstReach < 0.999, string.format("legs never hit full extension (max reach %.3f of leg length)", worstReach))
	stats.ik = { worstErr, worstReach }
end

-- 7. leg angles actually used (for SPEC.md): knee flex / hip at key moments of the combo at 1.0x
if DUMP then
	local joints = rig(1)
	local s = Player.new(joints, { autoHit = true })
	local marks = { { 1, 0.34 }, { 1, 0.41 }, { 1, 0.63 }, { 2, 0.23 }, { 2, 0.30 }, { 3, 0.38 }, { 3, 0.47 }, { 3, 0.60 } }
	local presses = { 0, 0.35, 0.85 }
	local pi, t = 1, 0
	local done = {}
	while t < 4 do
		if presses[pi] and presses[pi] <= t + 1e-9 then Player.attack(s); pi += 1 end
		local pose = Player.step(s, 1 / 60, idleBase(t), 0)
		for mi, m in marks do
			if not done[mi] and pose and s.strike == m[1] and s.t >= m[2] - 1e-9 and not s.exiting then
				done[mi] = true
				local function e(n) local x, y, z = pose[n]:ToEulerAnglesXYZ() return string.format("(%4.0f,%4.0f,%4.0f)", deg(x), deg(y), deg(z)) end
				print(string.format("legs S%d t=%.2f LHip%s LKnee%s LAnkle%s RHip%s RKnee%s RAnkle%s", m[1], m[2],
					e("LeftHip"), e("LeftKnee"), e("LeftAnkle"), e("RightHip"), e("RightKnee"), e("RightAnkle")))
			end
		end
		t += 1 / 60
	end
end

if DUMP then
	print(serde.encode("json", stats))
end
local labels = {}
for label, n in failures do table.insert(labels, label .. " x" .. n) end
table.sort(labels)
for _, label in labels do print("FAIL " .. label) end
if #labels > 0 then
	error("sword combo: " .. #labels .. " failing contracts")
end
print("PASS sword combo checks=" .. checks)
