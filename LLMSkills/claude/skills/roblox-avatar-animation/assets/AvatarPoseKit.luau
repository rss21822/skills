-- AvatarPoseKit: helpers for procedural pose layers on Roblox R15 player avatars.
--
-- A "pose" is { [jointName] = CFrame } holding joint Transforms (the value you write to Motor6D.Transform /
-- AnimationConstraint.Transform). "joints" is { [jointName] = joint } where a joint is a Motor6D, an
-- AnimationConstraint (Server Authority avatars), or an offline table { C0 = CFrame, C1 = CFrame, Part1 = { Size = Vector3 } }.
-- Every function below is pure (no Instance writes) except Kit.floorClearance, which raycasts.
-- All heights are in the HumanoidRootPart's space (the Root joint's Part0), so they do not depend on where the body is.
--
-- Origin: SpinOut anim-elite (2026-09-25). Measured on R15 blocky and scaled avatars; see references/pose-layer.md.
local Kit = {}

Kit.LEG_JOINTS = table.freeze({ "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle" })
Kit.R15_JOINTS = table.freeze({
	"Root", "Waist", "Neck",
	"LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow", "RightWrist",
	"LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle",
})
-- The 360 deg/s joint budget used for every grounded hand-off (fast enough to follow the Animator, slow enough
-- that no joint ever pops in one frame).
Kit.DEFAULT_RATE = math.rad(360)

local function finite(x)
	return type(x) == "number" and x == x and math.abs(x) < math.huge
end
Kit.finite = finite

function Kit.smoothstep(t)
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- Frame-rate independent exponential blend factor for a time constant tau (seconds).
function Kit.expAlpha(dt, tau)
	if tau <= 0 then return 1 end
	return 1 - math.exp(-math.max(dt, 0) / tau)
end

---------------------------------------------------------------- joints

-- Motor6D (C0 / C1 / Part1) and AnimationConstraint (Attachment0 / Attachment1) in one shape:
-- part1 = part0 * c0 * Transform * c1:Inverse().
function Kit.jointData(joint)
	if not joint then return nil end
	if (typeof(joint) == "Instance" and joint:IsA("Motor6D")) or (type(joint) == "table" and joint.C0 and joint.C1) then
		return { c0 = joint.C0, c1 = joint.C1, part1 = joint.Part1 }
	end
	local a, b = joint.Attachment0, joint.Attachment1
	if a and b then return { c0 = a.CFrame, c1 = b.CFrame, part1 = b.Parent } end
	return nil
end

-- Every animatable joint of a character by name. When a rig has both (Server Authority keeps the Motor6D but animates
-- the AnimationConstraint), the AnimationConstraint wins because that is the one the Animator drives.
function Kit.collectJoints(character)
	local joints = {}
	for _, d in character:GetDescendants() do
		if d:IsA("AnimationConstraint") then
			joints[d.Name] = d
		elseif d:IsA("Motor6D") and not joints[d.Name] then
			joints[d.Name] = d
		end
	end
	return joints
end

function Kit.rootName(joints)
	return joints.Root and "Root" or (joints.RootJoint and "RootJoint") or nil
end

---------------------------------------------------------------- feet

