-- Offline contracts for assets/AvatarPoseKit.luau on a measured R15 rig at several body scales.
-- Also the template for testing your own pose layer offline: load the rig JSON (scripts/studio/dump_rig.luau output)
-- into table joints, load the module with luau.load + an environment, and assert measurable contracts.
--
--   lune run scripts/test_pose_kit.luau [path/to/AvatarPoseKit.luau] [path/to/rig.json]
-- (run from the skill folder, or pass paths). Prints "PASS pose kit checks=N" or the failing labels.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3 = rbx.CFrame, rbx.Vector3

local kitPath = process.args[1] or "assets/AvatarPoseKit.luau"
local rigPath = process.args[2] or "assets/rig-r15-sample.json"

local checks, failures = 0, {}
local function check(ok, label)
	checks += 1
	if not ok then failures[label] = (failures[label] or 0) + 1 end
end
local function r(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y or 0), math.rad(z or 0)) end

-- Load a Roblox module offline: inject the globals it uses. typeof must say "table" for mock joints.
local env = { CFrame = CFrame, Vector3 = Vector3, Enum = rbx.Enum,
	typeof = function(v) return type(v) == "table" and "table" or typeof(v) end }
local Kit = luau.load(fs.readFile(kitPath), { environment = env })()

-- Rig JSON: { Joint = { c0 = {12 numbers}, c1 = {12}, s1 = {x,y,z} (Part1 size), p0, p1 }, _hipHeight, _rootSize }.
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

