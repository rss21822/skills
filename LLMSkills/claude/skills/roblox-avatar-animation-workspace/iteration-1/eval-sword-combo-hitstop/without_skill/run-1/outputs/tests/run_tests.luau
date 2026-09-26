-- Lune 0.10.5 オフライン計測テスト:  outputs/ をカレントにして  lune run tests/run_tests.luau
-- rig-r15.json の FK で 240 Hz サンプリングし、剣の軌跡・速度・ヒットストップ・連続性・接地を実測する。
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local luau = require("@lune/luau")
local process = require("@lune/process")

getfenv(0).CFrame = roblox.CFrame
getfenv(0).Vector3 = roblox.Vector3

local RIG_PATH = process.env.RIG_JSON or "C:/Users/ryufu/.claude/skills/roblox-avatar-animation/evals/files/rig-r15.json"
local function load(path: string)
	return luau.load(fs.readFile(path), { chunkName = path, injectGlobals = true, environment = getfenv(0) })()
end
local PM = load("src/SwordCombo/PoseMath.luau")
local Data = load("src/SwordCombo/ComboData.luau")
local ComboPlayer = load("src/SwordCombo/ComboPlayer.luau")

local raw = serde.decode("json", fs.readFile(RIG_PATH))
local rig = {}
for k, v in raw do
	if type(v) == "table" and v.c0 then
		rig[k] = { p0 = v.p0, p1 = v.p1, C0 = CFrame.new(table.unpack(v.c0)), C1 = CFrame.new(table.unpack(v.c1)), s1 = v.s1 }
	end
end
local GROUND_Y = -(raw._hipHeight + raw._rootSize[2] / 2)

local failures, passes = 0, 0
local function check(name: string, ok: boolean, detail: string)
	if ok then
		passes += 1
		print(string.format("PASS  %-46s %s", name, detail))
	else
		failures += 1
		print(string.format("FAIL  %-46s %s", name, detail))
	end
end
local function fmt(v: Vector3) return string.format("(%.2f, %.2f, %.2f)", v.X, v.Y, v.Z) end

local GRIP = Vector3.new(table.unpack(Data.GRIP_OFFSET))
local L = Data.BLADE_LENGTH
local restTargets = PM.legRestTargets(rig)

-- 姿勢 → 全身 FK（脚は IK）
local lastPsi: number? = nil
local function evalPose(pose, shakeDeg: number?, lh: number?)
	local T = {}
	for j, cf in pose do T[j] = cf end
	if shakeDeg and shakeDeg ~= 0 then
		T.RightShoulder = T.RightShoulder * CFrame.Angles(math.rad(shakeDeg), 0, math.rad(shakeDeg * 0.5))
	end
	-- SwordComboLayer と同じ: 両手持ち区間は左腕を実行時 IK で柄へ（lh で FK と混ぜる）
	if lh and lh > 0 then
		local ik, _, psi = PM.solveLeftOnHilt(rig, T, GRIP, Data.POMMEL_BACK, lastPsi)
		lastPsi = psi
		for j, cf in ik do T[j] = T[j]:Lerp(cf, lh) end
	else
		lastPsi = nil
	end
	local legs, legErr = PM.solveLegs(rig, T.Root or CFrame.new(), restTargets)
	for j, cf in legs do T[j] = cf end
	local parts = PM.forwardKinematics(rig, T)
	local hand = parts.RightHand
	local grip = hand:PointToWorldSpace(GRIP)
	local dir = hand:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local lgrip = parts.LeftHand:PointToWorldSpace(GRIP)
	return { T = T, parts = parts, grip = grip, dir = dir, tip = grip + dir * L, lgrip = lgrip, legErr = legErr }
end