-- Lowest Y of an oriented box (a tilted foot's corner, not its centre).
function Kit.boxBottom(cf, size)
	return cf.Y - (math.abs(cf.RightVector.Y) * size.X + math.abs(cf.UpVector.Y) * size.Y + math.abs(cf.LookVector.Y) * size.Z) * 0.5
end

-- Foot part CFrame and size in root-part space for this pose (missing pose entries = identity = the rig's bind pose).
function Kit.footFrame(pose, joints, side)
	local rootName = Kit.rootName(joints)
	local root = rootName and Kit.jointData(joints[rootName])
	if not root then return nil end
	local cf = root.c0 * (pose[rootName] or CFrame.identity) * root.c1:Inverse()
	local size
	for _, suffix in { "Hip", "Knee", "Ankle" } do
		local frame = Kit.jointData(joints[side .. suffix])
		if not frame then return nil end
		cf = cf * frame.c0 * (pose[side .. suffix] or CFrame.identity) * frame.c1:Inverse()
		size = frame.part1 and frame.part1.Size
	end
	if not size then return nil end
	return cf, size
end

-- Lowest point of the foot (sole corner) and the foot centre, root-part space.
function Kit.soleLow(pose, joints, side)
	local cf, size = Kit.footFrame(pose, joints, side)
	if not cf then return nil end
	return Kit.boxBottom(cf, size), cf.Position
end

-- The sole height of this avatar standing in its bind pose. This is "the floor" in root space for a standing body:
-- use it instead of a constant, because body scale, package and HipHeight all move it.
function Kit.neutralLow(joints)
	local l, r = Kit.soleLow({}, joints, "Left"), Kit.soleLow({}, joints, "Right")
	if not l or not r then return nil end
	return math.min(l, r)
end

function Kit.lowestSole(pose, joints)
	local l, r = Kit.soleLow(pose, joints, "Left"), Kit.soleLow(pose, joints, "Right")
	if not l or not r then return nil end
	if l <= r then return l, "Left" end
	return r, "Right"
end

-- Hip-to-ankle length along the bind pose (thigh + shin), studs.
function Kit.legLength(joints, side)
	local hip, knee, ankle = Kit.jointData(joints[side .. "Hip"]), Kit.jointData(joints[side .. "Knee"]), Kit.jointData(joints[side .. "Ankle"])
	if not hip or not knee or not ankle then return nil end
	return (hip.c1.Position - knee.c0.Position).Magnitude + (knee.c1.Position - ankle.c0.Position).Magnitude
end

---------------------------------------------------------------- root placement (vertical only)

-- Move the rendered body straight up/down by dy studs (root-part space) through the Root joint's Transform.
-- Never rotates a joint, never touches the physics root.
function Kit.shiftRootY(pose, joints, dy)
	local rootName = Kit.rootName(joints)
	local root = rootName and Kit.jointData(joints[rootName])
	if not root or math.abs(dy) < 1e-7 then return pose end
	local out = table.clone(pose)
	out[rootName] = CFrame.new(root.c0:VectorToObjectSpace(Vector3.new(0, dy, 0))) * (pose[rootName] or CFrame.identity)
	return out
end

-- Put the lower sole exactly at targetLow (default: this avatar's standing sole height). Raises or lowers.
-- Use for poses with both feet on the ground (idle, stops, landings, stumbles, crouches).
function Kit.groundLowest(pose, joints, targetLow)
	targetLow = targetLow or Kit.neutralLow(joints)
	local low = Kit.lowestSole(pose, joints)
	if not low or not targetLow then return pose end
	return Kit.shiftRootY(pose, joints, targetLow - low)
end

-- Raise-only guard: if the lower sole is below minLow, lift the body until it is not. Never lowers a clear pose.
-- Use as the last write of a frame and while airborne (with minLow from Kit.floorClearance).
function Kit.raiseLowest(pose, joints, minLow)
	local low = Kit.lowestSole(pose, joints)
	if not low or not minLow or low >= minLow then return pose end
	return Kit.shiftRootY(pose, joints, minLow - low)
end

---------------------------------------------------------------- two-bone leg IK

-- Move one foot so its sole's lowest point reaches targetLow (root-part space Y), by bending the knee, swinging the hip
-- minimally and counter-rotating the ankle so the foot keeps its world orientation. The foot moves straight up/down.
-- Soft IK when extending: within softFraction * leg length of full extension the reach eases in exponentially, so the
-- knee never snaps straight in one frame (the singularity at full extension); the foot then stops up to
-- legLength * softFraction / e short of the target.
-- Assumes the R15 knee convention: Knee Transform rotation about -X flexes the knee.
function Kit.reachFoot(pose, joints, side, targetLow, softFraction)
	softFraction = softFraction or 0.05
	local rootName = Kit.rootName(joints)
	local root = rootName and Kit.jointData(joints[rootName])
	local hip, knee, ankle = Kit.jointData(joints[side .. "Hip"]), Kit.jointData(joints[side .. "Knee"]), Kit.jointData(joints[side .. "Ankle"])
	if not root or not hip or not knee or not ankle then return pose end
	local out = pose
	for _ = 1, 6 do
		local low = Kit.soleLow(out, joints, side)
		if not low then return pose end
		local dy = targetLow - low
		if math.abs(dy) < 1e-5 then break end
		local hipT = out[side .. "Hip"] or CFrame.identity
		local kneeT = out[side .. "Knee"] or CFrame.identity
		local ankleT = out[side .. "Ankle"] or CFrame.identity
		local hipBase = root.c0 * (out[rootName] or CFrame.identity) * root.c1:Inverse() * hip.c0
		local hipFrame = hipBase * hipT
		local kneeFrame = hipFrame * hip.c1:Inverse() * knee.c0 * kneeT
		local ankleBase = kneeFrame * knee.c1:Inverse() * ankle.c0
		local H, K, A = hipFrame.Position, kneeFrame.Position, ankleBase.Position
		local thigh, shin = (K - H).Magnitude, (A - K).Magnitude
		if thigh < 1e-4 or shin < 1e-4 then return pose end
		local target = A + Vector3.new(0, dy, 0)
		local function bend(reach)
			local c = math.clamp((thigh * thigh + shin * shin - reach * reach) / (2 * thigh * shin), -1, 1)
			return math.pi - math.acos(c)
		end
		local full, soft = thigh + shin, softFraction * (thigh + shin)
		local current = (A - H).Magnitude
		local reach = (target - H).Magnitude
		local softened = soft > 0 and reach > current and reach > full - soft
		if softened then
			reach = math.max(current, full - soft * math.exp(-(reach - (full - soft)) / soft))
		end
		reach = math.min(reach, full)
		local flex = bend(reach) - bend(current)
		local bent = K + CFrame.fromAxisAngle(kneeFrame.RightVector, -flex):VectorToWorldSpace(A - K)
		local from, to = (bent - H).Unit, (target - H).Unit
		local axis = from:Cross(to)
		local swing = CFrame.identity
		if axis.Magnitude > 1e-9 then
			-- atan2, not acos: acos rounds small float32 angles to ~0.02 degree steps
			swing = CFrame.fromAxisAngle(axis.Unit, math.atan2(axis.Magnitude, from:Dot(to)))
		end
		local newHipFrame = CFrame.new(H) * swing * CFrame.new(-H) * hipFrame
		local newHipT = hipBase:Inverse() * newHipFrame
		local newKneeT = kneeT * CFrame.Angles(-flex, 0, 0)
		local newAnkleBase = newHipFrame * hip.c1:Inverse() * knee.c0 * newKneeT * knee.c1:Inverse() * ankle.c0
		out = table.clone(out)
		out[side .. "Hip"] = newHipT
		out[side .. "Knee"] = newKneeT
		out[side .. "Ankle"] = CFrame.new(ankleT.Position) * (newAnkleBase.Rotation:Inverse() * ankleBase.Rotation * ankleT.Rotation)
		-- A softened reach intentionally stops short; iterating would swing the leg around an arc.
		if softened then break end
	end
	return out
end

---------------------------------------------------------------- uneven ground (slopes, stairs)

-- Fit both feet to their own floor heights (root-part space Y of the ground under each foot, e.g. from
-- Kit.floorUnderFeet). The lower foot is planted on its floor; the other foot keeps its lift above the lower one
-- (a swinging foot stays lifted by the same amount above ITS floor). The pelvis moves just enough for the planted
-- target, then the higher foot is raised with two-bone IK. weight (0..1) blends the fit in/out (take-off, landing).
-- opts.keepFlight = true measures lift from the standing sole height instead, so a run cycle's flight phase (both
-- feet up) stays in the air; the default plants the lower foot every grounded frame (walks, idles, skating).
-- opts: maxDrop (studs the pelvis may sink below the authored height, default 0.6 x leg length), maxRise (default
--       0.3 x leg length), liftFade (lift at which a swinging foot stops being pulled down, default 0.32 x leg length),
--       maxRaise (the most a foot is raised above its animated height by IK, default 0.55 x leg length (~135 degrees of knee flex); raising more
--       folds the knee toward 160-180 degrees and the leg flips), soft (IK soft fraction).
--       Defaults scale with the avatar so small and tall bodies behave the same.
-- Feed it floor heights that change smoothly (Kit.smoothFloor): the floor under a moving foot jumps a whole step at an
-- edge, and fitting that in one frame snaps the knee.
function Kit.fitFeetToFloor(pose, joints, floorLeft, floorRight, weight, opts)
	opts = opts or {}
	weight = math.clamp(weight or 1, 0, 1)
	if weight <= 1e-4 then return pose end
	local lowL, lowR = Kit.soleLow(pose, joints, "Left"), Kit.soleLow(pose, joints, "Right")
	local neutral = Kit.neutralLow(joints)
	if not lowL or not lowR or not neutral then return pose end
	floorLeft, floorRight = floorLeft or neutral, floorRight or neutral
	-- authored lift: above the lower foot (default) or above flat ground (keepFlight; neutral = standing sole height)
	local reference = opts.keepFlight and neutral or math.min(lowL, lowR)
	local liftL, liftR = math.max(lowL - reference, 0), math.max(lowR - reference, 0)
	local leg = Kit.legLength(joints, "Left") or 2
	local fade = opts.liftFade or 0.32 * leg
	-- feet high in their swing are not pulled to the floor (only lifted if the floor rises into them)
	local stickL = 1 - Kit.smoothstep(liftL / fade)
	local stickR = 1 - Kit.smoothstep(liftR / fade)
	local targetL, targetR = floorLeft + liftL, floorRight + liftR
	-- pelvis: drop (or rise) by the smaller need so that foot lands exactly; the other foot is then raised by IK.
	-- A swinging foot (stick ~ 0) never pulls the pelvis down.
	local function effective(need, stick) return need > 0 and need or need * stick end
	local dy = math.min(effective(targetL - lowL, stickL), effective(targetR - lowR, stickR))
	dy = math.clamp(dy, -(opts.maxDrop or 0.6 * leg), opts.maxRise or 0.3 * leg) * weight
	local out = Kit.shiftRootY(pose, joints, dy)
	local maxRaise = opts.maxRaise or 0.55 * leg
	for _, side in { "Left", "Right" } do
		local low = Kit.soleLow(out, joints, side)
		local target = side == "Left" and targetL or targetR
		local stick = side == "Left" and stickL or stickR
		local animated = (side == "Left" and lowL or lowR) + dy
		local want = math.min(low + (target - low) * weight, animated + maxRaise)
		-- raise into a rising floor always; pull down onto the floor only while the foot is planted (stick)
		if want > low + 1e-4 then
			out = Kit.reachFoot(out, joints, side, want, opts.soft)
		elseif want < low - 1e-4 and stick > 1e-3 then
			out = Kit.reachFoot(out, joints, side, low + (want - low) * stick, opts.soft)
		end
	end
	return out
end

-- Move a tracked floor height toward a new measurement at no more than `rate` studs/s (default 12), so a foot crossing a
-- step edge rises/drops over a few frames instead of in one. Returns the smoothed height (nil resets).
function Kit.smoothFloor(previous, measured, dt, rate)
	if measured == nil then return nil end
	if previous == nil or dt <= 0 then return measured end
	local step = (rate or 12) * dt
	return previous + math.clamp(measured - previous, -step, step)
end

-- Runtime: floor height under each foot in root-part space (nil when no floor within reach), plus the hit normals.
-- Each foot casts two rays, at the toe and the heel, and stands on the higher hit: a foot across a step edge rests on
-- the upper step, not on the floor under its centre. The rays start at the root's height above the foot, not just
-- above the foot: a ray that starts inside a step or a slope never hits it and reports the floor far below.
function Kit.floorUnderFeet(character, root, pose, joints, params, reach)
	local Workspace = game:GetService("Workspace")
	reach = reach or 4
	local results = {}
	for _, side in { "Left", "Right" } do
		local footCf, size = Kit.footFrame(pose, joints, side)
		if footCf then
			local world = root.CFrame * footCf
			local best
			for _, along in { 0.4, -0.4 } do
				local point = world.Position + world.LookVector * (size.Z * along)
				local start = Vector3.new(point.X, root.Position.Y, point.Z)
				local hit = Workspace:Raycast(start, Vector3.new(0, -(root.Position.Y - point.Y + reach), 0), params)
				if hit and (not best or hit.Position.Y > best.Position.Y) then best = hit end
			end
			if best then
				results[side] = root.CFrame:PointToObjectSpace(best.Position).Y
				results[side .. "Normal"] = best.Normal
			end
		end
	end
	return results.Left, results.Right, results
end

---------------------------------------------------------------- rate limits and transitions

function Kit.angleBetween(a, b)
	local _, angle = a:ToObjectSpace(b):ToAxisAngle()
	angle = math.abs(angle)
	return math.min(angle, math.abs(2 * math.pi - angle))
end

-- Move from previous toward target by at most maxAngle radians of rotation (position follows the same fraction).
function Kit.limitRotation(previous, target, maxAngle)
	if not previous then return target end
	local angle = Kit.angleBetween(previous, target)
	if angle <= maxAngle or angle < 1e-9 then return target end
	return previous:Lerp(target, maxAngle / angle)
end

-- Rate-limit a CORRECTION (IK, contact fix) on top of motion you do not want to slow down: the rendered joint may move as
-- far as the uncorrected joint moved this frame, plus rate * dt. A correction that appears or disappears (overlay
-- entry/exit, a foot swap) then eases in/out instead of popping, while the live animation underneath is never delayed.
function Kit.carryLimit(renderedPrev, uncorrectedPrev, uncorrected, desired, dt, rate)
	if not renderedPrev or not uncorrectedPrev or dt <= 0 then return desired end
	local allowed = Kit.angleBetween(uncorrectedPrev, uncorrected) + (rate or Kit.DEFAULT_RATE) * dt
	local angle = Kit.angleBetween(renderedPrev, desired)
	if angle <= allowed then return desired end
	return renderedPrev:Lerp(desired, allowed / angle)
end

-- Angular and linear velocity of a joint between two frames (clamped), for carrying motion through a mode switch.
function Kit.jointVelocity(previous, current, dt, maxSpeed)
	if not previous or dt <= 0 then return nil end
	local delta = previous:ToObjectSpace(current)
	local axis, angle = delta:ToAxisAngle()
	maxSpeed = maxSpeed or Kit.DEFAULT_RATE
	return { axis = axis, speed = math.clamp(angle / dt, -maxSpeed, maxSpeed), position = delta.Position / dt }
end

-- Start pose for a blend that keeps the outgoing joint moving briefly instead of stopping it at the switch:
-- a cubic carry duration * t * (1 - t)^2 that is zero at both ends. Blend: Kit.carriedStart(...):Lerp(target, smoothstep(t)).
function Kit.carriedStart(from, velocity, elapsed, duration)
	if not velocity or duration <= 0 then return from end
	local t = math.clamp(elapsed / duration, 0, 1)
	local carry = duration * t * (1 - t) ^ 2
	local rotation = CFrame.identity
	if velocity.axis.Magnitude > 1e-7 and math.abs(velocity.speed * carry) > 1e-7 then
		rotation = CFrame.fromAxisAngle(velocity.axis, velocity.speed * carry)
	end
	return from * CFrame.new(velocity.position * carry) * rotation
end

---------------------------------------------------------------- springs

-- Critically-/under-damped 2nd-order spring (semi-implicit Euler, sub-stepped to <= 1/60 s so 30 fps and 144 fps agree).
-- params = { freq = rad/s, damping = ratio }. state[key] and state[key .. "V"] hold value and velocity.
function Kit.spring(state, key, target, params, dt)
	local x, v = state[key] or 0, state[key .. "V"] or 0
	if dt <= 0 then return x end
	local steps = math.max(1, math.ceil(dt * 60 - 1e-6))
	local h = dt / steps
	local w, z = params.freq, params.damping
	for _ = 1, steps do
		local a = w * w * (target - x) - 2 * z * w * v
		v += a * h
		x += v * h
	end
	state[key], state[key .. "V"] = x, v
	return x
end

---------------------------------------------------------------- floor while airborne (runtime only)

-- How far the root is above standing height over the floor right below it, predicted one physics step ahead
-- (Transforms written in PreSimulation are drawn after that step). nil when no floor within `reach` studs.
-- Hard landings compress the Humanoid below standing height by roughly 0.005 * fall speed (max ~0.4-0.5 stud);
-- allow that much sink so the prediction does not lift the body above the ice on impact.
-- Use: minLow = Kit.neutralLow(joints) - clearance, then Kit.raiseLowest(pose, joints, minLow).
function Kit.floorClearance(character, humanoid, root, dt, opts)
	opts = opts or {}
	local Workspace = game:GetService("Workspace")
	local params = opts.params or RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = opts.ignore or { character }
	local stand = (tonumber(humanoid.HipHeight) or 2) + root.Size.Y * 0.5
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(stand + (opts.reach or 4)), 0), params)
	if not hit then return nil end
	local measured = (root.Position.Y - hit.Position.Y) - stand
	local vy = root.AssemblyLinearVelocity.Y
	local deepest = measured >= 0 and -math.min(opts.sinkMax or 0.4, math.max(-vy, 0) * (opts.sinkPerSpeed or 0.005)) or measured
	return math.max(measured + vy * (dt or 0), deepest)
