--[[
	ProceduralGrounding/Solver
	R15 の「足の接地 (脚 IK + 骨盤の沈み + 足首の地面合わせ)」と「旋回リーン」を計算する純粋な数学モジュール。
	Instance / RunService / workspace には一切触らない (CFrame・Vector3・math のみ)。
	そのため Lune (@lune/roblox) でそのままオフライン検証できる。

	座標の約束 (Motor6D):  Part1.CFrame = Part0.CFrame * C0 * Transform * C1:Inverse()
	HRP ローカル: -Z が前, +X が右, +Y が上。
	CFrame.Angles(0, 0, θ) の θ > 0 は「左へ傾く」。ヨー角 (上から見て反時計回り) > 0 は「左旋回」。
	→ 左旋回で θ > 0 (内側 = 左) に傾くので符号はそのまま一致する。
]]

local Solver = {}

local SIDES = { "Left", "Right" }
local UP = Vector3.new(0, 1, 0)
local IDENTITY = CFrame.new()

local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- 指数的に target へ近づける (フレームレート非依存)
local function approach(current: number, target: number, rate: number, dt: number): number
	return target + (current - target) * math.exp(-rate * dt)
end

local function wrapAngle(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- 臨界減衰ばね (陰的オイラー: どんな dt でも発散しない)
local function springStep(x: number, v: number, target: number, omega: number, dt: number): (number, number)
	local f = 1 + 2 * dt * omega
	local oo = omega * omega
	local hoo = dt * oo
	local hhoo = dt * hoo
	local detInv = 1 / (f + hhoo)
	local newX = (f * x + dt * v + hhoo * target) * detInv
	local newV = (v + hoo * (target - x)) * detInv
	return newX, newV
end

-- ベクトル a を b へ向ける最小回転
local function fromTo(a: Vector3, b: Vector3): CFrame
	local ma, mb = a.Magnitude, b.Magnitude
	if ma < 1e-6 or mb < 1e-6 then
		return IDENTITY
	end
	local ua, ub = a / ma, b / mb
	local d = clamp(ua:Dot(ub), -1, 1)
	local axis = ua:Cross(ub)
	local s = axis.Magnitude
	if s < 1e-7 then
		if d > 0 then
			return IDENTITY
		end
		local perp = ua:Cross(Vector3.new(1, 0, 0))
		if perp.Magnitude < 1e-3 then
			perp = ua:Cross(Vector3.new(0, 0, 1))
		end
		return CFrame.fromAxisAngle(perp.Unit, math.pi)
	end
	return CFrame.fromAxisAngle(axis / s, math.atan2(s, d))
end

-- 点 pivot を中心に回転 rot (純回転) を掛ける CFrame
local function rotateAbout(pivot: Vector3, rot: CFrame): CFrame
	return CFrame.new(pivot) * rot * CFrame.new(-pivot)
end

-- Part0 空間の回転 rot を、関節点まわりの Transform 用に変換する
local function rotInParent(c0: CFrame, rot: CFrame): CFrame
	local r = c0.Rotation
	return r:Inverse() * rot * r
end

Solver.fromTo = fromTo
Solver.springStep = springStep
Solver.wrapAngle = wrapAngle

function Solver.cframeNear(a: CFrame, b: CFrame, eps: number): boolean
	if (a.Position - b.Position).Magnitude > eps then
		return false
	end
	return (a.RightVector - b.RightVector).Magnitude <= eps and (a.UpVector - b.UpVector).Magnitude <= eps
end

--[[
	Animator がこのフレームに書いた「素の」Transform を得る。
	今フレーム Animator がその関節に触れていない場合、Motor6D には前フレームに自分が書いた値が残っている。
	それを素の値と誤認して重ね掛けすると毎フレーム累積してしまうので、前回書いた値と同じなら前回の素の値を使う。
]]
function Solver.resolveBase(current: CFrame, lastWritten: CFrame?, lastBase: CFrame?): CFrame
	if lastWritten ~= nil and lastBase ~= nil and Solver.cframeNear(current, lastWritten, 1e-5) then
		return lastBase
	end
	return current
end

function Solver.newState()
	return {
		weight = 0, -- 0 = 素のアニメ, 1 = 接地補正 100%
		lean = 0,
		leanVel = 0,
		drop = 0, -- 骨盤を下げている量 (stud)
		prevYaw = nil :: number?,
		prevHrpY = nil :: number?,
		footGround = {} :: { [string]: number? }, -- 各足の下の地面高さ (ワールド Y, 平滑化済み)
	}
end

--[[
	input = {
		dt: number,
		rootCFrame: CFrame,          -- HumanoidRootPart.CFrame
		rootSizeY: number,           -- HumanoidRootPart.Size.Y
		hipHeight: number,           -- Humanoid.HipHeight
		joints: { [name]: { c0: CFrame, c1: CFrame, base: CFrame } },
		                             -- Root, LeftHip, LeftKnee, LeftAnkle, RightHip, RightKnee, RightAnkle (必須)
		                             -- Waist, Neck (任意)
		footSize: { Left: Vector3, Right: Vector3 },
		velocity: Vector3,           -- HRP.AssemblyLinearVelocity
		gravity: number,             -- workspace.Gravity
		grounded: boolean,           -- Humanoid が地上ステートか
		sample: (x, z, yTop, yBottom) -> (number?, Vector3?)  -- 鉛直レイで地面の高さと法線
	}
	戻り値 { transforms = { [name]: CFrame }, debug = {...} }
]]
function Solver.solve(input, state, cfg)
	local rawDt = math.max(input.dt, 1e-3)
	local dt = clamp(input.dt, 1 / 240, 1 / 15)
	local hrp: CFrame = input.rootCFrame
	local J = input.joints
	local hipHeight: number = input.hipHeight
	local halfRoot: number = input.rootSizeY * 0.5
	-- Humanoid は HRP を「床 + HipHeight + HRP半高」に保つ。アニメはこの床を前提に作られている。
	local groundRef = hrp.Position.Y - hipHeight - halfRoot

	local root = J.Root
	local lt0 = hrp * root.c0 * root.base * root.c1:Inverse()

	-- 1. 素のアニメの脚 FK と、足下の地面サンプリング -----------------------------
	local legs = {}
	local anyGround = false
	local yTop = groundRef + cfg.probeUp
	local yBottom = groundRef - cfg.probeDown
	for _, side in SIDES do
		local hipJ, kneeJ, ankleJ = J[side .. "Hip"], J[side .. "Knee"], J[side .. "Ankle"]
		local u0 = lt0 * hipJ.c0 * hipJ.base * hipJ.c1:Inverse()
		local l0 = u0 * kneeJ.c0 * kneeJ.base * kneeJ.c1:Inverse()
		local f0 = l0 * ankleJ.c0 * ankleJ.base * ankleJ.c1:Inverse()
		local h0 = lt0 * hipJ.c0.Position
		local k0 = u0 * kneeJ.c0.Position
		local a0 = l0 * ankleJ.c0.Position

		local size: Vector3 = input.footSize[side]
		local hy, hz = size.Y * 0.5, size.Z * 0.5
		local soleC = f0 * Vector3.new(0, -hy, 0)
		local heel = f0 * Vector3.new(0, -hy, hz)
		local toe = f0 * Vector3.new(0, -hy, -hz)
		local fwd = Vector3.new(toe.X - heel.X, 0, toe.Z - heel.Z)
		local lh = fwd.Magnitude
		local fwdU: Vector3
		if lh > 0.15 then
			fwdU = fwd / lh
		else
			local lv = f0.LookVector
			local flat = Vector3.new(lv.X, 0, lv.Z)
			fwdU = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
			lh = 0
		end
		local rightU = fwdU:Cross(UP)

		local gc, nc = input.sample(soleC.X, soleC.Z, yTop, yBottom)
		local gh, nh, gt, nt = nil, nil, nil, nil
		if lh > 0 then
			gh, nh = input.sample(heel.X, heel.Z, yTop, yBottom)
			gt, nt = input.sample(toe.X, toe.Z, yTop, yBottom)
		end

		-- 面の傾き = 当たった面の法線の平均 (壁のような急面は除外)。
		-- 階段の踏み面は法線が真上なので足は水平のまま上の段に乗る (段の角で足をつま先下がりに折らない)。
		local nSum = Vector3.zero
		if nh and nh.Y >= cfg.minGroundNormalY then
			nSum += nh
		end
		if nc and nc.Y >= cfg.minGroundNormalY then
			nSum += nc
		end
		if nt and nt.Y >= cfg.minGroundNormalY then
			nSum += nt
		end
		local slope, sideSlope = 0, 0
		if nSum.Magnitude > 1e-3 then
			local n = nSum.Unit
			slope = -n:Dot(fwdU) / n.Y
			sideSlope = -n:Dot(rightU) / n.Y
		end
		local tanP = math.tan(cfg.maxFootPitch)
		local tanR = math.tan(cfg.maxFootRoll)
		slope = clamp(slope, -tanP, tanP)
		sideSlope = clamp(sideSlope, -tanR, tanR)

		-- 足裏の線 y(x) = center + slope * x (x: 足裏中心から前方への水平距離) を、3 点すべてが地面の上に来る高さに置く
		local center = -math.huge
		if gh then
			center = math.max(center, gh + slope * lh * 0.5)
		end
		if gc then
			center = math.max(center, gc)
		end
		if gt then
			center = math.max(center, gt - slope * lh * 0.5)
		end

		local hasGround = center > -math.huge
		if hasGround then
			anyGround = true
		end

		legs[side] = {
			hipJ = hipJ,
			kneeJ = kneeJ,
			ankleJ = ankleJ,
			u0 = u0,
			l0 = l0,
			f0 = f0,
			h0 = h0,
			k0 = k0,
			a0 = a0,
			soleC = soleC,
			clearance = math.min(heel.Y, toe.Y, soleC.Y) - groundRef,
			fwdU = fwdU,
			rightU = rightU,
			slope = slope,
			sideSlope = sideSlope,
			center = if hasGround then center else nil,
		}
	end

	-- 2. 接地ウェイト (空中・泳ぎ・座り等では 0 へ) -------------------------------
	local groundedTarget = if input.grounded and anyGround then 1 else 0
	state.weight = approach(state.weight, groundedTarget, cfg.weightRate, dt)
	if state.weight < 1e-3 and groundedTarget == 0 then
		state.weight = 0
	elseif state.weight > 0.999 and groundedTarget == 1 then
		state.weight = 1
	end
	local w = state.weight

	-- 空中 (ウェイト 0) で傾きも消えたら素のアニメをそのまま返す (ほぼ伸び切った脚の微小な曲がりも出さない)
	if w == 0 and math.abs(state.lean) < 1e-3 and math.abs(state.leanVel) < 1e-3 then
		state.drop = 0
		state.prevHrpY = hrp.Position.Y
		state.prevYaw = math.atan2(-hrp.LookVector.X, -hrp.LookVector.Z)
		state.lean, state.leanVel = 0, 0
		local out = {}
		for name, j in J do
			out[name] = j.base
		end
		return {
			transforms = out,
			debug = { weight = 0, lean = 0, leanTarget = 0, yawRate = 0, drop = 0, groundRef = groundRef, legs = {
				Left = { offset = 0, plant = 0, reachError = 0 },
				Right = { offset = 0, plant = 0, reachError = 0 },
			} },
		}
	end

	-- 3. 足の目標 (ワールド): 地面の線に足裏中心を乗せ、足裏を面に合わせる --------------
	for _, side in SIDES do
		local leg = legs[side]
		local center = leg.center
		local prevG = state.footGround[side]
		local g: number? = nil
		local plantNow = 1 - smoothstep(cfg.plantClearanceLo, cfg.plantClearanceHi, leg.clearance)
		if center then
			if prevG == nil or w < 0.05 or center >= prevG or plantNow > 0.5 or math.abs(center - prevG) > cfg.footGroundSnap then
				-- 地面が上がる方向・接地中の足は即時 (めり込ませない / 浮かせない)。
				-- 振り上げ中の足が段を降りるときだけ平滑化 (足先がワープしない)
				g = center
			else
				g = approach(prevG, center, cfg.footGroundRate, dt)
			end
		end
		state.footGround[side] = g

		local target = leg.f0
		leg.offset = 0
		leg.plant = 1 - smoothstep(cfg.plantClearanceLo, cfg.plantClearanceHi, leg.clearance)
		if g then
			local offset = clamp(g - groundRef, -cfg.maxFootDown, cfg.maxFootUp)
			local tf = leg.fwdU + UP * leg.slope
			local tr = leg.rightU + UP * leg.sideSlope
			local n = tr:Cross(tf).Unit
			local align = IDENTITY:Lerp(fromTo(UP, n), leg.plant)
			target = CFrame.new(0, offset, 0) * rotateAbout(leg.soleC, align) * leg.f0
			leg.offset = offset
		end
		target = leg.f0:Lerp(target, w)
		leg.target = target
		-- 足首の取り付け点 (足パーツ空間) を目標足に写したものが脚 IK の目標
		local attachLocal = leg.f0:PointToObjectSpace(leg.a0)
		leg.goal = target * attachLocal
	end

	-- 4. 旋回リーン: 横加速度 = 速さ × ヨー角速度, 傾き = atan(横加速度 / 重力) -----------
	local look = hrp.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local yawRate = 0
	if state.prevYaw ~= nil then
		yawRate = clamp(wrapAngle(yaw - state.prevYaw) / rawDt, -cfg.maxYawRate, cfg.maxYawRate)
	end
	state.prevYaw = yaw
	local v: Vector3 = input.velocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local gravity = if input.gravity and input.gravity > 0 then input.gravity else 196.2
	local leanTarget = clamp(cfg.leanGain * math.atan(speed * yawRate / gravity), -cfg.maxLean, cfg.maxLean)
	leanTarget *= smoothstep(cfg.leanSpeedMin, cfg.leanSpeedFull, speed) * groundedTarget
	state.lean, state.leanVel = springStep(state.lean, state.leanVel, leanTarget, cfg.leanOmega, dt)
	local lean = clamp(state.lean, -cfg.maxLean * 1.2, cfg.maxLean * 1.2)

	-- 5. 骨盤: 足元 (地面) を支点に傾け、届かない足があれば骨盤を下げる ------------------
	local pivotLocal = Vector3.new(0, -(hipHeight + halfRoot), 0)
	local leanCF = rotateAbout(pivotLocal, CFrame.Angles(0, 0, lean))
	local ltLean = hrp * leanCF * root.c0 * root.base * root.c1:Inverse()
	local need = 0
	for _, side in SIDES do
		local leg = legs[side]
		local l1 = (leg.k0 - leg.h0).Magnitude
		local l2 = (leg.a0 - leg.k0).Magnitude
		leg.l1, leg.l2 = l1, l2
		local reach = l1 + l2
		local hipPos = ltLean * leg.hipJ.c0.Position
		local dv = leg.goal - hipPos
		local hsq = dv.X * dv.X + dv.Z * dv.Z
		local dy = hipPos.Y - leg.goal.Y
		local d
		if hsq >= reach * reach then
			d = dy
		else
			d = dy - math.sqrt(reach * reach - hsq)
		end
		if d > need then
			need = d
		end
	end
	need = clamp(need, 0, cfg.maxPelvisDrop)
	-- HRP が段差で急に持ち上がった分 (歩行の上昇速度を超える分) は骨盤を下げて相殺し、ワールド高さを保つ
	local hrpY = hrp.Position.Y
	local carried = state.drop
	if state.prevHrpY ~= nil then
		local dy = hrpY - state.prevHrpY
		if dy > 0 and dy < cfg.footGroundSnap then
			carried += math.max(0, dy - cfg.hrpRiseFollowSpeed * rawDt)
		end
	end
	state.prevHrpY = hrpY
	carried = math.min(carried, cfg.maxPelvisDrop)
	if need >= carried then
		-- 下げる方向は即時 (届かない足を作らない)
		state.drop = need
	else
		state.drop = approach(carried, need, cfg.dropReleaseRate, dt)
	end

	local dropLocal = hrp:VectorToObjectSpace(Vector3.new(0, -state.drop, 0))
	local rootMod = CFrame.new(dropLocal) * leanCF
	local out = {}
	out.Root = root.c0:Inverse() * rootMod * root.c0 * root.base
	local lt = hrp * root.c0 * out.Root * root.c1:Inverse()

	-- 6. 2 ボーン IK (太もも・すね) と足首 ---------------------------------------------
	local legDebug = {}
	for _, side in SIDES do
		local leg = legs[side]
		local hipJ, kneeJ, ankleJ = leg.hipJ, leg.kneeJ, leg.ankleJ
		local l1, l2 = leg.l1, leg.l2
		local hipPos = lt * hipJ.c0.Position
		local uCur = lt * hipJ.c0 * hipJ.base * hipJ.c1:Inverse()
		local kCur = uCur * kneeJ.c0.Position

		-- 膝の曲がる方向: 素のアニメの膝の向き。脚が真っ直ぐなら太ももの前方向 (膝は前に曲がる)
		local pole: Vector3? = nil
		local axis0 = leg.a0 - leg.h0
		if axis0.Magnitude > 1e-4 then
			local du = axis0.Unit
			local kv = leg.k0 - leg.h0
			pole = kv - du * kv:Dot(du)
		end
		if pole == nil or pole.Magnitude < 0.02 * l1 then
			pole = leg.u0.LookVector
		end

		local toGoal = leg.goal - hipPos
		local dist = toGoal.Magnitude
		local goalReached = leg.goal
		local kneePos = kCur
		if dist > 1e-4 then
			local dir = toGoal / dist
			local dC = clamp(dist, math.abs(l1 - l2) + 1e-3, l1 + l2)
			local cosA = clamp((l1 * l1 + dC * dC - l2 * l2) / (2 * l1 * dC), -1, 1)
			local sinA = math.sqrt(math.max(0, 1 - cosA * cosA))
			local bend = (pole :: Vector3) - dir * (pole :: Vector3):Dot(dir)
			if bend.Magnitude < 1e-5 then
				local lv = leg.u0.LookVector
				bend = lv - dir * lv:Dot(dir)
			end
			if bend.Magnitude > 1e-5 then
				bend = bend.Unit
			end
			kneePos = hipPos + dir * (l1 * cosA) + bend * (l1 * sinA)
			goalReached = hipPos + dir * dC
		end

		local uNew = rotateAbout(hipPos, fromTo(kCur - hipPos, kneePos - hipPos)) * uCur
		local lCur = uNew * kneeJ.c0 * kneeJ.base * kneeJ.c1:Inverse()
		local aCur = lCur * ankleJ.c0.Position
		local lNew = rotateAbout(kneePos, fromTo(aCur - kneePos, goalReached - kneePos)) * lCur

		out[side .. "Hip"] = hipJ.c0:Inverse() * lt:Inverse() * uNew * hipJ.c1
		out[side .. "Knee"] = kneeJ.c0:Inverse() * uNew:Inverse() * lNew * kneeJ.c1
		local x = ankleJ.c0:Inverse() * lNew:Inverse() * leg.target * ankleJ.c1
		out[side .. "Ankle"] = CFrame.new(ankleJ.base.Position) * x.Rotation

		legDebug[side] = {
			offset = leg.offset,
			plant = leg.plant,
			reachError = ((lNew * ankleJ.c0.Position) - leg.goal).Magnitude,
		}
	end

	-- 7. 上半身の追加リーンと頭の水平保持 -------------------------------------------
	local waist, neck = J.Waist, J.Neck
	if waist then
		out.Waist = rotInParent(waist.c0, CFrame.Angles(0, 0, lean * cfg.waistLeanShare)) * waist.base
	end
	if neck then
		local torsoLean = lean * (1 + cfg.waistLeanShare)
		out.Neck = rotInParent(neck.c0, CFrame.Angles(0, 0, -torsoLean * cfg.headStabilize)) * neck.base
	end

	return {
		transforms = out,
		debug = {
			weight = w,
			lean = lean,
			leanTarget = leanTarget,
			yawRate = yawRate,
			drop = state.drop,
			groundRef = groundRef,
			legs = legDebug,
		},
	}
end

return Solver
