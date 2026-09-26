-- Authoring aid (offline, Lune): solve the arm Euler angles of each key from where the hand should be and where the
-- blade should point, in UpperTorso space (so the chest's coil/lean from Root + Waist is independent).
-- Output is pasted into src/shared/SwordCombo/Spec.luau (rounded to 1 deg). Blade = RightHand -Z (Spec.BLADE_LENGTH).
--   lune run tools/solve_arm_keys.luau        (from the outputs folder)
local fs = require("@lune/fs")
local rbx = require("@lune/roblox")
local serde = require("@lune/serde")
local CFrame, Vector3 = rbx.CFrame, rbx.Vector3
local rig = serde.decode("json", fs.readFile("tests/rig-r15.json"))
local function J(n) return CFrame.new(table.unpack(rig[n].c0)), CFrame.new(table.unpack(rig[n].c1)) end
local function R(x, y, z) return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z)) end

-- hand frame in UpperTorso space for side, p = { sx, sy, sz, elbowX, wx, wz, elbowY (forearm twist) }
local function hand(side, p)
	local s0, s1 = J(side .. "Shoulder")
	local e0, e1 = J(side .. "Elbow")
	local w0, w1 = J(side .. "Wrist")
	return s0 * R(p[1], p[2], p[3]) * s1:Inverse() * e0 * R(p[4], p[7] or 0, 0) * e1:Inverse() * w0 * R(p[5], 0, p[6]) * w1:Inverse()
end

local LIMITS = { { -80, 185 }, { -90, 90 }, { -100, 100 }, { 0, 140 }, { -75, 75 }, { -45, 45 }, { -90, 90 } }
local CONTINUITY = 1.5e-5 -- per deg^2 away from the previous key: keeps consecutive keys on one branch (no forearm flips)
local function cost(side, p, target, blade, prior)
	local h = hand(side, p)
	local c = (h.Position - target).Magnitude ^ 2 * 6
	if blade then c += (h.LookVector - blade.Unit).Magnitude ^ 2 end
	for i, v in p do
		local lo, hi = LIMITS[i][1], LIMITS[i][2]
		if v < lo then c += ((lo - v) / 10) ^ 2 end
		if v > hi then c += ((v - hi) / 10) ^ 2 end
		c += CONTINUITY * (v - (prior and prior[i] or 0)) ^ 2
	end
	c += 4e-6 * (p[5] ^ 2 + p[6] ^ 2 + p[7] ^ 2) -- prefer the shoulder and elbow flex over wrist / forearm twist
	return c
end

local function solve(side, target, blade, starts, prior)
	local best, bestC
	for _, start in starts do
		local p = table.clone(start)
		local c = cost(side, p, target, blade, prior or start)
		local step = 20
		while step > 0.05 do
			local improved = false
			for i = 1, #p do
				for _, d in { step, -step } do
					local q = table.clone(p)
					q[i] += d
					local qc = cost(side, q, target, blade, prior or start)
					if qc < c then p, c, improved = q, qc, true end
				end
			end
			if not improved then step *= 0.5 end
		end
		if not bestC or c < bestC then best, bestC = p, c end
	end
	local h = hand(side, best)
	return best, (h.Position - target).Magnitude, blade and math.deg(math.acos(math.clamp(h.LookVector:Dot(blade.Unit), -1, 1))) or 0
end

local STARTS = {
	{ 40, 0, 10, 40, 0, 0, 0 }, { 150, 0, 40, 90, 0, 0, 0 }, { 90, 0, 90, 90, 0, 0, 0 }, { 90, -60, -40, 60, 0, 0, 0 },
	{ 60, 60, 60, 30, 0, 0, 0 }, { 170, 0, 0, 80, 0, 0, 0 }, { 20, -40, -40, 30, 0, 0, 0 }, { 120, 40, 20, 110, 0, 0, 0 },
}