end

---------------------------------------------------------------- physics-linked secondary motion

-- Adds to an already-rendered pose, from the body's velocity only (works identically for the local player, NPCs and
-- remote players, and offline):
--   bank  : lean into the curve by atan(gain * v * omega / g), pivoting about the planted (lower) sole, and then
--           restore that sole's exact height (no sinking, no floating);
--   pitch : chest forward under acceleration, back under deceleration / knockback (Waist only, legs untouched);
--   head  : cancel part of the added bank (eyes level) and lead the turn (gaze leads the body);
--   arms  : counterbalance (outer arm lifts, inner arm tucks).
-- Authored lean is respected: only the difference to the target bank is added (Secondary.extraBank).
local Secondary = {}
Kit.Secondary = Secondary

Secondary.DEFAULTS = table.freeze({
	bankGain = 1.0, bankMax = math.rad(18), bankMinSpeed = 6, bankSpeedSpan = 14,
	pitchGain = 1.0, pitchForwardMax = math.rad(9), pitchBackMax = math.rad(8),
	headLevel = 0.55, headLevelMax = math.rad(15), headLead = 0.30, headLeadMax = math.rad(18),
	chestLead = 0.12, chestLeadMax = math.rad(8), armBalance = 0.30,
	pivotTie = 0.05, omegaMax = 6, accelMax = 420,
	bankSpring = table.freeze({ freq = 7.5, damping = 0.72 }),
	pitchSpring = table.freeze({ freq = 9.0, damping = 0.80 }),
	headSpring = table.freeze({ freq = 11.0, damping = 0.90 }),
	weightTau = 0.14, signalTau = 0.06,
})
Secondary.FULL = table.freeze({ bank = 1, pitch = 1, head = 1, arms = 1 })
Secondary.OFF = table.freeze({ bank = 0, pitch = 0, head = 0, arms = 0 })