-- ───────── 0. 構文ゲート（Roblox 専用モジュールも Luau としてコンパイルできるか） ─────────
do
	local files = {
		"src/SwordCombo/PoseMath.luau", "src/SwordCombo/ComboData.luau", "src/SwordCombo/ComboPlayer.luau",
		"src/SwordCombo/SwordComboLayer.luau", "src/SwordCombo/KeyframeSequenceExport.luau",
		"src/client/SwordComboClient.client.luau",
	}
	local bad = {}
	for _, f in files do
		local ok, err = pcall(luau.compile, fs.readFile(f))
		if not ok then table.insert(bad, f .. ": " .. tostring(err)) end
	end
	check("syntax: all src files compile", #bad == 0, #bad == 0 and string.format("%d files", #files) or table.concat(bad, " | "))
end

-- ───────── 1. FK 正当性 ─────────
do
	local parts = PM.forwardKinematics(rig, {})
	local footBottom = parts.RightFoot.Position.Y - rig.RightAnkle.s1[2] / 2
	check("FK: rest foot bottom == ground", math.abs(footBottom - GROUND_Y) < 0.002, string.format("footBottom=%.4f ground=%.4f", footBottom, GROUND_Y))
end

-- ───────── 2. キー間の回転差（Slerp 安全域） ─────────
do
	local worst, where = 0, ""
	for _, s in Data.STRIKES do
		local prev = nil
		for _, k in s.keys do
			if k.pose ~= "FROM_CURRENT" then
				if prev then
					for _, j in Data.JOINTS do
						local d = PM.angleBetween(PM.keyToCFrame(prev.pose[j]), PM.keyToCFrame(k.pose[j]))
						if d > worst then worst, where = d, string.format("%s %s t=%.3f", s.name, j, k.t) end
					end
				end
				prev = k
			end
		end
	end
	check("keys: adjacent rotation delta < 170 deg", worst < 170, string.format("max=%.1f deg at %s", worst, where))
end

-- ───────── 3. フルコンボをシミュレート（240 Hz、各段の chainAt 直前に次入力） ─────────
local DT = 1 / 240
local function simulate(opts)
	local p = ComboPlayer.new(Data, PM, { hitShake = opts.shake })
	local readyPose = {}
	for _, j in Data.JOINTS do readyPose[j] = PM.keyToCFrame(Data.READY[j]) end
	p:press(readyPose)
	local frames = {}
	local wall = 0
	local pressedFor = { [1] = false, [2] = false }
	-- ダミー標的（前方 4 stud・高さは胴体帯）。叩きつけは地面でヒット。
	local target = { center = Vector3.new(0.3, 0.0, -4.2), half = Vector3.new(1.0, 2.6, 0.6) }
	local function inBox(pt: Vector3)
		local d = pt - target.center
		return math.abs(d.X) <= target.half.X and math.abs(d.Y) <= target.half.Y and math.abs(d.Z) <= target.half.Z
	end
	while wall < 4 do
		-- 入力: 各段で t=0.25 に次の入力（先行入力）
		if p.index >= 1 and p.index <= 2 and not pressedFor[p.index] and p.t >= 0.25 and opts.chain then
			pressedFor[p.index] = true
			p:press()
		end
		local pose, lh, w, shake = p:sample()
		if not pose then break end
		local e = evalPose(pose, shake, lh)
		-- 当たり判定
		if opts.hits and p:isActive() then
			local s = p:strike()
			local hit = false
			for i = 3, 10 do
				local pt = e.grip + e.dir * (L * i / 10)
				if inBox(pt) then hit = true end
			end
			if s.groundImpact and e.tip.Y <= GROUND_Y + 0.08 then hit = true end
			if hit then p:registerHit() end
		end
		table.insert(frames, { wall = wall, index = p.index, t = p.t, hs = p:isHitStopped(), w = w, lh = lh, e = e, pose = pose, shake = shake })
		p:step(DT)
		wall += DT
	end
	return frames, p
end

local frames, player = simulate({ chain = true, hits = true, shake = false })
local events = player:popEvents()
local hitEvents = {}
for _, ev in events do
	if ev.kind == "hit" then table.insert(hitEvents, ev) end
end
check("combo: 3 strikes chained + 3 hits", #hitEvents == 3, string.format("hits=%d (%s)", #hitEvents, (function()
	local s = {}
	for _, h in hitEvents do table.insert(s, string.format("#%d@t=%.3f", h.index, h.t)) end
	return table.concat(s, ", ")
end)()))
for _, h in hitEvents do
	local s = Data.STRIKES[h.index]
	check(string.format("hit %d near authored hitTime", h.index), math.abs(h.t - s.hitTime) <= 0.045, string.format("measured t=%.3f authored=%.3f", h.t, s.hitTime))
