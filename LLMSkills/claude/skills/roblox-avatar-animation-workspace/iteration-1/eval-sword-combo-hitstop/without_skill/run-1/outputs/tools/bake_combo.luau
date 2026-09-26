-- Lune 0.10.5:  lune run tools/bake_combo.luau  （outputs/ をカレントにして実行）
-- ComboAuthoring（剣の握り位置・刃の向き）を rig-r15.json の FK でオフライン IK し、
-- 関節角（度）へ焼き込んだ src/SwordCombo/ComboData.luau を書き出す。
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
local A = load("tools/ComboAuthoring.luau")

local raw = serde.decode("json", fs.readFile(RIG_PATH))
local rig = {}
for k, v in raw do
	if type(v) == "table" and v.c0 then
		rig[k] = { p0 = v.p0, p1 = v.p1, C0 = CFrame.new(table.unpack(v.c0)), C1 = CFrame.new(table.unpack(v.c1)), s1 = v.s1 }
	end
end

local function v3(t) return Vector3.new(t[1], t[2], t[3]) end
local gripOff = v3(A.gripOffset)

-- 腕 7 自由度 {sx, sy, sz, ex, wx, wy, wz} → transforms
local function armT(side: string, q)
	return {
		[side .. "Shoulder"] = PM.keyToCFrame({ q[1], q[2], q[3] }),
		[side .. "Elbow"] = PM.keyToCFrame({ q[4], 0, 0 }),
		[side .. "Wrist"] = PM.keyToCFrame({ q[5], q[6], q[7] }),
	}
end

local function solveArm(side: string, base, target: Vector3, dir: Vector3, seed)
	local LIM = { { -180, 200 }, { -90, 90 }, { -120, 120 }, { 0, 145 }, { -65, 65 }, { -65, 65 }, { -65, 65 } }
	local function clampQ(qq)
		for i = 1, 7 do qq[i] = math.clamp(qq[i], LIM[i][1], LIM[i][2]) end
		return qq
	end
	local q = clampQ(table.clone(seed))
	local function cost(qq)
		local T = table.clone(base)
		for k, v in armT(side, qq) do T[k] = v end
		local parts = PM.forwardKinematics(rig, T)
		local hand = parts[side .. "Hand"]
		local g = hand:PointToWorldSpace(gripOff)
		local d = hand:VectorToWorldSpace(Vector3.new(0, 0, -1))
		local c = 60 * (g - target).Magnitude ^ 2 + 25 * (1 - d:Dot(dir.Unit))
		-- 手首は小さく・肩のひねりは控えめ・肘は 0..145 度・前キーからの変化は小さく
		c += 0.00012 * (qq[5] ^ 2 + qq[6] ^ 2 + qq[7] ^ 2)
		c += 0.00004 * qq[2] ^ 2
		if qq[4] < 0 then c += 0.02 * qq[4] ^ 2 end
		if qq[4] > 145 then c += 0.02 * (qq[4] - 145) ^ 2 end
		for i = 5, 7 do
			if math.abs(qq[i]) > 65 then c += 0.02 * (math.abs(qq[i]) - 65) ^ 2 end
		end
		for i = 1, 7 do c += 0.000015 * (qq[i] - seed[i]) ^ 2 end
		return c, (g - target).Magnitude, math.deg(math.acos(math.clamp(d:Dot(dir.Unit), -1, 1)))
	end
	local function search(start)
		local qq = clampQ(table.clone(start))
		local best = cost(qq)
		local step = 24
		while step > 0.02 do
			local improved = true
			while improved do
				improved = false
				for i = 1, 7 do
					for _, s in { step, -step } do
						local old = qq[i]
						qq[i] = math.clamp(old + s, LIM[i][1], LIM[i][2])
						local c = cost(qq)
						if c < best then
							best = c
							improved = true
						else
							qq[i] = old
						end
					end
				end
			end
			step *= 0.5
		end
		return qq, best
	end
	-- 多点スタート（前キーの解・構え・前へ伸ばした腕・頭上の腕）→ 最良を採用。局所解（肘を畳んで手首で帳尻を合わせる等）を避ける
	local seeds = { q, { 26, 24, -34, 58, -38, -15, -8 }, { 70, 0, -10, 15, -40, 0, 0 }, { 160, 0, 0, 10, 0, 0, 0 }, { 45, 0, 30, 60, -20, 0, 0 } }
	local bestQ, bestC = nil, math.huge
	for _, sd in seeds do
		local qq, c = search(sd)
		if c < bestC then bestQ, bestC = qq, c end
	end
	q = bestQ
	local _, perr, derr = cost(q)
	return q, perr, derr