function Secondary.new(params)
	return { p = params or Secondary.DEFAULTS, bank = 0, pitch = 0, headYaw = 0, chestYaw = 0, omega = 0, along = 0,
		wBank = 0, wPitch = 0, wHead = 0, wArms = 0 }
end

-- Signed angle about +Y from a to b (counter-clockwise seen from above = turning LEFT = positive).
function Secondary.signedYaw(a, b)
	return math.atan2(a.Z * b.X - a.X * b.Z, a.X * b.X + a.Z * b.Z)
end

-- Measure turn rate (omega) and along-track acceleration from the horizontal velocity. Call once per frame.
function Secondary.measure(state, velocity, dt)
	local p = state.p
	dt = finite(dt) and dt or 0
	if dt <= 0 then return state end
	if dt > 0.1 then -- a hitch (load, teleport): forget the old velocity instead of reporting a huge acceleration
		state.dir, state.speed = nil, nil
		dt = 0.1
	end
	local flat = finite(velocity.X) and finite(velocity.Z) and Vector3.new(velocity.X, 0, velocity.Z) or Vector3.zero
	local speed = flat.Magnitude
	local k = Kit.expAlpha(dt, p.signalTau)
	local omega = 0
	if speed > p.bankMinSpeed * 0.5 and state.dir then
		omega = math.clamp(Secondary.signedYaw(state.dir, flat / speed) / dt, -p.omegaMax, p.omegaMax)
	end
	local along = state.speed and math.clamp((speed - state.speed) / dt, -p.accelMax, p.accelMax) or 0
	state.omega += (omega - state.omega) * k
	state.along += (along - state.along) * k
	state.dir = speed > 1e-3 and flat / speed or state.dir
	state.speed = speed
	return state