end

-- 段ごとの切り出し
local function framesOf(index: number)
	local out = {}
	for _, f in frames do
		if f.index == index then table.insert(out, f) end
	end
	return out
end
local function at(fs_, t: number)
	local best, bd = nil, math.huge
	for _, f in fs_ do
		if not f.hs and math.abs(f.t - t) < bd then best, bd = f, math.abs(f.t - t) end
	end
	return best
end
local function bladePt(f, frac: number) return f.e.grip + f.e.dir * (L * frac) end

-- ───────── 4. 軌跡の形 ─────────
do
	local f1 = framesOf(1)
	local a, b = at(f1, 0.24), at(f1, 0.34)
	local d = bladePt(b, 0.6) - bladePt(a, 0.6)
	local wind = at(f1, 0.20)
	check("strike1 kesa: windup grip upper-right", wind.e.grip.X > 0.6 and wind.e.grip.Y > 1.2, "grip@0.20=" .. fmt(wind.e.grip))
	check("strike1 kesa: blade moves down-left diagonally", d.X < -0.8 and d.Y < -0.8 and math.abs(d.Y / d.X) > 0.4 and math.abs(d.Y / d.X) < 2.5,
		string.format("blade60%% disp 0.24→0.34 = %s  |dy/dx|=%.2f", fmt(d), math.abs(d.Y / d.X)))
	local fend = at(f1, 0.34)
	check("strike1 kesa: follow-through ends low-left", fend.e.grip.X < 0 and fend.e.grip.Y < -0.5, "grip@0.34=" .. fmt(fend.e.grip))
end
do
	local f2 = framesOf(2)
	local a, b = at(f2, 0.19), at(f2, 0.36)
	local pa, pb = bladePt(a, 0.6), bladePt(b, 0.6)
	local d = pb - pa
	-- 振りの途中（0.21〜0.30）での刃の 60% 点の高さの幅
	local ymin, ymax = math.huge, -math.huge
	for _, f in f2 do
		if f.t >= 0.21 and f.t <= 0.30 and not f.hs then
			local y = bladePt(f, 0.6).Y
			ymin, ymax = math.min(ymin, y), math.max(ymax, y)
		end
	end
	check("strike2 yokonagi: blade moves left→right", d.X > 1.5, string.format("blade60%% disp 0.19→0.36 = %s", fmt(d)))
	local incl = math.deg(math.atan((ymax - ymin) / math.max(math.abs(d.X), 1e-6)))
	check("strike2 yokonagi: path inclination < 12 deg", incl < 12 and ymin > -1.2 and ymax < 1.2, string.format("blade60%% Y range in 0.21–0.30 = [%.2f, %.2f] over dx=%.2f → %.1f deg", ymin, ymax, d.X, incl))
end
do
	local f3 = framesOf(3)
	local top = at(f3, 0.40)
	local hit = at(f3, 0.49)
	check("strike3 slam: windup tip above head", top.e.tip.Y > 2.4 and top.e.grip.Y > 1.6, string.format("tip@0.40=%s grip=%s (head top≈1.93)", fmt(top.e.tip), fmt(top.e.grip)))
	check("strike3 slam: tip reaches ground in front", hit.e.tip.Y <= GROUND_Y + 0.15 and hit.e.tip.Z < -3, string.format("tip@0.49=%s ground=%.2f", fmt(hit.e.tip), GROUND_Y))
	check("strike3 slam: tip not buried (>0.25 below ground)", hit.e.tip.Y > GROUND_Y - 0.25, string.format("tipY=%.3f", hit.e.tip.Y))
end

