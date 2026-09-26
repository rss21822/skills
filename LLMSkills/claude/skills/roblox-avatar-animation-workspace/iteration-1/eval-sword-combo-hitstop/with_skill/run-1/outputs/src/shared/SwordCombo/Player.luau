-- SwordCombo/Player: pure per-character state machine for the 3-strike sword combo.
-- No Instances, no RunService: Player.step(state, dt, base, speed) takes the Animator's pose for this frame (base) and
-- returns the pose to draw (or nil = let Animate draw). The runtime layer (SwordCombo/Layer) and the offline test
-- (tests/test_sword_combo.luau) call exactly this code.
--
--   * Pose clock vs real time: the strike keys run on s.t (the pose clock). Hit-stop freezes ONLY this clock for
--     strike.hitStop seconds of real time (plus a tiny decaying shake). Physics, the Humanoid, input and the Animator
--     keep running; nothing here touches them.
--   * Hand-offs (Animate -> combo, strike -> strike, combo -> Animate) start from the rendered pose, carry its velocity
--     (Kit.carriedStart) and are rate-limited as a CORRECTION on top of the authored motion (Kit.carryLimit: authored
--     motion this frame + 360 deg/s * dt). The authored swing itself is fast on purpose and is never slowed.
--   * Feet: planted targets in HumanoidRootPart space, legs solved by two-bone IK every frame, so the pelvis can coil,
--     dip and rise without any foot sliding. Feet only move in authored steps (lifted arcs). While the body is walking,
--     the legs and Root hand back to the Animator (upper body keeps the combo).
local Kit = require(script.Parent.AvatarPoseKit)
local Spec = require(script.Parent.Spec)

local Player = {}

Player.LEG_JOINTS = { "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" }
Player.HIT_LATE = 0.05 -- a hit reported this long after the contact frame still freezes (network / query latency)
Player.MOVE_SPEED0 = 2 -- studs/s: legs start handing back to the Animator's walk above this speed
Player.MOVE_SPAN = 4
Player.LEG_TAU = 0.10
Player.LEG_SETTLE = 0.08 -- s, end of the exit: legs from IK to the Animator's joint values
Player.REFERENCE_LEG = 1.883 -- leg length of the measured rig (rig-r15.json); offsets scale with the body

---------------------------------------------------------------- two-bone leg IK to a full foot frame

-- Solve Hip / Knee / Ankle Transforms so that the foot part lands exactly on footTarget (HumanoidRootPart space),
-- given the Root Transform. Knee points along the foot's look direction. Returns hipT, kneeT, ankleT, error (studs).
function Player.solveLeg(joints, rootT, side, footTarget)
	local root = Kit.jointData(joints.Root)
	local hip = Kit.jointData(joints[side .. "Hip"])
	local knee = Kit.jointData(joints[side .. "Knee"])
	local ankle = Kit.jointData(joints[side .. "Ankle"])
	local hipBase = root.c0 * rootT * root.c1:Inverse() * hip.c0
	local H = hipBase.Position
	local P = (footTarget * ankle.c1).Position -- ankle joint position (Transform only rotates about it)
	local v = hipBase:VectorToObjectSpace(P - H)
	local link = hip.c1:Inverse() * knee.c0 -- hip joint -> knee joint (thigh)
	local d2 = (knee.c1:Inverse() * ankle.c0).Position -- knee joint -> ankle joint (shin)
	local function legVec(theta)
		return link.Position + link:VectorToWorldSpace(CFrame.Angles(theta, 0, 0):VectorToWorldSpace(d2))
	end
	-- knee flex is -X (R15). |legVec| shrinks monotonically from straight (0) to -150 deg: bisect.
	local lo, hi = math.rad(-150), 0
	local maxLen, minLen = legVec(hi).Magnitude, legVec(lo).Magnitude
	local want = math.clamp(v.Magnitude, minLen, maxLen * 0.999)
	for _ = 1, 40 do
		local mid = (lo + hi) * 0.5
		if legVec(mid).Magnitude > want then hi = mid else lo = mid end
	end
	local theta = (lo + hi) * 0.5
	local u = legVec(theta)
	-- swing the leg onto the target direction (minimal rotation), then twist about it so the knee faces the toe
	local a0, a1 = u.Unit, v.Unit
	local axis = a0:Cross(a1)
	local swing = CFrame.identity
	if axis.Magnitude > 1e-9 then swing = CFrame.fromAxisAngle(axis.Unit, math.atan2(axis.Magnitude, a0:Dot(a1))) end
	local thighFwd = swing:VectorToWorldSpace(link:VectorToWorldSpace(Vector3.new(0, 0, -1)))
	local pole = hipBase:VectorToObjectSpace(footTarget.LookVector)
	local f = thighFwd - a1 * thighFwd:Dot(a1)
	local p = pole - a1 * pole:Dot(a1)
	local twist = CFrame.identity
	if f.Magnitude > 1e-6 and p.Magnitude > 1e-6 then
		twist = CFrame.fromAxisAngle(a1, math.atan2(a1:Dot(f:Cross(p)), f:Dot(p)))
	end
	local hipT = twist * swing
	local kneeT = CFrame.Angles(theta, 0, 0)
	local ankleFrame = hipBase * hipT * link * kneeT * (knee.c1:Inverse() * ankle.c0)
	local ankleT = (ankleFrame:Inverse() * footTarget * ankle.c1).Rotation
	return hipT, kneeT, ankleT, (ankleFrame.Position - P).Magnitude