end

local function r2(x: number): string
	local s = string.format("%.2f", x)
	if s == "-0.00" then s = "0.00" end
	return s
end
local function t3(x: number): string
	local s = string.format("%.3f", x):gsub("0+$", ""):gsub("%.$", ".0")
	return s
end
local function keyStr(k): string
	local parts = {}
	for _, x in k do table.insert(parts, r2(x)) end
	return "{ " .. table.concat(parts, ", ") .. " }"
end

local function neckFor(root, waist)
	-- 頭を目標方向へ残す（上体のひねり・前後傾を首で 6〜7 割打ち消す）
	return { -0.5 * (root[1] + waist[1]), -0.7 * (root[2] + waist[2]), -0.6 * (root[3] + waist[3]) }
end

local report = {}
local prevR = { 40, 0, -20, 50, -30, 0, 0 }
local prevL = { 18, 0, 12, 40, 0, 0, 0 }

local function bakeKey(key, label)
	local root = key.root
	local waist = key.waist
	local base = {
		Root = PM.keyToCFrame(root),
		Waist = PM.keyToCFrame(waist),
	}
	local qR, pe, de = solveArm("Right", base, v3(key.grip), v3(key.dir), prevR)
	prevR = qR
	local pose = {
		Root = root,
		Waist = waist,
		Neck = neckFor(root, waist),
		RightShoulder = { qR[1], qR[2], qR[3] },
		RightElbow = { qR[4], 0, 0 },
		RightWrist = { qR[5], qR[6], qR[7] },
	}
	local lhIK = 0
	local lpe, lde = 0, 0
	if key.left == "HILT" then
		-- 右手の実際の握り（解いた結果）から柄頭側へ
		local T = table.clone(base)
		for k, v in armT("Right", qR) do T[k] = v end
		local parts = PM.forwardKinematics(rig, T)
		local hand = parts.RightHand
		local g = hand:PointToWorldSpace(gripOff)
		local d = hand:VectorToWorldSpace(Vector3.new(0, 0, -1))
		local qL
		qL, lpe, lde = solveArm("Left", base, g - d * A.pommelBack, d, prevL)
		prevL = qL
		pose.LeftShoulder = { qL[1], qL[2], qL[3] }
		pose.LeftElbow = { qL[4], 0, 0 }
		pose.LeftWrist = { qL[5], qL[6], qL[7] }
		lhIK = if key.lhIK ~= nil then key.lhIK else 1
	else
		pose.LeftShoulder = key.left.LeftShoulder
		pose.LeftElbow = key.left.LeftElbow
		pose.LeftWrist = key.left.LeftWrist
		prevL = { key.left.LeftShoulder[1], key.left.LeftShoulder[2], key.left.LeftShoulder[3], key.left.LeftElbow[1], 0, 0, 0 }
	end
	table.insert(report, string.format("%-28s gripErr=%.3f stud dirErr=%.1f deg | leftErr=%.3f stud %.1f deg", label, pe, de, lpe, lde))
	return pose, lhIK
end

local JOINTS = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }

local function poseStr(pose, indent: string): string
	local lines = {}
	for _, j in JOINTS do
		table.insert(lines, string.format("%s%s = %s,", indent, j, keyStr(pose[j])))
	end
	return table.concat(lines, "\n")
end