-- ───────── 5. 重さ: 速度プロファイル ─────────
local phaseWin = {
	{ wind = { 0.02, 0.15 }, hold = { 0.16, 0.20 }, swing = { 0.22, 0.30 } },
	{ wind = { 0.02, 0.14 }, hold = { 0.15, 0.19 }, swing = { 0.20, 0.28 } },
	{ wind = { 0.02, 0.32 }, hold = { 0.35, 0.40 }, swing = { 0.43, 0.50 } },
}
for i = 1, 3 do
	local fi = framesOf(i)
	local maxIn = function(win)
		local m, prev = 0, nil
		for _, f in fi do
			if not f.hs then
				if prev and f.t >= win[1] and f.t <= win[2] and f.t > prev.t then
					local v = (f.e.tip - prev.e.tip).Magnitude / (f.t - prev.t)
					m = math.max(m, v)
				end
				prev = f
			end
		end
		return m
	end
	local vw, vh, vs = maxIn(phaseWin[i].wind), maxIn(phaseWin[i].hold), maxIn(phaseWin[i].swing)
	check(string.format("strike%d weight: swing peak >= 2.5x windup peak", i), vs >= 2.5 * vw, string.format("tip speed peak windup=%.1f hold=%.1f swing=%.1f stud/s (x%.1f)", vw, vh, vs, vs / math.max(vw, 1e-6)))
	check(string.format("strike%d weight: hold (溜め) slow", i), vh <= 0.35 * vs, string.format("hold/swing=%.2f", vh / math.max(vs, 1e-6)))
end

