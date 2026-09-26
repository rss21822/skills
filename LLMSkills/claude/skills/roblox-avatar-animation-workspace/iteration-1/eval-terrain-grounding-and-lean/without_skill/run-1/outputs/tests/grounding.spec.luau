--[[
	オフライン検証: 手続き接地 + 旋回リーン (Solver)
	実行 (outputs フォルダで):
	  lune run tests/grounding.spec.luau
	リグ寸法は tests/fixtures/rig-r15.json (Studio で計測した既定 R15) を使う。
	地形は解析式 (平地 / 坂 / 横坂 / 階段) で、鉛直レイは式を評価して返す。
	Humanoid は HRP を「床 + HipHeight + HRP半高」に保つ、という前提で HRP を置く。
]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local CFrame, Vector3 = roblox.CFrame, roblox.Vector3

local SRC = "src/ReplicatedStorage/ProceduralGrounding/"
local function loadModule(path: string)
	local fn = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { CFrame = CFrame, Vector3 = Vector3 },
	})
	return fn()
end
local Solver = loadModule(SRC .. "Solver.luau")
local Config = loadModule(SRC .. "Config.luau")

---------------------------------------------------------------------------
-- 小さなテスト枠
---------------------------------------------------------------------------
local failures, passes = 0, 0
local function check(name: string, ok: boolean, detail: string)
	if ok then
		passes += 1
		print(string.format("  PASS  %-58s %s", name, detail))
	else
		failures += 1
		print(string.format("  FAIL  %-58s %s", name, detail))
	end
end
local function f3(x: number): string
	return string.format("%.3f", x)
end

