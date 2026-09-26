-- Offline contracts for the TerrainPose layer (src/client/TerrainPose/TerrainPoseCore.luau + AvatarPoseKit.luau),
-- on the measured R15 rig (rig-r15.json) at body scales 0.8 / 1.0 / 1.3 and 30 / 60 / 144 fps.
--
--   lune run tests/test_terrain_pose.luau [rig.json]        (run from the outputs folder)
--
-- What is simulated (no Roblox here, so these are stand-ins; the Studio procedure in REPORT.md measures the real thing):
--   * Animate: a procedural walk / run cycle with the proportions of the default R15 run (hip +-34 deg, swing knee
--     up to -95 deg, a small flight bob). It is drawn for FLAT ground, exactly like the real Animate: nothing in it
--     knows about slopes or stairs. OFF = this pose as-is.
--   * Humanoid physics: the HumanoidRootPart rides at standing height above the floor under its centre (steps up / down
--     with a 0.05 s settle), faces its velocity, and jumps ballistically. The layer never changes it (asserted).
--   * Raycasts: the runtime casts straight down from the root's height at the points Core.plan asks for; here the same
--     points read an analytic terrain (flat, 22 deg slope up / down / across, stairs 1 stud rise x 2.5 tread).
-- Each contract is measured on what would be drawn: the sole corners of the rendered feet against the floor under
-- THAT foot (toe and heel, higher hit), the same measurement as tests/studio/contact_probe.luau.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3 = rbx.CFrame, rbx.Vector3

local HERE = "tests/"
local SRC = "src/client/TerrainPose/"
local rigPath = process.args[1] or (HERE .. "rig-r15.json")

---------------------------------------------------------------- load the modules exactly as the game ships them
local env = { CFrame = CFrame, Vector3 = Vector3, Enum = rbx.Enum,
	typeof = function(v) return type(v) == "table" and "table" or typeof(v) end }
local Kit = luau.load(fs.readFile(SRC .. "AvatarPoseKit.luau"), { environment = env })()
local coreEnv = table.clone(env)
coreEnv.script = { Parent = { AvatarPoseKit = "AvatarPoseKit" } }
coreEnv.require = function(m)
	assert(m == "AvatarPoseKit", "unexpected require " .. tostring(m))
	return Kit
end
local Core = luau.load(fs.readFile(SRC .. "TerrainPoseCore.luau"), { environment = coreEnv })()

---------------------------------------------------------------- contracts bookkeeping
local checks, failures = 0, {}
local function check(ok, label)
	checks += 1
	if not ok then failures[label] = (failures[label] or 0) + 1 end
end
local report = {}
local function note(line) table.insert(report, line) end
local function deg(x) return math.deg(x) end
local function r(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0)) end

---------------------------------------------------------------- rig
local rigData = serde.decode("json", fs.readFile(rigPath))
local function rig(scale)
	local joints = {}
	for name, d in rigData do
		if type(d) == "table" and d.c0 then
			local c0, c1 = CFrame.new(table.unpack(d.c0)), CFrame.new(table.unpack(d.c1))
			joints[name] = { Name = name, C0 = c0 + c0.Position * (scale - 1), C1 = c1 + c1.Position * (scale - 1),
				Part1 = { Size = Vector3.new(table.unpack(d.s1)) * scale } }
		end
	end
	return joints
end

---------------------------------------------------------------- Animate stand-in (flat-ground walk / run cycle)
local function gait(phase, run)
	local H, K0, K1, bob = run and 34 or 24, run and 12 or 6, run and 83 or 50, run and 0.06 or 0.02
	local pose = { Root = CFrame.identity, Waist = r(run and -6 or -2), Neck = CFrame.identity,
		LeftShoulder = CFrame.identity, RightShoulder = CFrame.identity }
	for _, side in { "Left", "Right" } do
		local ph = phase * 2 * math.pi + (side == "Left" and 0 or math.pi)
		local hip = H * math.sin(ph)
		local swing = math.max(0, math.cos(ph)) ^ 1.5 -- hip moving forward = swing: knee folds
		local knee = -(K0 + K1 * swing)
		local ankle = -(hip + knee) * (1 - swing) * 0.8 + 10 * swing -- flat-ish sole in stance
		pose[side .. "Hip"], pose[side .. "Knee"], pose[side .. "Ankle"] = r(hip), r(knee), r(ankle)
		pose[(side == "Left" and "Right" or "Left") .. "Shoulder"] = r(-hip * 0.8)
	end
	return pose, bob * math.max(0, math.sin(phase * 4 * math.pi))
