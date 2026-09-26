--!strict
-- PoseMath: 純粋関数だけのモジュール（Roblox でも Lune でも動く。CFrame / Vector3 のみ使用）
--
-- 角度の符号規約（Motor6D.Transform、C0 の座標系。本リグは C0/C1 の回転が全て単位行列なので
-- 「親パーツの軸 = キャラクター軸」: +X = キャラの右, +Y = 上, -Z = 前）
--   * 回転は CFrame.Angles(rx, ry, rz)（= Rx * Ry * Rz）。表の値は「度」。
--   * X+ : 下向きの骨を「前へ」振り上げる（肩: 腕を前へ / 肘: 前腕を前へ曲げる / 腰(Waist): 上体を後ろへ反らす）
--          ※ Waist と Neck は上向きの骨なので X+ = 後ろへ反る、X- = 前へ屈む
--   * Y+ : 上から見て反時計回り = キャラの「左」へひねる
--   * Z+ : 下向きの骨を +X(右) 側へ（右腕なら外へ開く、左腕なら体の内側へ寄る）
--          上向きの骨（Waist/Neck）では Z+ = 左へ傾く
--   * 膝は X- で曲がる（下腿が後ろへ）、肘は X+ で曲がる（前腕が前へ）

local PoseMath = {}

local rad = math.rad

export type JointKey = { number } -- {rx, ry, rz [, px, py, pz]}  度 / stud
export type Pose = { [string]: JointKey }

-- ────────────────────────────── easing ──────────────────────────────
local EASE: { [string]: (number) -> number } = {
	linear = function(a) return a end,
	inQuad = function(a) return a * a end,
	outQuad = function(a) return 1 - (1 - a) * (1 - a) end,
	inCubic = function(a) return a * a * a end,
	outCubic = function(a) return 1 - (1 - a) ^ 3 end,
	inOutSine = function(a) return 0.5 - 0.5 * math.cos(math.pi * a) end,
	inOutCubic = function(a)
		if a < 0.5 then
			return 4 * a * a * a
		end
		return 1 - ((-2 * a + 2) ^ 3) / 2
	end,
	-- 振りの「溜めてから一気に」: 前半ほぼ止まり、後半で最大速度
	inQuart = function(a) return a * a * a * a end,
	-- フォロースルーの「一気に抜けてじわっと止まる」
	outQuart = function(a) return 1 - (1 - a) ^ 4 end,
}
PoseMath.EASE = EASE

function PoseMath.ease(name: string?, a: number): number
	local f = EASE[name or "inOutSine"]
	assert(f, "unknown ease " .. tostring(name))
	if a <= 0 then
		return 0
	elseif a >= 1 then
		return 1
	end
	return f(a)
end

-- ────────────────────────────── key → CFrame ──────────────────────────────
function PoseMath.keyToCFrame(k: JointKey?): CFrame
	if not k then
		return CFrame.new()
	end
	local rot = CFrame.Angles(rad(k[1] or 0), rad(k[2] or 0), rad(k[3] or 0))
	if k[4] or k[5] or k[6] then
		return CFrame.new(k[4] or 0, k[5] or 0, k[6] or 0) * rot
	end
	return rot
end

-- CFrame → {rx, ry, rz}（度、CFrame.Angles 順）
function PoseMath.cframeToKey(cf: CFrame): JointKey
	local x, y, z = cf:ToEulerAnglesXYZ()
	local p = cf.Position
	return { math.deg(x), math.deg(y), math.deg(z), p.X, p.Y, p.Z }
end

-- 2 つの CFrame の回転差（度）
function PoseMath.angleBetween(a: CFrame, b: CFrame): number
	local rel = a:ToObjectSpace(b)
	local _, ang = rel:ToAxisAngle()
	ang = math.abs(ang) % (2 * math.pi)
	if ang > math.pi then
		ang = 2 * math.pi - ang
	end
	return math.deg(ang)
end

-- ────────────────────────────── key sampling ──────────────────────────────
-- keys: { {t=, ease=, pose={Joint={...}}, lhIK=number?}, ... }  t 昇順
-- 戻り値: joint → CFrame, lhIK weight
-- startPose: 1 本目のキー（pose == "FROM_CURRENT"）の代わりに使う CFrame 表（連続性のため）
function PoseMath.sample(keys: { any }, t: number, joints: { string }, startPose: { [string]: CFrame }?): ({ [string]: CFrame }, number)
	local n = #keys
	local i = 1
	while i < n and keys[i + 1].t <= t do
		i += 1
	end
	local k0 = keys[i]
	local k1 = keys[math.min(i + 1, n)]
	local alpha = 1
	if k1 ~= k0 and k1.t > k0.t then
		alpha = PoseMath.ease(k1.ease, (t - k0.t) / (k1.t - k0.t))
	end
	if t < k0.t then
		alpha = 0
	end
	local out: { [string]: CFrame } = {}
	for _, j in joints do
		local c0: CFrame
		if k0.pose == "FROM_CURRENT" then
			c0 = (startPose and startPose[j]) or CFrame.new()
		else
			c0 = PoseMath.keyToCFrame(k0.pose[j])
		end
		local c1: CFrame
		if k1.pose == "FROM_CURRENT" then
			c1 = (startPose and startPose[j]) or CFrame.new()
		else
			c1 = PoseMath.keyToCFrame(k1.pose[j])
		end
		out[j] = c0:Lerp(c1, alpha)
	end
	local w0 = k0.lhIK or 0
	local w1 = k1.lhIK or 0
	return out, w0 + (w1 - w0) * alpha