end

---------------------------------------------------------------- state

local function footFrames(pose, joints)
	return { Left = (Kit.footFrame(pose, joints, "Left")), Right = (Kit.footFrame(pose, joints, "Right")) }
end

function Player.new(joints, opts)
	opts = opts or {}
	local scale = (Kit.legLength(joints, "Left") or Player.REFERENCE_LEG) / Player.REFERENCE_LEG
	local bind = footFrames({}, joints)
	local stance = {}
	for _, side in { "Left", "Right" } do
		local o = Spec.STANCE[side]
		stance[side] = CFrame.new(bind[side].Position + Vector3.new(o.dx, 0, o.dz) * scale)
			* CFrame.Angles(0, math.rad(o.yaw), 0) * bind[side].Rotation
	end
	return {
		joints = joints, scale = scale, neutral = Kit.neutralLow(joints), stance = stance,
		active = false, exiting = false, startPending = false, strike = 0, t = 0,
		freeze = 0, freezeTotal = 0, pendingHit = false, hitDone = false, queued = false,
		autoHit = opts.autoHit == true, -- preview: every strike "hits" (Studio / offline); gameplay leaves it false
		hitTest = opts.hitTest, -- optional function(strikeIndex) -> bool, called on the contact frame
		legW = 1, events = {},
	}
end

-- Attack input. Starts strike 1 when idle, or buffers the next strike inside the input window. Returns accepted.
function Player.attack(s)
	if not s.active or s.exiting then
		s.startPending = true
		return true
	end
	local strike = Spec.STRIKES[s.strike]
	if s.strike < #Spec.STRIKES and not s.queued and s.t >= strike.inputOpen then
		s.queued = true
		return true
	end
	return false
end

-- Gameplay confirmed a hit for the current strike (before the contact frame = freeze exactly on it; up to HIT_LATE
-- after = freeze now).
function Player.reportHit(s)
	if not s.active or s.exiting or s.hitDone then return false end
	local strike = Spec.STRIKES[s.strike]
	if s.t > strike.contact + Player.HIT_LATE then return false end
	s.pendingHit = true
	return true
end

local function emit(s, kind, value) table.insert(s.events, { kind = kind, value = value }) end

local function snapshotVelocity(s, dt)
	local vel = {}
	if s.rendered and s.renderedPrev then
		for name, cf in s.rendered do
			vel[name] = Kit.jointVelocity(s.renderedPrev[name] or cf, cf, dt, math.rad(720))
		end
	end
	return vel
end

local function beginStrike(s, index, base, carryT, dt)
	local strike = Spec.STRIKES[index]
	local from = s.rendered or base
	local fromFeet = footFrames(from, s.joints)
	s.blend = { from = table.clone(from), velocity = snapshotVelocity(s, dt), elapsed = 0,
		fade = (s.active and not s.exiting) and Spec.CHAIN_FADE or Spec.ENTER_FADE }
	if not s.active or s.exiting then
		-- step into the stance from wherever the feet are now (lifted arcs, never a slide)
		s.feet = {}
		for side, plan in Spec.STANCE.enterStep do
			s.feet[side] = { planted = fromFeet[side], step = { from = fromFeet[side], to = s.stance[side],
				t0 = plan.from, t1 = plan.to, lift = plan.lift * s.scale } }
		end
	end
	if strike.step then
		local side = strike.step.foot
		local now = s.feet[side].step and s.feet[side].step.to or s.feet[side].planted
		s.feet[side].step = { from = now, to = CFrame.new(0, 0, strike.step.dz * s.scale) * now,
			t0 = strike.step.from, t1 = strike.step.to, lift = strike.step.lift * s.scale }
	end
	s.active, s.exiting, s.startPending = true, false, false
	s.strike, s.t = index, carryT or 0
	s.freeze, s.freezeTotal, s.hitDone, s.queued = 0, 0, false, false
	s.pendingHit = s.autoHit
	s.handoff = true
	emit(s, "strike", index)