local readyPose = bakeKey(A.ready, "READY")
local readyQ = table.clone(prevR)
local out = {}
table.insert(out, "--!strict")
table.insert(out, "-- 自動生成: tools/bake_combo.luau（元データ tools/ComboAuthoring.luau + rig-r15.json）。手で直さないこと。")
table.insert(out, "-- 角度は度・CFrame.Angles(rx, ry, rz) 順・Motor6D.Transform（C0 空間）。Root だけ {rx,ry,rz,px,py,pz}。")
table.insert(out, "-- 符号規約は PoseMath.luau 冒頭 / SPEC.md を参照。")
table.insert(out, "local ComboData = {}")
table.insert(out, "")
table.insert(out, "ComboData.JOINTS = { \"Root\", \"Waist\", \"Neck\", \"RightShoulder\", \"RightElbow\", \"RightWrist\", \"LeftShoulder\", \"LeftElbow\", \"LeftWrist\" }")
table.insert(out, string.format("ComboData.GRIP_OFFSET = { %s, %s, %s } -- RightHand 空間の握り点", r2(A.gripOffset[1]), r2(A.gripOffset[2]), r2(A.gripOffset[3])))
table.insert(out, string.format("ComboData.BLADE_LENGTH = %s -- 握り点→切っ先（刃は RightHand の -Z 方向）", r2(A.bladeLength)))
table.insert(out, string.format("ComboData.POMMEL_BACK = %s -- 両手持ち時の左手の位置（右手の握りから刃と逆向き）", r2(A.pommelBack)))
table.insert(out, "ComboData.READY = {")
table.insert(out, poseStr(readyPose, "\t"))
table.insert(out, "}")
table.insert(out, "")
table.insert(out, "ComboData.STRIKES = {")
for si, s in A.strikes do
	table.insert(out, "\t{")
	table.insert(out, string.format("\t\tname = %q,", s.name))
	table.insert(out, string.format("\t\tduration = %s,", t3(s.duration)))
	table.insert(out, string.format("\t\tactive = { %s, %s }, -- 当たり判定を取る区間（秒）", t3(s.active[1]), t3(s.active[2])))
	table.insert(out, string.format("\t\thitTime = %s, -- 作画上の当たりフレーム（KeyframeMarker \"Hit\"）", t3(s.hitTime)))
	table.insert(out, string.format("\t\thitStop = %s, -- ヒットストップ秒", t3(s.hitStop)))
	table.insert(out, string.format("\t\tchainAt = %s, -- 次段へ移れる最早時刻（nil = 最終段）", s.chainAt and t3(s.chainAt) or "nil"))
	table.insert(out, string.format("\t\tgroundImpact = %s,", tostring(s.groundImpact == true)))
	table.insert(out, "\t\tkeys = {")
	for _, k in s.keys do
		if k.from then
			table.insert(out, string.format("\t\t\t{ t = %s, pose = \"FROM_CURRENT\", phase = %q },", r2(k.t), k.phase))
		elseif k.isReady then
			table.insert(out, string.format("			{ t = %s, ease = %q, lhIK = 0, phase = %q, pose = ComboData.READY },", t3(k.t), k.ease, k.phase))
			prevR = readyQ
		else
			local pose, lh = bakeKey(k, s.name .. " t=" .. t3(k.t))
			table.insert(out, string.format("\t\t\t{ t = %s, ease = %q, lhIK = %d, phase = %q, pose = {", r2(k.t), k.ease, lh, k.phase))
			table.insert(out, poseStr(pose, "\t\t\t\t"))
			table.insert(out, "\t\t\t} },")
		end
	end
	table.insert(out, "\t\t},")
	table.insert(out, "\t},")
	local _ = si
end
table.insert(out, "}")
table.insert(out, "")
table.insert(out, "return ComboData")
table.insert(out, "")

fs.writeFile("src/SwordCombo/ComboData.luau", table.concat(out, "\n"))
for _, l in report do print(l) end
print("wrote src/SwordCombo/ComboData.luau")