end

-- ────────────────────────────── 2-bone IK ──────────────────────────────
-- 一般形（C0/C1 に回転があっても可）。
--   rootJointFrame : ルート関節フレーム（Part0 * C0）の親空間での位置姿勢（回転込み）
--   A              : ルート関節の Part1 から見た「中間関節フレーム」 = C1root^-1 * C0mid
--   B              : 中間関節の Part1 から見た「末端関節フレーム」 = C1mid^-1 * C0end
--   target         : 末端関節（足首/手首）の目標位置（親空間）
--   pole           : 中間関節（膝/肘）を向けたい方向（親空間、ベクトル）
--   flexSign       : 中間関節が曲がる X 回転の符号（膝 = -1, 肘 = +1）
--   maxFlex        : 最大屈曲（度）
-- 戻り値: rootTransform(CFrame, 回転のみ), midTransform(CFrame), reachError(stud)
local function distForFlex(A: CFrame, B: CFrame, flexSign: number, deg: number): number
	local p = (A * CFrame.Angles(rad(deg) * flexSign, 0, 0) * B).Position
	return p.Magnitude
end

function PoseMath.solveTwoBone(rootJointFrame: CFrame, A: CFrame, B: CFrame, target: Vector3, pole: Vector3, flexSign: number, maxFlex: number?): (CFrame, CFrame, number)
	local maxF = maxFlex or 150
	local localTarget = rootJointFrame:PointToObjectSpace(target)
	local want = localTarget.Magnitude
	-- 屈曲角の探索（粗スキャン → 黄金分割）。単調性を仮定しない。
	local bestDeg, bestErr = 0, math.huge
	local steps = 60
	for s = 0, steps do
		local d = maxF * s / steps
		local e = math.abs(distForFlex(A, B, flexSign, d) - want)
		if e < bestErr then
			bestErr, bestDeg = e, d
		end
	end
	local lo = math.max(0, bestDeg - maxF / steps)
	local hi = math.min(maxF, bestDeg + maxF / steps)
	for _ = 1, 40 do
		local m1 = lo + (hi - lo) * 0.382
		local m2 = lo + (hi - lo) * 0.618
		if math.abs(distForFlex(A, B, flexSign, m1) - want) < math.abs(distForFlex(A, B, flexSign, m2) - want) then
			hi = m2
		else
			lo = m1
		end
	end
	local flex = (lo + hi) * 0.5
	local midT = CFrame.Angles(rad(flex) * flexSign, 0, 0)
	-- ルート関節フレーム内での（回転前の）末端位置と中間位置
	local v = (A * midT * B).Position
	local a = A.Position
	-- 局所基底
	local e1 = v.Unit
	local aPerp = a - e1 * a:Dot(e1)
	if aPerp.Magnitude < 1e-5 then
		aPerp = Vector3.new(0, 0, -1) - e1 * (-e1.Z)
	end
	local e2 = aPerp.Unit
	local e3 = e1:Cross(e2)
	-- 目標側の基底（ルート関節フレーム空間）
	local E1 = if localTarget.Magnitude > 1e-6 then localTarget.Unit else e1
	local lp = rootJointFrame:VectorToObjectSpace(pole)
	local pPerp = lp - E1 * lp:Dot(E1)
	if pPerp.Magnitude < 1e-5 then
		pPerp = e2 -- 退化時は現在の向きを維持
	end
	local E2 = pPerp.Unit
	local E3 = E1:Cross(E2)
	-- R = [E1 E2 E3][e1 e2 e3]^T の列ベクトル
	local function col(x: Vector3): Vector3
		return E1 * e1:Dot(x) + E2 * e2:Dot(x) + E3 * e3:Dot(x)
	end
	local rootT = CFrame.fromMatrix(Vector3.zero, col(Vector3.xAxis), col(Vector3.yAxis), col(Vector3.zAxis))
	local reach = (rootT * midT * B).Position
	local reachWorld = rootJointFrame * (rootT * A * midT * B).Position
	local err = (reachWorld - target).Magnitude
	local _ = reach
	return rootT, midT, err