for _, scale in { 0.8, 1, 1.3 } do
	local joints = rig(scale)
	local tag = " @scale " .. scale
	-- 1. standing sole height: both feet level and at the physical floor (HipHeight + root half height below the root)
	local neutral = Kit.neutralLow(joints)
	local l, r0 = Kit.soleLow({}, joints, "Left"), Kit.soleLow({}, joints, "Right")
	check(neutral and math.abs(l - r0) < 1e-3, "bind pose: feet level" .. tag)
	if scale == 1 then
		local floor = -(rigData._hipHeight + rigData._rootSize[2] * 0.5)
		check(math.abs(neutral - floor) < 0.15, "bind pose sole within 0.15 of HipHeight floor (" .. string.format("%.3f vs %.3f", neutral, floor) .. ")")
	end

	-- 2. groundLowest puts the lower sole exactly on the floor for crouches, lunges and tilted feet
	local poses = {
		crouch = { LeftHip = r(50), LeftKnee = r(-95), LeftAnkle = r(45), RightHip = r(50), RightKnee = r(-95), RightAnkle = r(45) },
		lunge = { LeftHip = r(70), LeftKnee = r(-80), RightHip = r(-25), RightKnee = r(-10), RightAnkle = r(-20) },
		tiptoe = { LeftAnkle = r(-35), RightAnkle = r(-35) },
		banked = { Root = r(0, 0, 20), LeftHip = r(10, 0, -15), RightHip = r(10, 0, -15) },
	}
	for name, pose in poses do
		local out = Kit.groundLowest(pose, joints)
		check(math.abs(Kit.lowestSole(out, joints) - neutral) < 1e-4, "groundLowest " .. name .. tag)
		for joint, cf in pose do
			if joint ~= "Root" then check(out[joint] == cf, "groundLowest never rotates " .. joint .. tag) end
		end
		-- raise-only never lowers a clear pose, and lifts a sunk one exactly
		local lifted = Kit.shiftRootY(out, joints, 0.3)
		check(Kit.raiseLowest(lifted, joints, neutral) == lifted, "raiseLowest leaves a clear pose alone " .. name .. tag)
		local sunk = Kit.shiftRootY(out, joints, -0.3)
		check(math.abs(Kit.lowestSole(Kit.raiseLowest(sunk, joints, neutral), joints) - neutral) < 1e-4, "raiseLowest lifts a sunk pose " .. name .. tag)
	end

	-- 3. two-bone IK: exact placement when reachable, foot keeps world orientation, soft stop when not
	local swing = { LeftHip = r(40, 0, 8), LeftKnee = r(-70), LeftAnkle = r(15), RightHip = r(-10), RightKnee = r(-20) }
	local low0 = Kit.soleLow(swing, joints, "Left")
	local footBefore = Kit.footFrame(swing, joints, "Left")
	for _, dy in { -0.2, -0.1, 0.2, 0.5 } do -- reachable; -0.3 and below run into the soft zone for this pose
		local out = Kit.reachFoot(swing, joints, "Left", low0 + dy)
		local low = Kit.soleLow(out, joints, "Left")
		check(math.abs(low - (low0 + dy)) < 2e-3 * scale, "reachFoot reaches dy=" .. dy .. tag)
		local footAfter = Kit.footFrame(out, joints, "Left")
		check(Kit.angleBetween(footBefore.Rotation, footAfter.Rotation) < math.rad(0.5), "reachFoot keeps the foot's world orientation dy=" .. dy .. tag)
		check(out.RightHip == swing.RightHip and out.RightKnee == swing.RightKnee, "reachFoot leaves the other leg alone" .. tag)
		local kx = out.LeftKnee:ToEulerAnglesXYZ()
		check(kx <= 1e-4, "knee never hyperextends dy=" .. dy .. tag)
	end
	local near = Kit.reachFoot(swing, joints, "Left", low0 - 0.4)
	local nearLow = Kit.soleLow(near, joints, "Left")
	check(nearLow < low0 - 0.25 and nearLow > low0 - 0.4, "near full extension: soft IK stops a little short" .. tag)
	check((near.LeftKnee:ToEulerAnglesXYZ()) < -math.rad(5), "soft IK keeps the knee bent" .. tag)
	local far = Kit.reachFoot(swing, joints, "Left", low0 - 10)
	local farLow = Kit.soleLow(far, joints, "Left")
	check(farLow == farLow and farLow > low0 - 10 and farLow < low0, "unreachable target: soft stop, finite, moved toward it" .. tag)

	-- 3b. uneven ground: each foot on its own floor, authored swing lift kept, pelvis drops only as needed
	local stand = { LeftHip = r(8), LeftKnee = r(-14), LeftAnkle = r(6), RightHip = r(8), RightKnee = r(-14), RightAnkle = r(6) }
	stand = Kit.groundLowest(stand, joints)
	check(Kit.fitFeetToFloor(stand, joints, neutral, neutral, 1) ~= nil, "fitFeetToFloor flat runs" .. tag)
	local flat = Kit.fitFeetToFloor(stand, joints, neutral, neutral, 1)
	check(math.abs(Kit.soleLow(flat, joints, "Left") - neutral) < 1e-3 and math.abs(Kit.soleLow(flat, joints, "Right") - neutral) < 1e-3, "flat floor: feet stay on it" .. tag)
	for _, case in { { 0.4, -0.3 }, { 0.9, 0 }, { -0.5, 0.2 }, { 0.25, 0.25 } } do
		local fl, fr = neutral + case[1] * scale, neutral + case[2] * scale
		local out = Kit.fitFeetToFloor(stand, joints, fl, fr, 1)
		local l2, r2 = Kit.soleLow(out, joints, "Left"), Kit.soleLow(out, joints, "Right")
		local label = string.format(" (%.2f, %.2f)", case[1], case[2]) .. tag
		check(math.abs(l2 - fl) < 5e-3 * scale and math.abs(r2 - fr) < 5e-3 * scale, "uneven floor: both feet on their floors" .. label)
		for _, n in Kit.R15_JOINTS do
			local cf = out[n]
			if cf then local ok = true for _, v in { cf:GetComponents() } do if v ~= v then ok = false end end check(ok, "uneven floor: finite " .. n) end
		end
	end
	local half = Kit.fitFeetToFloor(stand, joints, neutral + 0.4, neutral - 0.3, 0)
	check(half == stand, "weight 0 leaves the pose alone" .. tag)
	-- a foot high in its swing is not pulled down to a lower floor, and does not drag the pelvis
	local stepping = table.clone(stand)
	stepping.RightHip, stepping.RightKnee, stepping.RightAnkle = r(45), r(-90), r(45)
	stepping = Kit.groundLowest(stepping, joints)
	local swingLow = Kit.soleLow(stepping, joints, "Right")
	local stepOut = Kit.fitFeetToFloor(stepping, joints, neutral, neutral - 0.5, 1)
	check(math.abs(Kit.soleLow(stepOut, joints, "Right") - swingLow) < 0.1 * scale, "swinging foot keeps its lift" .. tag)
	-- default: a pose with both feet up (run flight) is planted; keepFlight leaves it in the air
	local flight = Kit.shiftRootY(stand, joints, 0.3)
	local planted = Kit.fitFeetToFloor(flight, joints, neutral, neutral, 1)
	check(math.abs(Kit.lowestSole(planted, joints) - neutral) < 5e-3 * scale, "default plants the lower foot" .. tag)
	local kept = Kit.fitFeetToFloor(flight, joints, neutral, neutral, 1, { keepFlight = true })
	check(math.abs(Kit.lowestSole(kept, joints) - (neutral + 0.3)) < 5e-3 * scale, "keepFlight keeps both feet up" .. tag)
	check(math.abs(Kit.soleLow(stepOut, joints, "Left") - neutral) < 5e-3 * scale, "planted foot stays planted while the other swings" .. tag)

	-- a floor far above the foot (a ledge the body has not stepped onto): raise is capped, the knee never folds past ~140
	local leg = Kit.legLength(joints, "Left")
	local ledge = Kit.fitFeetToFloor(stand, joints, neutral + 2 * leg, neutral, 1)
	local raised = Kit.soleLow(ledge, joints, "Left") - Kit.soleLow(stand, joints, "Left")
	check(raised <= 0.55 * leg + 1e-3, "maxRaise caps the IK raise" .. tag)
	check(-math.deg((ledge.LeftKnee:ToEulerAnglesXYZ())) < 140, "capped raise keeps the knee below 140 degrees of flex" .. tag)
	-- smoothFloor turns a one-frame step edge into a ramp at `rate`
	local f = Kit.smoothFloor(nil, 0, 1 / 60)
	f = Kit.smoothFloor(f, 1, 1 / 60, 12)
	check(math.abs(f - 0.2) < 1e-9, "smoothFloor moves at most rate*dt per frame" .. tag)
	check(Kit.smoothFloor(0.95, 1, 1 / 60, 12) == 1, "smoothFloor reaches the target" .. tag)

	-- 4. rate limits
	local a, b = CFrame.identity, r(90)
	check(math.abs(Kit.angleBetween(a, Kit.limitRotation(a, b, math.rad(6))) - math.rad(6)) < 1e-4, "limitRotation caps the step" .. tag)
	check(Kit.limitRotation(a, r(3), math.rad(6)) == r(3), "limitRotation passes small steps" .. tag)
	-- correction limit rides on top of live motion: live moved 10 deg, correction budget 6 deg at 360 deg/s * 1/60
	local carried = Kit.carryLimit(r(0), r(0), r(10), r(40), 1 / 60)
	check(math.abs(math.deg(Kit.angleBetween(r(0), carried)) - 16) < 0.05, "carryLimit = live motion + rate*dt" .. tag)

	-- 5. carried transition start is continuous and returns to the plain blend at the end
	local v = Kit.jointVelocity(r(0), r(3), 1 / 60)
	check(Kit.carriedStart(r(10), v, 0, 0.3) == r(10), "carriedStart at t=0 is the start pose" .. tag)
	check(Kit.angleBetween(Kit.carriedStart(r(10), v, 0.3, 0.3), r(10)) < 1e-6, "carriedStart carry ends at zero" .. tag)