-- ───────── 6. ヒットストップ: 静止・長さ・壁時計の延長 ─────────
do
	for _, h in hitEvents do
		local s = Data.STRIKES[h.index]
		local hsFrames = {}
		for _, f in frames do
			if f.index == h.index and f.hs then table.insert(hsFrames, f) end
		end
		local maxDelta = 0
		for k = 2, #hsFrames do
			for _, j in Data.JOINTS do
				maxDelta = math.max(maxDelta, PM.angleBetween(hsFrames[k].pose[j], hsFrames[k - 1].pose[j]))
			end
		end
		local dur = #hsFrames * DT
		check(string.format("hitstop %d: frozen pose", h.index), maxDelta < 1e-3, string.format("max joint delta during stop=%.5f deg over %d frames", maxDelta, #hsFrames))
		check(string.format("hitstop %d: duration", h.index), math.abs(dur - s.hitStop) <= DT + 1e-9, string.format("measured=%.4f s authored=%.3f s", dur, s.hitStop))
	end
	-- 壁時計: ヒットありのコンボ長 − ヒットなし = ヒットストップ合計
	local framesNoHit = simulate({ chain = true, hits = false, shake = false })
	local lenHit, lenNo = #frames * DT, #framesNoHit * DT
	local sumHS = Data.STRIKES[1].hitStop + Data.STRIKES[2].hitStop + Data.STRIKES[3].hitStop
	check("hitstop: combo wall time extended exactly", math.abs((lenHit - lenNo) - sumHS) <= 2 * DT, string.format("with hits=%.3f s, whiff=%.3f s, diff=%.3f (sum hitStop=%.3f)", lenHit, lenNo, lenHit - lenNo, sumHS))
	-- 微振動あり版: 振幅の上限
	local fShake = simulate({ chain = true, hits = true, shake = true })
	local maxShake = 0
	for _, f in fShake do maxShake = math.max(maxShake, math.abs(f.shake)) end
	check("hitstop shake bounded", maxShake > 0.1 and maxShake <= 1.2 + 1e-6, string.format("max shake=%.2f deg", maxShake))
end

-- ───────── 7. 連続性（関節が跳ばない）: 段の切り替わり含む ─────────
do
	local worstJump, where = 0, ""
	local peakVel = {}
	for k = 2, #frames do
		local a, b = frames[k - 1], frames[k]
		for _, j in Data.JOINTS do
			local d = PM.angleBetween(a.pose[j], b.pose[j])
			local vel = d / DT
			peakVel[j] = math.max(peakVel[j] or 0, vel)
			if d > worstJump then worstJump, where = d, string.format("%s wall=%.3f idx %d→%d", j, b.wall, a.index, b.index) end
		end
	end
	-- 「跳び」= 前後のサンプルより突出した 1 サンプルの変化（速い振り自体は跳びではない）
	local spikes, spikeWhere = 0, ""
	for k = 3, #frames - 1 do
		for _, j in Data.JOINTS do
			local dPrev = PM.angleBetween(frames[k - 2].pose[j], frames[k - 1].pose[j])
			local d = PM.angleBetween(frames[k - 1].pose[j], frames[k].pose[j])
			local dNext = PM.angleBetween(frames[k].pose[j], frames[k + 1].pose[j])
			if d > 3 * math.max(dPrev, dNext) + 2 then
				spikes += 1
				if spikeWhere == "" then spikeWhere = string.format("%s wall=%.3f", j, frames[k].wall) end
			end
		end
	end
	-- 実行時 IK の出力（左腕・脚）も同じ基準で
	local ikSpikes, ikWhere, ikMax = 0, "", 0
	local IKJ = { "LeftShoulder", "LeftElbow", "LeftWrist", "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle" }
	for k = 3, #frames - 1 do
		for _, j in IKJ do
			local dPrev = PM.angleBetween(frames[k - 2].e.T[j], frames[k - 1].e.T[j])
			local d = PM.angleBetween(frames[k - 1].e.T[j], frames[k].e.T[j])
			local dNext = PM.angleBetween(frames[k].e.T[j], frames[k + 1].e.T[j])
			ikMax = math.max(ikMax, d)
			if d > 3 * math.max(dPrev, dNext) + 2 then
				ikSpikes += 1
				if ikWhere == "" then ikWhere = string.format("%s wall=%.3f d=%.1f", j, frames[k].wall, d) end
			end
		end
	end
	check("continuity: runtime IK output (left arm, legs) no pops", ikSpikes == 0, string.format("spikes=%d %s; max change=%.2f deg/sample", ikSpikes, ikWhere, ikMax))
	check("continuity: no single-sample spikes (pops)", spikes == 0, string.format("spikes=%d %s; max change=%.2f deg/sample @240Hz (= %.1f deg per 60fps frame) at %s", spikes, spikeWhere, worstJump, worstJump * 4, where))
	local parts = {}
	for _, j in Data.JOINTS do table.insert(parts, string.format("%s=%.0f", j, peakVel[j])) end
	print("      peak angular velocity deg/s: " .. table.concat(parts, " "))
	-- 段切り替えの瞬間
	for k = 2, #frames do
		local a, b = frames[k - 1], frames[k]
		if a.index ~= b.index and a.index ~= 0 and b.index ~= 0 then
			local m = 0
			for _, j in Data.JOINTS do m = math.max(m, PM.angleBetween(a.pose[j], b.pose[j])) end
			check(string.format("chain %d→%d seamless", a.index, b.index), m < 1.5, string.format("max joint delta at switch=%.3f deg", m))
		end
	end
end

-- ───────── 8. 剣が体・頭を貫通しない ─────────
do
	local function insideOBB(cf: CFrame, size: Vector3, p: Vector3, pad: number)
		local l = cf:PointToObjectSpace(p)
		return math.abs(l.X) < size.X / 2 + pad and math.abs(l.Y) < size.Y / 2 + pad and math.abs(l.Z) < size.Z / 2 + pad
	end
	local bad, where = 0, ""
	local minHead = math.huge
	for _, f in frames do
		local parts = f.e.parts
		for i = 2, 10 do
			local pt = f.e.grip + f.e.dir * (L * i / 10)
			local head = (pt - parts.Head.Position).Magnitude
			minHead = math.min(minHead, head)
			if head < 0.62 or insideOBB(parts.UpperTorso, Vector3.new(table.unpack(rig.Waist.s1)), pt, 0.0)
				or insideOBB(parts.LowerTorso, Vector3.new(table.unpack(rig.Root.s1)), pt, 0.0) then
				bad += 1
				if where == "" then where = string.format("idx %d t=%.3f blade %d0%%", f.index, f.t, i) end
			end
		end
	end
	check("blade never passes through head/torso", bad == 0, string.format("penetrating samples=%d %s; min blade-head dist=%.2f", bad, where, minHead))
end

-- ───────── 9. 両手持ち（3 撃目） ─────────
do
	local worst, worstKey = 0, 0
	for _, f in framesOf(3) do
		if f.lh >= 0.999 then
			local want = f.e.grip - f.e.dir * Data.POMMEL_BACK
			local d = (f.e.lgrip - want).Magnitude
			worst = math.max(worst, d)
		end
	end
	for _, k in Data.STRIKES[3].keys do
		if k.pose ~= "FROM_CURRENT" and k.lhIK == 1 then
			local T = {}
			for _, j in Data.JOINTS do T[j] = PM.keyToCFrame(k.pose[j]) end
			local e = evalPose(T)
			worstKey = math.max(worstKey, (e.lgrip - (e.grip - e.dir * Data.POMMEL_BACK)).Magnitude)
		end
	end
	check("strike3 left hand on hilt at keys", worstKey < 0.12, string.format("max key error=%.3f stud", worstKey))
	check("strike3 left hand on hilt every frame (runtime IK)", worst < 0.05, string.format("max drift over all two-handed frames=%.3f stud", worst))
end

-- ───────── 10. 脚（接地） ─────────
do
	local worstErr, minBottom, maxKnee = 0, math.huge, 0
	for _, f in frames do
		worstErr = math.max(worstErr, f.e.legErr)
		for _, side in { "Right", "Left" } do
			local foot = f.e.parts[side .. "Foot"]
			-- 足裏 4 隅の最下点
			local sz = Vector3.new(table.unpack(rig[side .. "Ankle"].s1))
			for _, sx in { -1, 1 } do
				for _, sz2 in { -1, 1 } do
					local c = foot:PointToWorldSpace(Vector3.new(sx * sz.X / 2, -sz.Y / 2, sz2 * sz.Z / 2))
					minBottom = math.min(minBottom, c.Y)
				end
			end
			local kx = select(1, f.e.T[side .. "Knee"]:ToEulerAnglesXYZ())
			maxKnee = math.max(maxKnee, -math.deg(kx))
		end
	end
	check("legs: ankles stay planted (IK error)", worstErr < 0.01, string.format("max ankle error=%.4f stud", worstErr))
	check("legs: sole never below ground", minBottom > GROUND_Y - 0.02, string.format("lowest sole corner=%.3f ground=%.3f", minBottom, GROUND_Y))
	check("legs: knee flex plausible", maxKnee < 110, string.format("max knee flex=%.1f deg", maxKnee))
end

-- ───────── 11. 関節可動域 ─────────
do
	local minE, maxE, maxW = math.huge, -math.huge, 0
	for _, f in frames do
		local ex = math.deg(select(1, f.pose.RightElbow:ToEulerAnglesXYZ()))
		minE, maxE = math.min(minE, ex), math.max(maxE, ex)
		maxW = math.max(maxW, PM.angleBetween(CFrame.new(), f.pose.RightWrist))
	end
	local maxKeyW = 0
	for _, s in Data.STRIKES do
		for _, k in s.keys do
			if k.pose ~= "FROM_CURRENT" then maxKeyW = math.max(maxKeyW, PM.angleBetween(CFrame.new(), PM.keyToCFrame(k.pose.RightWrist))) end
		end
	end
	check("right elbow within 0..150 (no hyperextension)", minE >= -0.01 and maxE <= 150, string.format("elbow range [%.1f, %.1f]", minE, maxE))
	check("right wrist: interpolation never exceeds keys", maxW <= maxKeyW + 0.5, string.format("max total wrist rotation frames=%.1f deg, keys=%.1f deg", maxW, maxKeyW))
end

-- ───────── 12. 単発（連打しない）: 1 撃で戻ってフェードアウト ─────────
do
	local single = simulate({ chain = false, hits = false, shake = false })
	local maxIdx = 0
	for _, f in single do maxIdx = math.max(maxIdx, f.index) end
	check("single press plays strike 1 only then fades", maxIdx == 1, string.format("frames=%d (%.3f s incl. %.2f s fade)", #single, #single * DT, 0.2))
end

print(string.format("\n%d passed, %d failed", passes, failures))
if failures > 0 then
	process.exit(1)
end