end

-- Chase the targets with springs; weights (0..1 per channel) fade the layer per animation mode
-- (e.g. OFF during emotes, spins and airborne tricks that own the whole body).
function Secondary.settle(state, dt, gravity, weights)
	local p = state.p
	dt = finite(dt) and math.clamp(dt, 0, 0.1) or 0
	if dt <= 0 then return state end
	gravity = finite(gravity) and gravity > 1 and gravity or 196.2
	local speed = state.speed or 0
	local fade = Kit.smoothstep((speed - p.bankMinSpeed) / p.bankSpeedSpan)
	local lateral = speed * state.omega
	local bankTarget = math.clamp(math.atan(lateral * p.bankGain / gravity), -p.bankMax, p.bankMax) * fade
	local pitchTarget = math.clamp(-math.atan(state.along * p.pitchGain / gravity), -p.pitchForwardMax, p.pitchBackMax)
	local lead = math.clamp(state.omega * p.headLead, -p.headLeadMax, p.headLeadMax)
	local chest = math.clamp(state.omega * p.chestLead, -p.chestLeadMax, p.chestLeadMax)
	Kit.spring(state, "bank", bankTarget, p.bankSpring, dt)
	Kit.spring(state, "pitch", pitchTarget, p.pitchSpring, dt)
	Kit.spring(state, "headYaw", lead * fade, p.headSpring, dt)
	Kit.spring(state, "chestYaw", chest * fade, p.headSpring, dt)
	weights = weights or Secondary.FULL
	local kw = Kit.expAlpha(dt, p.weightTau)
	state.wBank += (weights.bank - state.wBank) * kw
	state.wPitch += (weights.pitch - state.wPitch) * kw
	state.wHead += (weights.head - state.wHead) * kw
	state.wArms += (weights.arms - state.wArms) * kw
	state.active = math.max(state.wBank, state.wPitch, state.wHead, state.wArms) > 1e-3
	return state