end

-- ────────────────────────────── FK（検証・IK 用） ──────────────────────────────
-- rig: { [jointName] = { p0=, p1=, C0=CFrame, C1=CFrame } }
-- transforms: jointName → CFrame（無ければ単位）
-- 戻り値: partName → CFrame（HumanoidRootPart 空間。hrpCFrame を渡せばワールド）
local ORDER = {
	"Root", "Waist", "Neck",
	"RightShoulder", "RightElbow", "RightWrist",
	"LeftShoulder", "LeftElbow", "LeftWrist",
	"RightHip", "RightKnee", "RightAnkle",
	"LeftHip", "LeftKnee", "LeftAnkle",
}
PoseMath.FK_ORDER = ORDER

function PoseMath.forwardKinematics(rig: { [string]: any }, transforms: { [string]: CFrame }, hrpCFrame: CFrame?): { [string]: CFrame }
	local parts: { [string]: CFrame } = { HumanoidRootPart = hrpCFrame or CFrame.new() }
	for _, j in ORDER do
		local m = rig[j]
		local p0 = parts[m.p0]
		assert(p0, "FK order: parent missing for " .. j)
		parts[m.p1] = p0 * m.C0 * (transforms[j] or CFrame.new()) * m.C1:Inverse()
	end
	return parts
end

-- ────────────────────────────── 脚 IK（足を床に固定したまま骨盤を沈める） ──────────────────────────────
-- rig は { [joint] = { C0 = CFrame, C1 = CFrame } }（実機では Motor6D から、テストでは rig-r15.json から）
-- 全て HumanoidRootPart 空間。
function PoseMath.legRestTargets(rig: { [string]: any }): { [string]: any }
	local LT = rig.Root.C0 * rig.Root.C1:Inverse()
	local out = {}
	for _, side in { "Right", "Left" } do
		local hip, knee, ankle = rig[side .. "Hip"], rig[side .. "Knee"], rig[side .. "Ankle"]
		local f = LT * hip.C0 * hip.C1:Inverse() * knee.C0 * knee.C1:Inverse() * ankle.C0
		out[side] = { ankle = f.Position, frame = f.Rotation }
	end
	return out
end

-- rootT: Root.Transform（骨盤）。targets: legRestTargets の戻り値（踏んでいる足首位置・向き）
-- 戻り値: joint → Transform、最大到達誤差(stud)
function PoseMath.solveLegs(rig: { [string]: any }, rootT: CFrame, targets: { [string]: any }): ({ [string]: CFrame }, number)
	local LT = rig.Root.C0 * rootT * rig.Root.C1:Inverse()
	local out: { [string]: CFrame } = {}
	local worst = 0
	for _, side in { "Right", "Left" } do
		local hip, knee, ankle = rig[side .. "Hip"], rig[side .. "Knee"], rig[side .. "Ankle"]
		local jointFrame = LT * hip.C0
		local A = hip.C1:Inverse() * knee.C0
		local B = knee.C1:Inverse() * ankle.C0
		local tgt = targets[side]
		local pole = LT:VectorToWorldSpace(Vector3.new(0, 0, -1)) -- 膝は骨盤の前へ
		local hipT, kneeT, err = PoseMath.solveTwoBone(jointFrame, A, B, tgt.ankle, pole, -1, 150)
		local ankleFrame = jointFrame * hipT * A * kneeT * B
		out[side .. "Hip"] = hipT
		out[side .. "Knee"] = kneeT
		out[side .. "Ankle"] = ankleFrame.Rotation:Inverse() * tgt.frame
		worst = math.max(worst, err)
	end
	return out, worst
end