end

local function beginExit(s, base, dt)
	s.exiting, s.exitElapsed = true, 0
	s.blend = { from = table.clone(s.rendered or base), velocity = snapshotVelocity(s, dt), elapsed = 0, fade = Spec.EXIT_FADE }
	s.handoff = true
	for side, plan in Spec.STANCE.exitStep do
		local f = s.feet[side]
		local now = f.step and f.step.to or f.planted
		f.planted, f.step = now, { from = now, toBase = true, t0 = plan.from, t1 = plan.to, lift = plan.lift * s.scale }
	end
	emit(s, "exit", s.strike)
end

-- Foot target at clock c: planted, or on a lifted arc between two frames (sin lift; horizontal travel only mid-air).
local function footTarget(f, c, baseFoot)
	local step = f.step
	if not step then return f.planted end
	local to = step.toBase and baseFoot or step.to
	if c <= step.t0 then return step.from end
	if c >= step.t1 then
		if not step.toBase then f.planted, f.step = to, nil end
		return to
	end
	-- lift off vertically, travel while up, set down vertically: the foot never moves sideways near the floor
	local u = math.clamp((c - step.t0) / (step.t1 - step.t0), 0, 1)
	local along = Kit.smoothstep((u - 0.15) / 0.7)
	return step.from:Lerp(to, along) + Vector3.new(0, step.lift * math.sin(math.pi * u), 0)
end

-- Advance the pose clock by dt of real time, honouring hit-stop. Returns nothing; updates s.t / s.freeze / events.
local function advance(s, dt)
	local strike = Spec.STRIKES[s.strike]
	local remaining = dt
	if s.freeze > 0 then
		local c = math.min(remaining, s.freeze)
		s.freeze -= c
		remaining -= c
	end
	if remaining <= 0 then return end
	local t0, t1 = s.t, s.t + remaining
	if not s.hitDone and t0 < strike.contact and t1 >= strike.contact then
		local hit = s.pendingHit
		if not hit and s.hitTest then hit = s.hitTest(s.strike) == true end
		emit(s, "contact", s.strike)
		if hit then
			s.hitDone, s.pendingHit = true, false
			s.freeze, s.freezeTotal = strike.hitStop, strike.hitStop
			emit(s, "hit", s.strike)
			local over = t1 - strike.contact
			local c = math.min(over, s.freeze)
			s.freeze -= c
			s.t = strike.contact + (over - c)
			return
		end
	elseif s.pendingHit and not s.hitDone and t0 >= strike.contact then
		-- late confirmation (<= HIT_LATE): freeze where we are
		s.hitDone, s.pendingHit = true, false
		s.freeze, s.freezeTotal = strike.hitStop, strike.hitStop
		emit(s, "hit", s.strike)
		local c = math.min(remaining, s.freeze)
		s.freeze -= c
		s.t = t0 + (remaining - c)
		return
	end
	s.t = t1
end

local function shaken(s, target)
	if s.freeze <= 0 or s.freezeTotal <= 0 then return target end
	local strike = Spec.STRIKES[s.strike]
	local tau = s.freezeTotal - s.freeze
	local sign = (math.floor(tau * 60) % 2 == 0) and 1 or -1
	local amp = math.rad(strike.shake) * (s.freeze / s.freezeTotal) * sign
	local out = table.clone(target)
	out.RightShoulder = target.RightShoulder * CFrame.Angles(amp, 0, 0)
	out.LeftShoulder = target.LeftShoulder * CFrame.Angles(amp * 0.6, 0, 0)
	out.Waist = target.Waist * CFrame.Angles(0, amp * 0.5, 0)
	return out
end