end

function Secondary.update(state, velocity, dt, gravity, weights)
	Secondary.measure(state, velocity, dt)
	return Secondary.settle(state, dt, gravity, weights)
end

-- Bank to add on top of an authored roll in the same direction (continuous across zero).
function Secondary.extraBank(target, authored)
	if target >= 0 then return target - math.clamp(authored, 0, target) end
	return target - math.clamp(authored, target, 0)
end

-- Returns only the joints it changes: { [name] = CFrame }. Apply them over the pose you rendered this frame.
function Secondary.apply(state, pose, joints)
	local p = state.p
	local out = {}
	if not state.active then return out end
	local rootName = Kit.rootName(joints)
	local rootPose = rootName and pose[rootName]
	if rootName and rootPose then
		local root = Kit.jointData(joints[rootName])
		local _, _, authoredRoll = rootPose:ToEulerAnglesYXZ()
		local extra = Secondary.extraBank(state.bank, authoredRoll) * state.wBank
		if root and math.abs(extra) > 1e-5 then
			local lowL, centerL = Kit.soleLow(pose, joints, "Left")
			local lowR, centerR = Kit.soleLow(pose, joints, "Right")
			local pivot
			if lowL and lowR then
				-- the planted (lower) sole is the pivot; when both are down, the inside one (the side the body falls to)
				local insideLeft = extra > 0
				local lowIn, lowOut = insideLeft and lowL or lowR, insideLeft and lowR or lowL
				local cIn, cOut = insideLeft and centerL or centerR, insideLeft and centerR or centerL
				pivot = lowOut < lowIn - p.pivotTie and cOut or cIn
			else
				pivot = root.c0.Position - Vector3.new(0, 3, 0)
			end
			local turn = CFrame.new(pivot) * CFrame.Angles(0, 0, extra) * CFrame.new(-pivot)
			local banked = root.c0:Inverse() * turn * root.c0 * rootPose
			if lowL and lowR then
				local trial = table.clone(pose)
				trial[rootName] = banked
				local after = Kit.lowestSole(trial, joints)
				if after then
					local shift = math.min(lowL, lowR) - after
					if math.abs(shift) > 1e-5 then
						banked = root.c0:Inverse() * CFrame.new(0, shift, 0) * root.c0 * banked
					end
				end
			end
			out[rootName] = banked
		end
		local neck = pose.Neck
		if neck then
			local level = math.clamp(-p.headLevel * extra, -p.headLevelMax, p.headLevelMax)
			local yaw = state.headYaw * state.wHead
			if math.abs(level) > 1e-5 or math.abs(yaw) > 1e-5 then
				out.Neck = CFrame.Angles(0, yaw, level) * neck
			end
		end
		local arms = extra * p.armBalance * state.wArms
		if math.abs(arms) > 1e-5 then
			for _, name in { "LeftShoulder", "RightShoulder" } do
				local cf = pose[name]
				if cf then out[name] = CFrame.Angles(0, 0, arms) * cf end
			end
		end
	end
	local waist = pose.Waist
	if waist then
		local pitch = state.pitch * state.wPitch
		local yaw = state.chestYaw * state.wHead
		if math.abs(pitch) > 1e-5 or math.abs(yaw) > 1e-5 then
			out.Waist = CFrame.Angles(pitch, yaw, 0) * waist
		end
	end
	return out
end

return table.freeze(Kit)