end

-- 6. springs and secondary motion (bank formula, clamps, frame-rate independence, sole stays planted)
local S = Kit.Secondary
local joints = rig(1)
local base = Kit.groundLowest({ Root = CFrame.identity, Waist = CFrame.identity, Neck = CFrame.identity,
	LeftShoulder = CFrame.identity, RightShoulder = CFrame.identity,
	LeftHip = r(20), LeftKnee = r(-30), RightHip = r(-15), RightKnee = r(-10) }, joints)
local lowBase = Kit.lowestSole(base, joints)
for _, fps in { 30, 60, 144 } do
	for _, speed in { 16, 30, 60 } do
		for _, dir in { 1, -1 } do
			local omega = 1.2 * dir
			local s = S.new()
			for f = 1, fps * 3 do
				local t = f / fps
				S.update(s, Vector3.new(-math.sin(omega * t), 0, -math.cos(omega * t)) * speed, 1 / fps, 196.2)
			end
			local p = S.DEFAULTS
			local fade = Kit.smoothstep((speed - p.bankMinSpeed) / p.bankSpeedSpan)
			local expected = math.clamp(math.atan(speed * omega * p.bankGain / 196.2), -p.bankMax, p.bankMax) * fade
			check(math.abs(s.bank - expected) < math.rad(1), string.format("steady bank = atan(gain v w / g) fps=%d v=%d", fps, speed))
			check(math.sign(s.bank) == dir, "banks into the turn (+ = left)")
			check(math.sign(s.headYaw) == dir, "head leads the turn")
			local out = S.apply(s, base, joints)
			local posed = table.clone(base)
			for k2, cf in out do posed[k2] = cf end
			check(math.abs(Kit.lowestSole(posed, joints) - lowBase) < 1e-4, "bank keeps the planted sole's height")
		end
	end
end
do
	local s = S.new()
	for _ = 1, 60 do S.update(s, Vector3.new(0, 0, -50), 1 / 60, 196.2) end
	check(math.abs(s.bank) < 1e-4 and math.abs(s.pitch) < math.rad(0.2), "straight, constant speed: no added motion")
	S.update(s, Vector3.new(400, 0, 90), 1 / 60, 196.2) -- knockback spike
	check(math.abs(s.bank) <= S.DEFAULTS.bankMax + 1e-6, "spike stays clamped")
	for _ = 1, 90 do S.update(s, Vector3.new(0, 0, -50), 1 / 60, 196.2, S.OFF) end
	check(not s.active, "OFF weights fade the layer out")
end

local labels = {}
for label, n in failures do table.insert(labels, label .. " x" .. n) end
table.sort(labels)
for _, label in labels do print("FAIL " .. label) end
if #labels > 0 then
	error("pose kit: " .. #labels .. " failing contracts")
end
print("PASS pose kit checks=" .. checks)