-- One frame. base = the Animator's pose this frame ({ [joint] = Transform }); speed = horizontal body speed (studs/s).
-- Returns the pose to write (every joint the combo owns), or nil when the combo is not drawing.
function Player.step(s, dt, base, speed)
	table.clear(s.events)
	dt = (Kit.finite(dt) and dt > 0) and math.min(dt, 0.1) or 0
	if s.startPending then beginStrike(s, 1, base, 0, dt) end
	if not s.active then return nil end

	-- 1. clocks, chaining, exit
	if s.exiting then
		s.exitElapsed += dt
	else
		advance(s, dt)
		local strike = Spec.STRIKES[s.strike]
		if s.queued and s.freeze <= 0 and s.t >= strike.chainAt then
			beginStrike(s, s.strike + 1, base, s.t - strike.chainAt, dt)
		elseif s.freeze <= 0 and s.t >= strike.duration then
			beginExit(s, base, dt)
		end
	end

	-- 2. target for Root + upper body
	local joints = s.joints
	local target
	if s.exiting then
		target = {}
		for _, name in Spec.UPPER do target[name] = base[name] or CFrame.identity end
	else
		local sample, dy = Spec.sample(s.strike, s.t)
		target = shaken(s, sample)
		local rootC0 = Kit.jointData(joints.Root).c0
		target.Root = CFrame.new(rootC0:VectorToObjectSpace(Vector3.new(0, dy * s.scale, 0))) * target.Root
	end

	-- 3. hand-off: carried blend from the rendered pose, then limit the correction to authored motion + 360 deg/s
	local blend = s.blend
	local rendered = {}
	local lagging = false
	if blend then blend.elapsed += dt end
	for _, name in Spec.UPPER do
		local goal = target[name]
		local desired = goal
		if blend and blend.elapsed < blend.fade and blend.from[name] then
			local a = Kit.smoothstep(blend.elapsed / blend.fade)
			desired = Kit.carriedStart(blend.from[name], blend.velocity[name], blend.elapsed, blend.fade):Lerp(goal, a)
		end
		local prev = s.rendered and s.rendered[name]
		-- first frame of a hand-off: the previous goal belongs to the old strike, so allow only the rate budget
		local prevGoal = s.handoff and goal or (s.target and s.target[name])
		local out = Kit.carryLimit(prev, prevGoal, goal, desired, dt, Spec.RATE)
		if Kit.angleBetween(out, goal) > 1e-4 or (out.Position - goal.Position).Magnitude > 1e-4 then lagging = true end
		rendered[name] = out
	end
	s.handoff = false
	if blend and blend.elapsed >= blend.fade and not lagging then s.blend = nil end

	-- 4. legs: IK to the planted / stepping foot targets (exact), handed to the Animator while walking
	local clock = s.exiting and s.exitElapsed or s.t
	local baseFeet = s.exiting and footFrames(base, joints) or nil
	for _, side in { "Left", "Right" } do
		local ft = footTarget(s.feet[side], clock, baseFeet and baseFeet[side])
		local h, k, a = Player.solveLeg(joints, rendered.Root, side, ft)
		rendered[side .. "Hip"], rendered[side .. "Knee"], rendered[side .. "Ankle"] = h, k, a
	end
	local legGoal = 1 - Kit.smoothstep(((speed or 0) - Player.MOVE_SPEED0) / Player.MOVE_SPAN)
	s.legW += (legGoal - s.legW) * Kit.expAlpha(dt, Player.LEG_TAU)
	local legW = s.legW
	if s.exiting then
		-- the feet stepped back to the Animator's foot frames and the Root has converged: close the residual
		-- joint-space gap (knee twist differences) over LEG_SETTLE, never while the pelvis is still moving
		legW = math.min(legW, 1 - Kit.smoothstep((s.exitElapsed - Spec.EXIT_FADE) / Player.LEG_SETTLE))
	end
	if legW < 1 then
		for _, name in Player.LEG_JOINTS do
			local b = base[name] or CFrame.identity
			rendered[name] = b:Lerp(rendered[name], legW)
		end
		if not s.exiting then
			-- walking: pelvis height/tilt back to the Animator too (upper body keeps the combo through the Waist)
			local b = base.Root or CFrame.identity
			rendered.Root = b:Lerp(rendered.Root, legW)
		end
	end

	-- 5. done?
	s.renderedPrev, s.rendered, s.target = s.rendered, rendered, target
	if s.exiting and s.exitElapsed >= Spec.EXIT_FADE + Player.LEG_SETTLE and not s.blend then
		local maxGap = 0
		for name, cf in rendered do
			local b = base[name] or CFrame.identity
			maxGap = math.max(maxGap, Kit.angleBetween(cf, b), (cf.Position - b.Position).Magnitude)
		end
		if maxGap < math.rad(0.05) then
			s.active, s.exiting, s.rendered, s.renderedPrev, s.target, s.blend, s.feet = false, false, nil, nil, nil, nil, nil
			emit(s, "done", 0)
			return nil
		end
	end
	return rendered
end

-- Seconds of pose clock the strike has left and whether the combo is drawing (for UI / gameplay gating).
function Player.status(s)
	return { active = s.active, strike = s.strike, t = s.t, frozen = s.freeze > 0, queued = s.queued, exiting = s.exiting }
end

return Player