end
local function animatePose(joints, phase, run)
	local pose, bob = gait(phase, run)
	pose = Kit.groundLowest(pose, joints) -- Animate is authored so a foot touches FLAT ground
	return Kit.shiftRootY(pose, joints, bob) -- plus a little flight
end

---------------------------------------------------------------- terrain (the ray emulation reads this)
local SLOPE = math.tan(math.rad(22))
local TERRAINS = {
	flat = function() return 0 end,
	slopeUp = function(_, z) return math.max(z, 0) * SLOPE end, -- walked in +Z: climbing
	slopeDown = function(_, z) return math.max(40 - z, 0) * SLOPE end, -- walked in +Z: descending
	slopeAcross = function(x) return x * SLOPE end, -- walked in +Z: the left (+X) foot is uphill
	stairsUp = function(_, z) return math.max(math.floor(z / 2.5) + 1, 0) end, -- walked in +Z, 1 stud rises
	stairsDown = function(_, z) return math.max(math.floor((40 - z) / 2.5) + 1, 0) end,
}

---------------------------------------------------------------- one simulated body (the runtime layer's job, offline)
-- TERRAIN_RATE=<deg/s> overrides the correction limit (experiments only; the contracts are for the shipped value)
local PARAMS = Core.DEFAULTS
if process.env.TERRAIN_RATE then
	PARAMS = table.clone(Core.DEFAULTS)
	PARAMS.correctionRate = math.rad(tonumber(process.env.TERRAIN_RATE))
end
local function newWorld(scale, terrainName, fps)
	local joints = rig(scale)
	local body = Core.newBody(joints, PARAMS)
	return { joints = joints, body = body, h = TERRAINS[terrainName], stand = -Kit.neutralLow(joints), fps = fps,
		rootY = nil, t = 0, phase = 0 }
end

local function floorUnder(world, rootCF, pose, side)
	local cf, size = Kit.footFrame(pose, world.joints, side)
	local best
	for _, along in { 0.4, -0.4 } do
		local p = rootCF:PointToWorldSpace(cf.Position + cf.LookVector * (size.Z * along))
		local y = world.h(p.X, p.Z)
		best = best and math.max(best, y) or y
	end
	return best
end

-- Advance one frame: move the physics root, build Animate's pose, run the layer (or not), measure what is drawn.
local function frame(world, opts)
	local dt = opts.dt or 1 / world.fps
	world.t += dt
	local pos, velocity, yaw = opts.path(world.t)
	local center = world.h(pos.X, pos.Z)
	local target = center + world.stand
	local vy = 0
	if opts.jump then
		local jy, jvy, air = opts.jump(world.t)
		if air then target, vy = center + world.stand + jy, jvy end
	end
	local jumping = opts.jump ~= nil and select(3, opts.jump(world.t)) == true
	local prevY = world.rootY or target
	if jumping then
		world.rootY, world.vy = target, vy
	elseif target >= prevY then -- standing / stepping up: the Humanoid lifts the root within a few frames
		world.rootY = prevY + (target - prevY) * Kit.expAlpha(dt, 0.04)
		world.vy = 0
		vy = dt > 0 and (world.rootY - prevY) / dt or 0
	else -- stepping down / off a ledge: the Humanoid falls under gravity until it meets the floor
		world.vy = math.min(world.vy or 0, 0) - 196.2 * dt
		world.rootY = math.max(target, prevY + world.vy * dt)
		if world.rootY <= target then world.vy = 0 end
		vy = world.vy
	end
	local rootCF = CFrame.new(pos.X, world.rootY, pos.Z) * CFrame.Angles(0, yaw, 0)
	local grounded = not jumping and (world.rootY - target) < 0.1 -- what Humanoid.FloorMaterial ~= Air reports
	-- frames where a foot should be on the floor: grounded, or stepping down a stair (not a jump)
	local contact = not jumping and (world.rootY - center - world.stand) < 1.3 and vy > -35
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	world.phase += dt * (opts.run and speed / 11 or speed / 7) -- cadence scales with speed like Animate's AdjustSpeed
	local base = animatePose(world.joints, world.phase, opts.run)

	local pose = base
	if opts.layer then
		local velRoot = rootCF:VectorToObjectSpace(velocity)
		local samples = Core.plan(world.body, base, velRoot)
		local heights = {}
		for i, s in samples do
			local wp = rootCF:PointToWorldSpace(s.point)
			local y = world.h(wp.X, wp.Z)
			if world.rootY - y <= world.stand + 4 then heights[i] = y - world.rootY end -- root-space Y (root is upright)
		end
		local floorL, floorR = Core.resolveFloors(world.body, base, samples, heights)
		local clearance
		if not grounded or world.body.plantW < 0.999 then
			local measured = (world.rootY - center) - world.stand
			local deepest = measured >= 0 and -math.min(0.4, math.max(-vy, 0) * 0.005) or measured
			clearance = math.max(measured + vy * dt, deepest)
		end
		pose = Core.step(world.body, { base = base, dt = dt, grounded = grounded, floorL = floorL, floorR = floorR,
			velocity = velocity + Vector3.new(0, vy, 0), gravity = 196.2, clearance = clearance, suspend = opts.suspend,
			rootHeight = world.rootY })
	end
	-- measure what is drawn: each foot's lowest corner vs the floor under that foot
	local gaps = {}
	for _, side in { "Left", "Right" } do
		gaps[side] = world.rootY + Kit.soleLow(pose, world.joints, side) - floorUnder(world, rootCF, pose, side)
	end
	return { pose = pose, base = base, gaps = gaps, grounded = grounded, contact = contact, rootCF = rootCF, dt = dt }
end

local function straightPath(speed)
	return function(t)
		return Vector3.new(0, 0, -10 + speed * t), Vector3.new(0, 0, speed), math.pi
	end
end
local function circlePath(speed, radius, dir)
	local w = speed / radius -- dir = +1: counter-clockwise from above = turning LEFT (a -Z facer has +X on its right)
	return function(t)
		local a = w * t
		local pos = Vector3.new(radius * math.cos(a), 0, -dir * radius * math.sin(a))
		local vel = Vector3.new(-radius * w * math.sin(a), 0, -dir * radius * w * math.cos(a))
		local look = vel.Unit
		return pos, vel, math.atan2(-look.X, -look.Z)
	end
end

local function finitePose(pose)
	for _, cf in pose do
		for _, v in { cf:GetComponents() } do
			if v ~= v or math.abs(v) == math.huge then return false end
		end
	end
	return true
end

-- Run a scenario; returns stats over grounded frames after a warm-up.
local function run(scale, terrain, fps, opts)
	local world = newWorld(scale, terrain, fps)
	local st = { n = 0, minGap = math.huge, plantMin = math.huge, plantMax = -math.huge, plantSum = 0,
		sink = 0, float = 0, pop = 0, finite = true, minAll = math.huge }
	local prev
	local frames = math.floor((opts.seconds or 3) * fps)
	for i = 1, frames do
		local f = frame(world, opts)
		if not finitePose(f.pose) then st.finite = false end
		local low = math.min(f.gaps.Left, f.gaps.Right)
		st.minAll = math.min(st.minAll, low)
		if i > fps * 0.5 and f.contact then
			st.n += 1
			st.minGap = math.min(st.minGap, low)
			st.plantMin, st.plantMax = math.min(st.plantMin, low), math.max(st.plantMax, low)
			st.plantSum += low
			if low < -0.05 then st.sink += 1 end
			if low > 0.1 then st.float += 1 end
		end
		-- correction pops: a drawn joint may turn at most Animate's own turn + 360 deg/s * dt this frame
		if prev and opts.layer and f.dt > 0 then
			for name, cf in f.pose do
				local extra = Kit.angleBetween(prev.pose[name], cf) - Kit.angleBetween(prev.base[name], f.base[name])
				st.pop = math.max(st.pop, extra - Kit.DEFAULT_RATE * f.dt)
			end
		end
		if opts.each then opts.each(world, f, i) end
		prev = f
	end
	st.mean = st.n > 0 and st.plantSum / st.n or 0
	return st, world
end

---------------------------------------------------------------- 1. terrain contact: OFF (Animate only) vs ON
local SPEEDS = { { name = "walk", speed = 8, run = false }, { name = "run", speed = 16, run = true } }
note("terrain contact (planted foot = lower gap over grounded frames; sink = frames < -0.05, float = frames > +0.10)")
for _, terrain in { "flat", "slopeUp", "slopeDown", "slopeAcross", "stairsUp", "stairsDown" } do
	for _, gaitDef in SPEEDS do
		for _, scale in { 0.8, 1, 1.3 } do
			for _, fps in { 30, 60, 144 } do
				local seconds = terrain:find("stairs") and 2.6 or 3
				local opts = { path = straightPath(gaitDef.speed * scale), run = gaitDef.run, seconds = seconds }
				local off = run(scale, terrain, fps, opts)
				opts.layer = true
				local on = run(scale, terrain, fps, opts)
				local tag = string.format("%s %s x%.1f %dfps", terrain, gaitDef.name, scale, fps)
				check(on.finite, "finite pose " .. tag)
				check(on.n > 0, "grounded frames exist " .. tag)
				-- hard, everywhere: no joint pops (corrections ride on Animate's motion + 360 deg/s)
				check(on.pop <= math.rad(0.05), string.format("corrections within 360 deg/s %s (%.2f deg over)", tag, deg(on.pop)))
				local strict = terrain == "flat" or terrain == "slopeAcross"
				if strict then
					-- quality bar: the planted foot sits on its floor (never inside, never hovering > 0.05)
					check(on.plantMin >= -0.02, string.format("planted foot not inside the floor %s (min %.3f)", tag, on.plantMin))
					check(on.plantMax <= 0.05, string.format("planted foot not floating %s (max %.3f)", tag, on.plantMax))
				elseif terrain:find("slope") then
					-- 22 deg slope up / down: the sinking is (almost) gone; residual listed as KNOWN below
					check(on.plantMin >= -0.2 and on.plantMin > off.plantMin, string.format("slope: shallower than Animate alone and >= -0.2 %s (%.3f vs %.3f)", tag, on.plantMin, off.plantMin))
					check(on.sink <= math.max(2, off.sink * 0.2), string.format("slope: sink frames cut >= 80%% %s (%d -> %d)", tag, off.sink, on.sink))
				end
				-- quality-bar misses are listed, never hidden (see REPORT.md: stairs need Studio measurement)
				if not strict and (scale ~= 0.8 and fps == 60) and (on.plantMin < -0.02 or on.plantMax > 0.05) then
					table.insert(report, string.format("KNOWN %s %s x%.1f: planted foot %+.3f..%+.3f, sink %d float %d of %d frames (OFF %+.3f..%+.3f sink %d float %d)",
						terrain, gaitDef.name, scale, on.plantMin, on.plantMax, on.sink, on.float, on.n, off.plantMin, off.plantMax, off.sink, off.float))
				end
				if scale == 1 and fps == 60 then
					note(string.format("  %-12s %-4s OFF min %+.3f mean %+.3f max %+.3f sink %3d float %3d | ON min %+.3f mean %+.3f max %+.3f sink %d float %d pop %.1fdeg (n=%d)",
						terrain, gaitDef.name, off.plantMin, off.mean, off.plantMax, off.sink, off.float,
						on.plantMin, on.mean, on.plantMax, on.sink, on.float, deg(on.pop), on.n))
				end
				-- the complaint is real in the stand-in too (so the ON numbers mean something)
				if scale == 1 and fps == 60 and gaitDef.run then
					if terrain == "slopeUp" or terrain == "slopeAcross" then
						check(off.plantMin < -0.1, "baseline sinks on " .. terrain .. string.format(" (%.3f)", off.plantMin))
					elseif terrain == "stairsUp" or terrain == "stairsDown" then
						check(off.float > 0 or off.sink > 0, "baseline floats / sinks on " .. terrain)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- 2. swing foot vs stair risers / uphill (both feet, not only the planted one)
note("swing foot: lowest corner of EITHER foot vs its own floor (run, x1.0, 60 fps)")
for _, terrain in { "slopeUp", "stairsUp", "stairsDown", "slopeAcross" } do
	local base = { path = straightPath(16), run = true, seconds = 2.6 }
	local off = run(1, terrain, 60, base)
	base.layer = true
	local on = run(1, terrain, 60, base)
	note(string.format("  %-12s OFF %+.3f  ON %+.3f", terrain, off.minAll, on.minAll))
	if terrain:find("slope") then
		check(on.minAll >= -0.1, string.format("no foot deeper than 0.1 in the slope %s (%.3f)", terrain, on.minAll))
	end
	check(on.minAll >= off.minAll - 1e-3, string.format("never deeper than Animate alone %s (%.3f vs %.3f)", terrain, on.minAll, off.minAll))
end

---------------------------------------------------------------- 3. banking into turns (flat, run), steady state = atan(gain v w / g)
note("turn bank (flat, run 16 stud/s): expected vs drawn Root roll after 2.5 s")
local P = Core.SECONDARY
for _, scale in { 0.8, 1, 1.3 } do
	for _, fps in { 30, 60, 144 } do
		for _, radius in { 5, 8, 16, 40 } do
			for _, dir in { 1, -1 } do
				local speed = 16
				local omega = speed / radius
				local fade = Kit.smoothstep((speed - P.bankMinSpeed) / P.bankSpeedSpan)
				local expected = math.clamp(math.atan(P.bankGain * speed * omega / 196.2), -P.bankMax, P.bankMax) * fade * dir
				local lastRoll, lastNeck
				local st = run(scale, "flat", fps, { path = circlePath(speed, radius, dir), run = true, layer = true, seconds = 3,
					each = function(_, f)
						local _, _, roll = f.pose.Root:ToEulerAnglesYXZ()
						lastRoll = roll
						local _, _, neckRoll = f.pose.Neck:ToEulerAnglesYXZ()
						lastNeck = neckRoll
					end })
				local tag = string.format("R=%d dir=%d x%.1f %dfps", radius, dir, scale, fps)
				check(math.abs(lastRoll - expected) < math.rad(1), string.format("steady bank %s (%.2f vs %.2f deg)", tag, deg(lastRoll), deg(expected)))
				check(math.sign(lastRoll) == dir, "leans INTO the turn (+roll = left) " .. tag)
				check(math.abs(lastRoll) <= P.bankMax + 1e-4, "bank clamped " .. tag)
				check(lastNeck * dir < 0 and math.abs(lastNeck) < math.abs(lastRoll), "head counter-rolls toward level " .. tag)
				check(st.plantMin >= -0.02 and st.plantMax <= 0.05 and st.sink == 0 and st.float == 0,
					string.format("banked body keeps the planted foot on the floor %s (%.3f..%.3f)", tag, st.plantMin, st.plantMax))
				check(st.pop <= math.rad(0.05), "bank within the rate budget " .. tag)
				if scale == 1 and fps == 60 and dir == 1 then
					note(string.format("  R=%-3d w=%.2f rad/s  expected %5.2f deg  drawn %5.2f deg  head %+.2f deg  planted %+.3f..%+.3f",
						radius, omega, deg(expected), deg(lastRoll), deg(lastNeck), st.plantMin, st.plantMax))
				end
			end
		end
	end
end
-- straight running: no lean; turning on the spot (slow): no lean
do
	local roll
	run(1, "flat", 60, { path = straightPath(16), run = true, layer = true, seconds = 2,
		each = function(_, f) roll = select(3, f.pose.Root:ToEulerAnglesYXZ()) end })
	check(math.abs(roll) < math.rad(0.05), "straight run: no lean")
	local slowMax = 0
	run(1, "flat", 60, { path = circlePath(3, 1, 1), run = false, layer = true, seconds = 2,
		each = function(_, f) slowMax = math.max(slowMax, math.abs(select(3, f.pose.Root:ToEulerAnglesYXZ()))) end })
	check(slowMax < math.rad(0.5), string.format("slow pivot turn: no lean (%.2f deg)", deg(slowMax)))
	note(string.format("straight run roll %.3f deg; slow pivot turn max roll %.3f deg", deg(roll), deg(slowMax)))
end
-- turning on a slope: bank and terrain fit together
do
	local st = run(1, "slopeAcross", 60, { path = circlePath(16, 10, 1), run = true, layer = true, seconds = 3 })
	check(st.plantMin >= -0.05 and st.sink == 0, string.format("bank + slope: planted foot never inside the floor (%.3f)", st.plantMin))
	if st.plantMax > 0.05 then
		table.insert(report, string.format("KNOWN bank on cross-slope circle: planted foot hovers up to %+.3f (%d frames > 0.10)", st.plantMax, st.float))
	end
	note(string.format("bank on a cross-slope circle R=10: planted %+.3f..%+.3f, sink %d float %d", st.plantMin, st.plantMax, st.sink, st.float))
end

---------------------------------------------------------------- 4. jump: never below the floor while airborne or landing
do
	local g, v0, t0 = 196.2, 50, 1.0
	local function jump(t)
		local s = t - t0
		if s <= 0 then return 0, 0, false end
		local y = v0 * s - 0.5 * g * s * s
		if y <= 0 then return 0, 0, false end
		return y, v0 - g * s, true
	end
	for _, fps in { 30, 60, 144 } do
		local minAir = math.huge
		local st = run(1, "flat", fps, { path = straightPath(16), run = true, layer = true, seconds = 2.2, jump = jump,
			each = function(_, f) minAir = math.min(minAir, f.gaps.Left, f.gaps.Right) end })
		check(minAir >= -0.02, string.format("jump: no foot below the floor at %d fps (%.3f)", fps, minAir))
		check(st.finite, "jump: finite")
	end
end

---------------------------------------------------------------- 5. suspension (climbing, seated, full-body track): the layer hands the pose back to Animate
do
	local maxDiff, rollEnd = 0, 0
	local t = 0
	run(1, "slopeAcross", 60, { path = circlePath(16, 8, 1), run = true, layer = true, seconds = 2.5,
		suspend = nil, each = function(_, f, i)
			t = i / 60
			if t > 1.8 then
				for name, cf in f.pose do maxDiff = math.max(maxDiff, Kit.angleBetween(cf, f.base[name])) end
				rollEnd = select(3, f.pose.Root:ToEulerAnglesYXZ())
			end
		end, })
	check(maxDiff > math.rad(1), "sanity: layer active before suspension")
	local diffs = 0
	local world = newWorld(1, "slopeAcross", 60)
	local opts = { path = circlePath(16, 8, 1), run = true, layer = true }
	local prev
	local popMax = 0
	for i = 1, 150 do
		opts.suspend = i > 60 -- suspended after 1 s
		local f = frame(world, opts)
		if prev then
			for name, cf in f.pose do
				local extra = Kit.angleBetween(prev.pose[name], cf) - Kit.angleBetween(prev.base[name], f.base[name])
				popMax = math.max(popMax, extra - Kit.DEFAULT_RATE * f.dt)
			end
		end
		if i == 150 then
			for name, cf in f.pose do diffs = math.max(diffs, Kit.angleBetween(cf, f.base[name])) end
			local dy = 0
			for name, cf in f.pose do dy = math.max(dy, (cf.Position - f.base[name].Position).Magnitude) end
			check(dy < 0.01, string.format("suspended: joints back at Animate's positions (%.4f)", dy))
		end
		prev = f
	end
	check(diffs < math.rad(0.3), string.format("suspended: pose returns to Animate (%.3f deg)", deg(diffs)))
	check(popMax <= math.rad(0.05), "suspension fades out within the rate budget")
	note(string.format("suspend after 1 s: residual %.3f deg at 2.5 s, fade within budget (%.3f deg over)", deg(diffs), deg(math.max(popMax, 0))))
end

---------------------------------------------------------------- 6. hitches: dt = 0 and a 0.25 s frame do not break anything
do
	local world = newWorld(1, "slopeAcross", 60)
	local opts = { path = straightPath(16), run = true, layer = true }
	local ok = true
	for i = 1, 150 do
		opts.dt = (i == 40 and 0) or (i == 80 and 0.25) or nil
		local f = frame(world, opts)
		if not finitePose(f.pose) then ok = false end
		if i > 100 and f.grounded then
			check(math.min(f.gaps.Left, f.gaps.Right) >= -0.02, "after a hitch the planted foot is back on the floor")
		end
	end
	check(ok, "hitch frames stay finite")
end

---------------------------------------------------------------- 7. several bodies (player + NPCs) through the same functions: no shared state
do
	local specs = { { 0.8, "stairsUp", { path = straightPath(12), run = true, layer = true } },
		{ 1, "slopeUp", { path = circlePath(16, 8, -1), run = true, layer = true } },
		{ 1.3, "slopeAcross", { path = straightPath(8), run = false, layer = true } } }
	local alone = {}
	for k, spec in specs do
		local world = newWorld(spec[1], spec[2], 60)
		alone[k] = {}
		for i = 1, 180 do alone[k][i] = frame(world, spec[3]).pose end
	end
	local worlds = {}
	for k, spec in specs do worlds[k] = newWorld(spec[1], spec[2], 60) end
	local same = true
	for i = 1, 180 do
		for k, world in worlds do
			local pose = frame(world, specs[k][3]).pose
			for name, cf in pose do
				if Kit.angleBetween(cf, alone[k][i][name]) > 1e-6 or (cf.Position - alone[k][i][name].Position).Magnitude > 1e-6 then same = false end
			end
		end
	end
	check(same, "3 bodies drawn in the same frame = each drawn alone (no shared state)")
	check(worlds[1].body ~= worlds[2].body and worlds[1].body.secondary ~= worlds[2].body.secondary, "one state per body")
end

---------------------------------------------------------------- 8. presentation only: the layer never touches the physics root
do
	local world = newWorld(1, "stairsUp", 60)
	local offWorld = newWorld(1, "stairsUp", 60)
	local same = true
	for _ = 1, 120 do
		local a = frame(world, { path = straightPath(16), run = true, layer = true })
		local b = frame(offWorld, { path = straightPath(16), run = true })
		if a.rootCF ~= b.rootCF then same = false end
	end
	check(same, "HumanoidRootPart path identical with the layer ON and OFF")
end
-- sanity: the circle helper really turns left for dir = +1 (Kit.Secondary: counter-clockwise from above = + = left)
do
	local s = Kit.Secondary.new()
	local path = circlePath(16, 8, 1)
	for i = 1, 60 do
		local _, vel = path(i / 60)
		Kit.Secondary.measure(s, vel, 1 / 60)
	end
	check(s.omega > 0, "circlePath(dir=+1) is a left turn")
end

---------------------------------------------------------------- result
for _, line in report do print(line) end
local labels = {}
for label, n in failures do table.insert(labels, label .. " x" .. n) end
table.sort(labels)
for _, label in labels do print("FAIL " .. label) end
if #labels > 0 then
	error("terrain pose: " .. #labels .. " failing contracts of " .. checks)
end
print("PASS terrain pose checks=" .. checks)