---------------------------------------------------------------------------
-- リグ
---------------------------------------------------------------------------
local rigJson = serde.decode("json", fs.readFile("tests/fixtures/rig-r15.json"))
local JOINTS = { "Root", "Waist", "Neck", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
local SIDES = { "Left", "Right" }

local function cfFrom(t)
	return CFrame.new(table.unpack(t))
end

local function makeRig(scale: number?)
	local s = scale or 1
	local joints = {}
	for _, n in JOINTS do
		local j = rigJson[n]
		local c0, c1 = cfFrom(j.c0), cfFrom(j.c1)
		joints[n] = {
			c0 = CFrame.new(c0.Position * s) * c0.Rotation,
			c1 = CFrame.new(c1.Position * s) * c1.Rotation,
			base = CFrame.new(),
		}
	end
	local function v(t)
		return Vector3.new(t[1], t[2], t[3]) * s
	end
	return {
		joints = joints,
		hipHeight = rigJson._hipHeight * s,
		rootSizeY = rigJson._rootSize[2] * s,
		footSize = { Left = v(rigJson.LeftAnkle.s1), Right = v(rigJson.RightAnkle.s1) },
	}
end

local function legLength(rig)
	local j = rig.joints
	local l1 = (j.LeftHip.c1.Position - j.LeftKnee.c0.Position).Magnitude
	local l2 = (j.LeftKnee.c1.Position - j.LeftAnkle.c0.Position).Magnitude
	return l1 + l2
end

-- 歩幅ポーズ: 左脚を前 a, 右脚を後ろ a に振り、足は水平、Root を下げて平地で両足が着く (アニメが平地前提で作られている状態)
local function setStride(rig, a: number)
	local j = rig.joints
	local drop = legLength(rig) * (1 - math.cos(a))
	j.Root.base = CFrame.new(0, -drop, 0)
	j.LeftHip.base = CFrame.Angles(a, 0, 0)
	j.LeftKnee.base = CFrame.new()
	j.LeftAnkle.base = CFrame.Angles(-a, 0, 0)
	j.RightHip.base = CFrame.Angles(-a, 0, 0)
	j.RightKnee.base = CFrame.new()
	j.RightAnkle.base = CFrame.Angles(a, 0, 0)
end

local function setStanding(rig)
	for _, n in JOINTS do
		rig.joints[n].base = CFrame.new()
	end
end

---------------------------------------------------------------------------
-- 地形 (y = f(x,z), 法線)
---------------------------------------------------------------------------
local UP = Vector3.new(0, 1, 0)
local function flatGround()
	return function(_x, _z)
		return 0, UP
	end
end
local function slopeGround(deg: number, uphill: Vector3)
	local t = math.tan(math.rad(deg))
	local n = Vector3.new(-t * uphill.X, 1, -t * uphill.Z).Unit
	return function(x, z)
		return t * (x * uphill.X + z * uphill.Z), n
	end
end
-- 階段: dir 方向に stepD ごとに stepH 上がる。edge = 最初の段差の位置
local function stairsGround(stepH: number, stepD: number, dir: Vector3, edge: number)
	return function(x, z)
		local s = x * dir.X + z * dir.Z - edge
		return (math.floor(s / stepD) + 1) * stepH, UP
	end
end

local function makeSampler(ground)
	return function(x, z, yTop, yBottom)
		local y, n = ground(x, z)
		if y <= yTop and y >= yBottom then
			return y, n
		end
		return nil, nil
	end
end

-- Humanoid の床: HRP の足元 (2 x 1 の範囲) で一番高い点。坂では中心とほぼ同じ、階段では上の段を拾う
local function humanoidFloor(ground, pos: Vector3, rootCF: CFrame)
	local best = -math.huge
	for _, o in { Vector3.new(0, 0, 0), Vector3.new(0.9, 0, 0), Vector3.new(-0.9, 0, 0), Vector3.new(0, 0, 0.4), Vector3.new(0, 0, -0.4) } do
		local p = pos + rootCF:VectorToWorldSpace(o)
		local y = ground(p.X, p.Z)
		if y > best then
			best = y
		end
	end
	return best
end

local function placeRoot(rig, ground, x: number, z: number, yaw: number, floorFn)
	local rot = CFrame.Angles(0, yaw, 0)
	local floorY = if floorFn then floorFn(ground, Vector3.new(x, 0, z), rot) else (ground(x, z))
	return CFrame.new(x, floorY + rig.hipHeight + rig.rootSizeY * 0.5, z) * rot
end

---------------------------------------------------------------------------
-- FK と計測
---------------------------------------------------------------------------
local function fk(rig, rootCF: CFrame, T)
	local j = rig.joints
	local function t(n)
		return (T and T[n]) or j[n].base
	end
	local parts = {}
	parts.LowerTorso = rootCF * j.Root.c0 * t("Root") * j.Root.c1:Inverse()
	parts.UpperTorso = parts.LowerTorso * j.Waist.c0 * t("Waist") * j.Waist.c1:Inverse()
	parts.Head = parts.UpperTorso * j.Neck.c0 * t("Neck") * j.Neck.c1:Inverse()
	for _, s in SIDES do
		parts[s .. "UpperLeg"] = parts.LowerTorso * j[s .. "Hip"].c0 * t(s .. "Hip") * j[s .. "Hip"].c1:Inverse()
		parts[s .. "LowerLeg"] = parts[s .. "UpperLeg"] * j[s .. "Knee"].c0 * t(s .. "Knee") * j[s .. "Knee"].c1:Inverse()
		parts[s .. "Foot"] = parts[s .. "LowerLeg"] * j[s .. "Ankle"].c0 * t(s .. "Ankle") * j[s .. "Ankle"].c1:Inverse()
	end
	return parts
end

-- 足裏 5 点 (4 隅 + 中心) の地面からの高さ。最小値 < 0 はめり込み、> 0 は浮き
local function footGap(rig, parts, ground, side: string)
	local f = parts[side .. "Foot"]
	local sz = rig.footSize[side]
	local hx, hy, hz = sz.X * 0.5, sz.Y * 0.5, sz.Z * 0.5
	local minGap = math.huge
	for _, o in { Vector3.new(hx, -hy, hz), Vector3.new(-hx, -hy, hz), Vector3.new(hx, -hy, -hz), Vector3.new(-hx, -hy, -hz), Vector3.new(0, -hy, 0) } do
		local p = f * o
		local gy = ground(p.X, p.Z)
		minGap = math.min(minGap, p.Y - gy)
	end
	return minGap
end

local function rollDeg(cf: CFrame, rootCF: CFrame): number
	local up = cf.UpVector
	return math.deg(math.atan2(-up:Dot(rootCF.RightVector), up:Dot(UP)))
end

local function angleBetween(a: CFrame, b: CFrame): number
	local _, ang = (a.Rotation:Inverse() * b.Rotation):ToAxisAngle()
	return math.deg(math.abs(ang))
end

local function newInput(rig, rootCF, ground, extra)
	local input = {
		dt = 1 / 60,
		rootCFrame = rootCF,
		rootSizeY = rig.rootSizeY,
		hipHeight = rig.hipHeight,
		joints = rig.joints,
		footSize = rig.footSize,
		velocity = Vector3.new(0, 0, 0),
		gravity = 196.2,
		grounded = true,
		sample = makeSampler(ground),
	}
	if extra then
		for k, v in extra do
			input[k] = v
		end
	end
	return input
end

-- 静止シーン: 同じ入力で n フレーム回して収束後の結果を返す
local function settle(rig, rootCF, ground, frames: number?, extra)
	local state = Solver.newState()
	local res
	for _ = 1, frames or 60 do
		res = Solver.solve(newInput(rig, rootCF, ground, extra), state, Config)
	end
	return res, state
end

local function contactReport(rig, rootCF, ground, T)
	local parts = fk(rig, rootCF, T)
	return footGap(rig, parts, ground, "Left"), footGap(rig, parts, ground, "Right"), parts
end

local function sceneCase(title: string, rig, rootCF, ground, tol: number)
	local bl, br = contactReport(rig, rootCF, ground, nil)
	local res = settle(rig, rootCF, ground)
	local al, ar = contactReport(rig, rootCF, ground, res.transforms)
	local detail = string.format(
		"before L=%s R=%s | after L=%s R=%s | drop=%s",
		f3(bl), f3(br), f3(al), f3(ar), f3(res.debug.drop)
	)
	check(title, math.abs(al) <= tol and math.abs(ar) <= tol, detail)
	return res, bl, br, al, ar
end

---------------------------------------------------------------------------
print("== 0. リグの整合 (rig-r15.json) ==")
do
	local rig = makeRig()
	local root = placeRoot(rig, flatGround(), 0, 0, 0)
	local l, r = contactReport(rig, root, flatGround(), nil)
	check("rest pose: soles sit exactly on the HipHeight floor", math.abs(l) < 1e-3 and math.abs(r) < 1e-3, "L=" .. f3(l) .. " R=" .. f3(r))
	local len = legLength(rig)
	print(string.format("        leg hip->ankle = %.4f  (thigh %.4f + shin %.4f), hipHeight = %.4f", len,
		(rig.joints.LeftHip.c1.Position - rig.joints.LeftKnee.c0.Position).Magnitude,
		(rig.joints.LeftKnee.c1.Position - rig.joints.LeftAnkle.c0.Position).Magnitude, rig.hipHeight))
end

print("== 1. 平地では素のアニメを一切変えない ==")
do
	for _, pose in { "standing", "stride" } do
		local rig = makeRig()
		if pose == "stride" then
			setStride(rig, math.rad(22))
		end
		local ground = flatGround()
		local root = placeRoot(rig, ground, 3, -2, 0.7)
		local res = settle(rig, root, ground)
		local maxAng, maxPos = 0, 0
		for _, n in JOINTS do
			local t = res.transforms[n]
			if t then
				maxAng = math.max(maxAng, angleBetween(t, rig.joints[n].base))
				maxPos = math.max(maxPos, (t.Position - rig.joints[n].base.Position).Magnitude)
			end
		end
		check("flat " .. pose .. ": transforms == animation", maxAng < 0.05 and maxPos < 1e-3,
			string.format("max joint diff %.4f deg / %.5f stud", maxAng, maxPos))
	end
end

print("== 2. 坂・階段: 足裏の最低点が地面に乗る (tol 0.03 stud) ==")
local sceneRows = {}
do
	local stride = math.rad(22)
	local scenes = {
		{ "uphill 25deg, stride (facing uphill)", function(rig)
			setStride(rig, stride)
			local g = slopeGround(25, Vector3.new(0, 0, -1))
			return g, placeRoot(rig, g, 0, 0, 0)
		end },
		{ "downhill 25deg, stride (facing downhill)", function(rig)
			setStride(rig, stride)
			local g = slopeGround(25, Vector3.new(0, 0, 1))
			return g, placeRoot(rig, g, 0, 0, 0)
		end },
		{ "side slope 20deg, standing (slope rises to the left)", function(rig)
			setStanding(rig)
			local g = slopeGround(20, Vector3.new(-1, 0, 0))
			return g, placeRoot(rig, g, 0, 0, 0)
		end },
		{ "uphill 35deg, standing", function(rig)
			setStanding(rig)
			local g = slopeGround(35, Vector3.new(0, 0, -1))
			return g, placeRoot(rig, g, 0, 0, 0)
		end },
		{ "stairs 0.8 high, standing sideways across the edge", function(rig)
			setStanding(rig)
			-- 段差の縁が x=0 (体の中心)。右 (+x) が上の段
			local g = stairsGround(0.8, 4, Vector3.new(1, 0, 0), 0)
			return g, placeRoot(rig, g, 0, 0, 0, humanoidFloor)
		end },
		{ "stairs 0.6/1.2, stride facing up (front foot on upper step)", function(rig)
			setStride(rig, stride)
			local g = stairsGround(0.6, 1.2, Vector3.new(0, 0, -1), 0.3)
			return g, placeRoot(rig, g, 0, 0, 0, humanoidFloor)
		end },
		{ "stairs 0.6/1.2, stride facing down", function(rig)
			setStride(rig, stride)
			local g = stairsGround(0.6, 1.2, Vector3.new(0, 0, 1), -0.3)
			return g, placeRoot(rig, g, 0, 0, 0, humanoidFloor)
		end },
	}
	for _, sc in scenes do
		local rig = makeRig()
		local g, root = sc[2](rig)
		local res, bl, br, al, ar = sceneCase(sc[1], rig, root, g, 0.03)
		table.insert(sceneRows, { sc[1], bl, br, al, ar, res.debug.drop })
	end
end

print("== 3. 膝は必ず前に曲がる (逆関節にならない) ==")
do
	local rig = makeRig()
	setStride(rig, math.rad(22))
	local g = slopeGround(25, Vector3.new(0, 0, -1))
	local root = placeRoot(rig, g, 0, 0, 0)
	local res = settle(rig, root, g)
	local parts = fk(rig, root, res.transforms)
	for _, s in SIDES do
		local hip = parts.LowerTorso * rig.joints[s .. "Hip"].c0.Position
		local knee = parts[s .. "UpperLeg"] * rig.joints[s .. "Knee"].c0.Position
		local ankle = parts[s .. "LowerLeg"] * rig.joints[s .. "Ankle"].c0.Position
		local du = (ankle - hip).Unit
		local off = (knee - hip) - du * (knee - hip):Dot(du)
		local fwd = off:Dot(root.LookVector)
		check("uphill knee bends forward (" .. s .. ")", fwd >= -1e-3, "knee offset along facing = " .. f3(fwd))
	end
end

print("== 4. 旋回リーン ==")
local leanRows = {}
local function runTurn(speed: number, yawRate: number, seconds: number, ground, rigScale: number?)
	local rig = makeRig(rigScale)
	setStanding(rig)
	local state = Solver.newState()
	local yaw, pos = 0, Vector3.new(0, 0, 0)
	local dt = 1 / 60
	local res, root
	for _ = 1, math.floor(seconds / dt) do
		yaw += yawRate * dt
		root = placeRoot(rig, ground, pos.X, pos.Z, yaw)
		local look = root.LookVector
		res = Solver.solve(newInput(rig, root, ground, { velocity = look * speed, dt = dt }), state, Config)
		pos += look * speed * dt
	end
	local parts = fk(rig, root, res.transforms)
	local l, r = footGap(rig, parts, ground, "Left"), footGap(rig, parts, ground, "Right")
	return {
		body = math.deg(res.debug.lean),
		torso = rollDeg(parts.UpperTorso, root),
		head = rollDeg(parts.Head, root),
		lowerTorso = rollDeg(parts.LowerTorso, root),
		gapL = l,
		gapR = r,
		drop = res.debug.drop,
	}
end
do
	local ground = flatGround()
	local expected = math.deg(math.atan(16 * 3 / 196.2))
	local left = runTurn(16, 3, 1.5, ground)
	check("run 16 st/s, left turn 3 rad/s -> leans LEFT (into turn)", left.torso > 5,
		string.format("body %.2f deg (physics atan(v*w/g)=%.2f), UpperTorso %.2f, Head %.2f", left.body, expected, left.torso, left.head))
	check("  body lean ~= atan(v*w/g) at gain 1.0", math.abs(left.body - expected) < 0.5, string.format("%.2f vs %.2f", left.body, expected))
	check("  head stays more level than torso", math.abs(left.head) < math.abs(left.torso) * 0.6, string.format("head %.2f / torso %.2f", left.head, left.torso))
	check("  feet stay planted while leaning (tol 0.03)", math.abs(left.gapL) < 0.03 and math.abs(left.gapR) < 0.03,
		string.format("L=%s R=%s drop=%s", f3(left.gapL), f3(left.gapR), f3(left.drop)))
	local right = runTurn(16, -3, 1.5, ground)
	check("run 16 st/s, right turn -> leans RIGHT (mirror)", math.abs(right.torso + left.torso) < 0.05,
		string.format("UpperTorso %.2f vs left %.2f", right.torso, left.torso))
	local sharp = runTurn(16, 9, 1.0, ground)
	check("sharp turn clamps at maxLean (18 deg)", sharp.body <= 18.01 and sharp.body > 17,
		string.format("body %.2f deg, UpperTorso %.2f", sharp.body, sharp.torso))
	local inPlace = runTurn(0, 3, 1.0, ground)
	check("turning in place (speed 0) does not lean", math.abs(inPlace.torso) < 0.01, string.format("UpperTorso %.3f deg", inPlace.torso))
	local walk = runTurn(6, 3, 1.0, ground)
	table.insert(leanRows, { "walk 6 st/s, 3 rad/s", walk })
	table.insert(leanRows, { "run 16 st/s, 3 rad/s", left })
	table.insert(leanRows, { "run 16 st/s, 9 rad/s", sharp })
	table.insert(leanRows, { "in place, 3 rad/s", inPlace })
	-- 立ち上がりの滑らかさ: 直進 -> 急旋回へ切り替えた瞬間から 1 フレームあたりの傾き変化
	local rig = makeRig()
	local state = Solver.newState()
	local yaw, maxStep, prev = 0, 0, 0
	local t90 = nil
	for i = 1, 90 do
		local rate = if i > 10 then 9 else 0
		yaw += rate / 60
		local root = placeRoot(rig, ground, 0, 0, yaw)
		local res = Solver.solve(newInput(rig, root, ground, { velocity = root.LookVector * 16 }), state, Config)
		local d = math.deg(res.debug.lean)
		maxStep = math.max(maxStep, math.abs(d - prev))
		prev = d
		if t90 == nil and d >= 0.9 * 18 then
			t90 = (i - 10) / 60
		end
	end
	check("lean onset is smooth (max change per 60fps frame < 2 deg)", maxStep < 2,
		string.format("max %.2f deg/frame, 90%% reached after %.3f s", maxStep, t90 or -1))
end

print("== 5. 空中では素のアニメに戻る ==")
do
	local rig = makeRig()
	setStride(rig, math.rad(22))
	local g = stairsGround(0.6, 1.2, Vector3.new(0, 0, -1), 0.3)
	local root = placeRoot(rig, g, 0, 0, 0, humanoidFloor)
	local state = Solver.newState()
	for _ = 1, 30 do
		Solver.solve(newInput(rig, root, g), state, Config)
	end
	local res
	local framesTo = nil
	for i = 1, 60 do
		res = Solver.solve(newInput(rig, root, g, { grounded = false }), state, Config)
		if framesTo == nil and res.debug.weight == 0 then
			framesTo = i
		end
	end
	local maxAng = 0
	for _, n in JOINTS do
		if res.transforms[n] then
			maxAng = math.max(maxAng, angleBetween(res.transforms[n], rig.joints[n].base))
		end
	end
	check("airborne -> weight 0 and pose == animation", res.debug.weight == 0 and maxAng < 0.05,
		string.format("weight 0 after %s frames, max joint diff %.4f deg", tostring(framesTo), maxAng))
end

print("== 6. 段差で HRP が跳ね上がっても骨盤・足がワープしない ==")
do
	local rig = makeRig()
	setStanding(rig)
	local g = stairsGround(0.8, 4, Vector3.new(1, 0, 0), 0)
	local state = Solver.newState()
	-- 最初は Humanoid が下の段に居る (HRP 低い) -> 上の段の足は曲げて持ち上げる
	local lowRoot = CFrame.new(0, 0 + rig.hipHeight + rig.rootSizeY * 0.5, 0)
	local highRoot = CFrame.new(0, 0.8 + rig.hipHeight + rig.rootSizeY * 0.5, 0)
	local before
	for _ = 1, 40 do
		before = Solver.solve(newInput(rig, lowRoot, g), state, Config)
	end
	local pb = fk(rig, lowRoot, before.transforms)
	local after = Solver.solve(newInput(rig, highRoot, g), state, Config)
	local pa = fk(rig, highRoot, after.transforms)
	local dPelvis = pa.LowerTorso.Position.Y - pb.LowerTorso.Position.Y
	local dL = (pa.LeftFoot.Position - pb.LeftFoot.Position).Magnitude
	local dR = (pa.RightFoot.Position - pb.RightFoot.Position).Magnitude
	check("HRP pops +0.8: pelvis world Y jump", math.abs(dPelvis) < 0.02, "Δpelvis = " .. f3(dPelvis) .. " (HRP moved 0.800)")
	check("HRP pops +0.8: planted feet do not move", dL < 0.02 and dR < 0.02, "ΔL = " .. f3(dL) .. "  ΔR = " .. f3(dR))
end

print("== 7. 階段を連続で登る歩行 (合成歩行, 60fps, 3 秒) ==")
local walkRows = {}
local function walkStairs(useLayer: boolean, stepH: number, stepD: number, dirSign: number)
	local rig = makeRig()
	-- 階段は常に -Z 方向へ上る。dirSign=1: -Z へ進んで上る / -1: z=-24 から +Z へ進んで下る
	local g = stairsGround(stepH, stepD, Vector3.new(0, 0, -1), 0.3)
	local state = Solver.newState()
	local speed, dt = 8, 1 / 60
	local gaps = {}
	local maxPelvisStep, maxJointStep = 0, 0
	local prevPelvis, prevT = nil, nil
	for i = 1, 180 do
		local z = if dirSign > 0 then -speed * dt * i else -24 + speed * dt * i
		local phase = (speed * dt * i) / 3.0
		setStride(rig, math.rad(22) * math.sin(phase * 2 * math.pi))
		local root = placeRoot(rig, g, 0, z, if dirSign > 0 then 0 else math.pi, humanoidFloor)
		local T = nil
		if useLayer then
			T = Solver.solve(newInput(rig, root, g, { velocity = root.LookVector * speed }), state, Config).transforms
		end
		local parts = fk(rig, root, T)
		for _, s in SIDES do
			table.insert(gaps, math.abs(footGap(rig, parts, g, s)))
		end
		local py = parts.LowerTorso.Position.Y
		if prevPelvis then
			maxPelvisStep = math.max(maxPelvisStep, math.abs(py - prevPelvis))
		end
		prevPelvis = py
		if T and prevT then
			for _, n in { "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" } do
				maxJointStep = math.max(maxJointStep, angleBetween(T[n], prevT[n]))
			end
		end
		prevT = T
	end
	table.sort(gaps)
	local p50 = gaps[math.floor(#gaps * 0.5)]
	local p95 = gaps[math.floor(#gaps * 0.95)]
	local mx = gaps[#gaps]
	return { p50 = p50, p95 = p95, max = mx, pelvisStep = maxPelvisStep, jointStep = maxJointStep }
end
do
	for _, cfgRow in { { "up 0.6/1.2", 0.6, 1.2, 1 }, { "down 0.6/1.2", 0.6, 1.2, -1 } } do
		local base = walkStairs(false, cfgRow[2], cfgRow[3], cfgRow[4])
		local lay = walkStairs(true, cfgRow[2], cfgRow[3], cfgRow[4])
		table.insert(walkRows, { cfgRow[1], base, lay })
		check("stairs " .. cfgRow[1] .. ": median |sole gap| <= 0.03", lay.p50 <= 0.03,
			string.format("before p50=%s p95=%s max=%s | after p50=%s p95=%s max=%s", f3(base.p50), f3(base.p95), f3(base.max), f3(lay.p50), f3(lay.p95), f3(lay.max)))
		check("stairs " .. cfgRow[1] .. ": pelvis never jumps more than raw HRP", lay.pelvisStep <= base.pelvisStep + 1e-3,
			string.format("max pelvis Δ/frame before %s after %s ; max leg joint Δ/frame %.2f deg", f3(base.pelvisStep), f3(lay.pelvisStep), lay.jointStep))
	end
end

print("== 8. 体格違い (全身 1.3 倍) でも同じ結果 (寸法は実機の C0/C1 から読む) ==")
do
	local rig = makeRig(1.3)
	setStride(rig, math.rad(22))
	local g = slopeGround(25, Vector3.new(0, 0, -1))
	sceneCase("scale 1.3, uphill 25deg stride", rig, placeRoot(rig, g, 0, 0, 0), g, 0.03)
	local rig2 = makeRig(0.8)
	local g2 = stairsGround(0.8, 4, Vector3.new(1, 0, 0), 0)
	sceneCase("scale 0.8, stairs sideways 0.8", rig2, placeRoot(rig2, g2, 0, 0, 0, humanoidFloor), g2, 0.03)
end

print("== 9. Animator が書かなかった関節で補正が累積しない (resolveBase) ==")
do
	local anim = CFrame.Angles(0.3, 0, 0)
	local written = anim * CFrame.Angles(0, 0, 0.2)
	check("animator wrote new value -> use it", Solver.resolveBase(anim, written, anim) == anim, "")
	check("value is our own last write -> reuse last base", Solver.resolveBase(written, written, anim) == anim, "")
	-- 10 フレーム Animator が触らない関節に同じ補正を掛け続けても、書く値は一定
	local motor = anim
	local lastW, lastB = nil, nil
	local mod = CFrame.Angles(0, 0, 0.2)
	for _ = 1, 10 do
		local base = Solver.resolveBase(motor, lastW, lastB)
		local out = base * mod
		motor, lastW, lastB = out, out, base
	end
	check("10 untouched frames: no accumulation", angleBetween(motor, anim * mod) < 1e-3, string.format("%.5f deg", angleBetween(motor, anim * mod)))
end

---------------------------------------------------------------------------
print("")
print("== 数値まとめ ==")
print("scene                                                  | before L / R (stud) | after L / R (stud) | pelvis drop")
for _, r in sceneRows do
	print(string.format("%-54s | %7s / %7s   | %7s / %7s  | %s", r[1], f3(r[2]), f3(r[3]), f3(r[4]), f3(r[5]), f3(r[6])))
end
print("")
print("turn                 | body lean | UpperTorso roll | Head roll | feet gap L / R")
for _, r in leanRows do
	local x = r[2]
	print(string.format("%-20s | %7.2f   | %7.2f         | %7.2f   | %s / %s", r[1], x.body, x.torso, x.head, f3(x.gapL), f3(x.gapR)))
end
print("")
print("stairs walk (|sole gap| stud)  | before p50 / p95 / max  | after p50 / p95 / max | pelvis Δ/frame before / after | leg joint Δ/frame")
for _, r in walkRows do
	print(string.format("%-30s | %s / %s / %s   | %s / %s / %s | %s / %s | %.2f deg", r[1], f3(r[2].p50), f3(r[2].p95), f3(r[2].max),
		f3(r[3].p50), f3(r[3].p95), f3(r[3].max), f3(r[2].pelvisStep), f3(r[3].pelvisStep), r[3].jointStep))
end
print("")
print(string.format("RESULT: %d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