-- Right hand targets: position (UpperTorso space) and blade direction.
local KEYS = {
	{ "GUARD", Vector3.new(0.40, -0.45, -1.10), Vector3.new(-0.10, 0.70, -0.70) },
	{ "S1 windup", Vector3.new(0.80, 1.10, 0.25), Vector3.new(-0.35, 0.55, 0.75) },
	{ "S1 hold", Vector3.new(0.82, 1.15, 0.32), Vector3.new(-0.40, 0.50, 0.78) },
	{ "S1 contact", Vector3.new(0.35, 0.35, -1.25), Vector3.new(-0.30, 0.30, -0.90) },
	{ "S1 end", Vector3.new(-0.45, -0.85, -0.75), Vector3.new(-0.55, -0.55, -0.63) },
	{ "S1 follow", Vector3.new(-0.60, -0.95, -0.55), Vector3.new(-0.65, -0.55, -0.50) },
	{ "S1 recover", Vector3.new(-0.45, -0.70, -0.85), Vector3.new(-0.60, -0.20, -0.77) },
	{ "S2 windup", Vector3.new(-0.55, 0.05, -0.55), Vector3.new(-0.55, 0.00, 0.83) },
	{ "S2 hold", Vector3.new(-0.60, 0.08, -0.50), Vector3.new(-0.60, 0.00, 0.80) },
	{ "S2 contact", Vector3.new(0.20, 0.10, -1.30), Vector3.new(0.10, 0.05, -1.00) },
	{ "S2 end", Vector3.new(1.25, 0.15, -0.60), Vector3.new(0.85, 0.05, -0.50) },
	{ "S2 follow", Vector3.new(1.40, 0.20, -0.20), Vector3.new(0.95, 0.10, 0.10) },
	{ "S2 recover", Vector3.new(1.05, 0.55, -0.30), Vector3.new(0.35, 0.90, 0.20) },
	{ "S3 windup", Vector3.new(0.15, 1.45, 0.10), Vector3.new(0.00, -0.15, 1.00) },
	{ "S3 hold", Vector3.new(0.15, 1.50, 0.15), Vector3.new(0.00, -0.25, 1.00) },
	{ "S3 impact", Vector3.new(0.12, -0.20, -1.35), Vector3.new(0.00, 0.40, -0.92) }, -- chest pitched ~38 deg: root-space blade ~(0,-0.2,-0.98)
	{ "S3 follow", Vector3.new(0.12, -0.28, -1.32), Vector3.new(0.00, 0.50, -0.86) }, -- chest pitched ~42 deg
	{ "S3 recover", Vector3.new(0.30, -0.50, -1.10), Vector3.new(0.00, 0.20, -0.98) },
}
local solved = {}
local previous = nil
for _, k in KEYS do
	local p, err, ang
	if previous then
		local starts = { previous }
		for _, st in STARTS do table.insert(starts, st) end
		p, err, ang = solve("Right", k[2], k[3], starts, previous)
	else
		p, err, ang = solve("Right", k[2], k[3], STARTS)
	end
	previous = p
	solved[k[1]] = p
	print(string.format("%-11s Right Shoulder(%4.0f,%4.0f,%4.0f) Elbow(%4.0f,%4.0f,0) Wrist(%4.0f,0,%4.0f)  hand err %.3f  blade err %.1f deg",
		k[1], p[1], p[2], p[3], p[4], p[7], p[5], p[6], err, ang))
end
local leftPrev
-- S3: the left hand joins the hilt (pommel side of the right hand) at the top and at impact
for _, name in { "S3 windup", "S3 hold", "S3 impact", "S3 follow" } do
	local h = hand("Right", solved[name])
	local target = h.Position - h.LookVector * 0.45
	local p, err = solve("Left", target, nil, { leftPrev or { 150, -40, 30, 60, 0, 0, 0 } })
	leftPrev = p
	print(string.format("%-11s Left  Shoulder(%4.0f,%4.0f,%4.0f) Elbow(%4.0f,%4.0f,0) Wrist(%4.0f,0,%4.0f)  hand err %.3f",
		name, p[1], p[2], p[3], p[4], p[7], p[5], p[6], err))
end