-- ────────────────────────────── 左手を柄へ（両手持ち） ──────────────────────────────
-- T: 現在の Transform 表（Root/Waist/Right* を含む）。右手の握りから刃と逆向きへ pommelBack 進んだ点を
-- 左手の握り点にし、左手の向きは右手と同じにする。戻り値: {LeftShoulder, LeftElbow, LeftWrist}, 誤差
function PoseMath.solveLeftOnHilt(rig: { [string]: any }, T: { [string]: CFrame }, gripOff: Vector3, pommelBack: number, prevPsi: number?): ({ [string]: CFrame }, number, number)
	local parts = PoseMath.forwardKinematics(rig, T)
	local rh = parts.RightHand
	local dir = rh:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local P = rh:PointToWorldSpace(gripOff) - dir * pommelBack
	local sh, el, wr = rig.LeftShoulder, rig.LeftElbow, rig.LeftWrist
	local jointFrame = parts.UpperTorso * sh.C0
	local A = sh.C1:Inverse() * el.C0
	local B = el.C1:Inverse() * wr.C0
	-- 左手の向き: 右手と同じ向きを基準に、刃の軸まわりのロール ψ だけは自由にする
	-- （柄を握ったまま前腕を寄せる/離す動き。ロール固定だと頭上や胸元で届かない）。
	-- ψ は「肩→手首の距離が腕の届く範囲に入る最小の回転」を連続的に（二分法で）求める = フレーム間で跳ばない。
	-- 基準の向き = いま FK で出ている左手の向きを、-Z が刃の向きに揃うよう最小回転したもの
	-- （焼き込み済みの左手 FK と一致させる。右手の向きをそのまま使うとロールが 180 度ずれて Lerp が破綻する）
	local lhFK = parts.LeftHand
	local fwd = lhFK:VectorToWorldSpace(Vector3.new(0, 0, -1))
	local axis = fwd:Cross(dir)
	local R0 = lhFK.Rotation
	if axis.Magnitude > 1e-6 then
		R0 = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(fwd:Dot(dir), -1, 1))) * R0
	elseif fwd:Dot(dir) < 0 then
		R0 = CFrame.fromAxisAngle(lhFK:VectorToWorldSpace(Vector3.xAxis), math.pi) * R0
	end
	local sPos = jointFrame.Position
	local c = R0:VectorToWorldSpace(wr.C1.Position - gripOff)
	local cPerp = c - dir * c:Dot(dir)
	local u = (sPos - P) - dir * (sPos - P):Dot(dir)
	local dMin, dMax = math.huge, 0
	for f = 0, 150, 5 do
		local d = (A * CFrame.Angles(math.rad(f), 0, 0) * B).Position.Magnitude
		dMin, dMax = math.min(dMin, d), math.max(dMax, d)
	end
	dMin += 0.03
	dMax -= 0.03
	local function distAt(psi: number): number
		return (P + CFrame.fromAxisAngle(dir, psi):VectorToWorldSpace(c) - sPos).Magnitude
	end
	local psi = 0
	if cPerp.Magnitude > 1e-4 and u.Magnitude > 1e-4 then
		local a1, a2 = cPerp.Unit, u.Unit
		local toward = math.atan2(a1:Cross(a2):Dot(dir), a1:Dot(a2)) -- 手首が肩へ最も近づくロール
		local away = toward + (if toward > 0 then -math.pi else math.pi)
		-- ±π 付近で回す向きが入れ替わらないよう、前フレームの ψ に近い表現を選ぶ（アンラップ）
		if prevPsi then
			local function unwrap(x: number): number
				while x - prevPsi > math.pi do x -= 2 * math.pi end
				while x - prevPsi < -math.pi do x += 2 * math.pi end
				return x
			end
			toward, away = unwrap(toward), unwrap(away)
		end
		local d0 = distAt(0)
		local goal, limit = nil, 0
		if d0 > dMax then
			goal, limit = dMax, toward
		elseif d0 < dMin then
			goal, limit = dMin, away
		end
		if goal then
			if (distAt(limit) - goal) * (d0 - goal) > 0 then
				psi = limit -- 回しきっても届かない: 最も近い向き
			else
				local lo, hi = 0, 1
				for _ = 1, 30 do
					local m = (lo + hi) / 2
					if (distAt(limit * m) - goal) * (d0 - goal) > 0 then lo = m else hi = m end
				end
				psi = limit * (lo + hi) / 2
			end
		end
	end
	local Rdes = CFrame.fromAxisAngle(dir, psi) * R0
	local wristTarget = P + Rdes:VectorToWorldSpace(wr.C1.Position - gripOff)
	-- 肘の向き（ポール）は FK の肘位置から取る = キーで作った肘の張りを保ち、フレーム間で反転しない
	local fkElbow = (parts.LeftUpperArm * el.C0).Position
	local pole = fkElbow - sPos
	local tdir = (wristTarget - sPos)
	if tdir.Magnitude > 1e-4 and (pole - tdir.Unit * pole:Dot(tdir.Unit)).Magnitude < 0.05 then
		pole = parts.UpperTorso:VectorToWorldSpace(Vector3.new(-0.6, -0.7, 0.3)) -- 退化時: 外・下・やや後ろ
	end
	local sT, eT, e = PoseMath.solveTwoBone(jointFrame, A, B, wristTarget, pole, 1, 150)
	local best = { sT = sT, eT = eT, err = e, R = Rdes }
	local shT, elT, err = best.sT, best.eT, best.err
	local wristFrame = jointFrame * shT * A * elT * B
	local wrT = wristFrame.Rotation:Inverse() * best.R * wr.C1.Rotation
	return { LeftShoulder = shT, LeftElbow = elT, LeftWrist = wrT }, err, psi
end

return PoseMath
