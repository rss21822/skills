-- TerrainPoseCore: the pure per-frame solver of the TerrainPose layer (no Instances, no services).
-- The runtime layer (TerrainPoseLayer) reads the Animator's pose and casts the rays this module asks for; everything
-- that decides the drawn pose happens here, so the offline Lune test runs exactly the same code as the game.
--
-- One frame of one body:
--   1. plan()   : where to sample the floor (toe + heel of each foot, plus a look-ahead point for the swinging foot),
--                 in HumanoidRootPart space. The runtime casts each one straight down from the root's height.
--   2. step()   : Animate's pose (base)
--                 -> secondary motion from the body's velocity (bank into turns, chest pitch on accel/brake, head level
--                    and leading, arm counterbalance; pivot on the planted foot)            [Kit.Secondary]
--                 -> terrain fit: each foot on its own floor, pelvis drops only as needed, the higher foot is raised
--                    with two-bone IK (slopes: no uphill foot in the ground; stairs: no foot hanging in the air)
--                                                                                          [Kit.fitFeetToFloor]
--                 -> airborne: never draw a foot below the floor one physics step ahead    [Kit.floorClearance result]
--                 -> correction rate limit: a joint may move as far as Animate moved it + 360 deg/s [Kit.carryLimit]
--                 -> safety net: the planted foot is never inside its floor (whole-body raise only, no rotation)
-- Presentation only: the result is written to joint Transforms. Physics, the HumanoidRootPart, input and replication
-- are never touched.
local Kit = require(script.Parent.AvatarPoseKit)

local Core = {}

-- Starting values for a human runner at Roblox speeds (WalkSpeed 16). Tune bank* with the game camera, then re-run the
-- offline test (it asserts the steady bank formula for whatever values are here).
local secondary = table.clone(Kit.Secondary.DEFAULTS)
secondary.bankGain = 1.4 -- 1.0 = physically correct lean atan(v*w/g); runners read better slightly exaggerated
secondary.bankMax = math.rad(20)
secondary.bankMinSpeed = 4 -- no lean when turning on the spot / walking slowly
secondary.bankSpeedSpan = 10 -- full lean from 14 stud/s (WalkSpeed 16 runs at full lean)
Core.SECONDARY = table.freeze(secondary)

Core.DEFAULTS = table.freeze({
	plantTau = 0.06, -- s: terrain fit fades in on landing / out on take-off
	activeTau = 0.12, -- s: whole layer fades out while suspended (climbing, seated, swimming, full-body tracks)
	correctionRate = Kit.DEFAULT_RATE, -- 360 deg/s on top of Animate's own motion (the quality bar: no joint pops)
	floorSlew = 0, -- studs/s (0 = off). Optional world-space slew of each foot's floor. Offline it made stairs WORSE
	-- (a planted toe crossing a step edge stays inside the step while the floor slews: stairs-up min -0.70 vs -0.27).
	floorSnap = 3, -- studs: bigger floor jumps (teleport, respawn, a cliff) are taken at once
	stepReach = 1.3, -- studs above standing height: stepping DOWN a stair / curb still counts as contact (the Humanoid
	-- is briefly airborne there; without this the fit would let go for 3-6 frames on every step down)
	pelvisTau = 0.07, -- s: pelvis height eases toward the terrain fit (see step)
	stepFallSpeed = 35, -- stud/s: ... unless falling faster than this (a real jump landing keeps the airborne clamp)
	lookahead = 0.12, -- s: the swinging foot also samples the floor this far ahead (clears stair risers / uphill)
	swingLiftStart = 0.05, -- studs above the planted foot where look-ahead starts to count
	swingLiftSpan = 0.25, -- ... and counts fully
	soft = 0.05, -- soft IK fraction of the leg length
	secondary = Core.SECONDARY,
	airWeights = table.freeze({ bank = 0.4, pitch = 0.4, head = 1, arms = 0.4 }),
})

local function finite(x)
	return type(x) == "number" and x == x and math.abs(x) < math.huge
end

function Core.newBody(joints, params)
	params = params or Core.DEFAULTS
	return {
		p = params,
		joints = joints,
		neutral = Kit.neutralLow(joints),
		secondary = Kit.Secondary.new(params.secondary),
		plantW = 1,
		activeW = 1,
		floorWorld = {}, -- slewed floor height per foot (world Y)
		prevBase = nil, -- Animate's pose last frame
		prevOut = nil, -- what we drew last frame
		debug = {},
	}
end

-- How far each foot is lifted above the lower one in Animate's pose (0 for the planted foot).
local function lifts(base, joints)
	local l, r = Kit.soleLow(base, joints, "Left"), Kit.soleLow(base, joints, "Right")
	if not l or not r then return 0, 0 end
	local low = math.min(l, r)
	return l - low, r - low
end

-- Floor sample points for this frame, in root space: { { side, kind = "toe" | "heel" | "ahead", point } }.
-- velocityRoot is the horizontal velocity in root space (studs/s). Rays must start at the root's height
-- (a ray started just above the foot begins inside a step or slope, never hits it and reports the floor below).
function Core.plan(body, base, velocityRoot)
	local p, joints = body.p, body.joints
	local samples = {}
	local liftL, liftR = lifts(base, joints)
	for _, side in { "Left", "Right" } do
		local cf, size = Kit.footFrame(base, joints, side)
		if cf then
			local toe = cf.Position + cf.LookVector * (size.Z * 0.4)
			local heel = cf.Position - cf.LookVector * (size.Z * 0.4)
			table.insert(samples, { side = side, kind = "toe", point = toe })
			table.insert(samples, { side = side, kind = "heel", point = heel })
			local lift = side == "Left" and liftL or liftR
			if lift > p.swingLiftStart and velocityRoot and p.lookahead > 0 then
				local v = Vector3.new(velocityRoot.X, 0, velocityRoot.Z)
				if v.Magnitude > 0.5 then
					table.insert(samples, { side = side, kind = "ahead", point = toe + v * p.lookahead })
				end
			end
		end
	end
	return samples
end

-- Turn cast results (heights[i] = root-space floor Y for samples[i], or nil = no floor within reach) into one floor
-- height per foot. A foot across a step edge stands on the higher of toe / heel; a swinging foot blends toward the
-- floor ahead by how high it is lifted, so it rises before it reaches a riser and lands on the real floor.
function Core.resolveFloors(body, base, samples, heights)
	local p = body.p
	local liftL, liftR = lifts(base, body.joints)
	local floor, ahead = {}, {}
	for i, s in samples do
		local h = heights[i]
		if h and finite(h) then
			if s.kind == "ahead" then
				ahead[s.side] = math.max(ahead[s.side] or -math.huge, h)
			else
				floor[s.side] = math.max(floor[s.side] or -math.huge, h)
			end
		end
	end
	for _, side in { "Left", "Right" } do
		if floor[side] and ahead[side] and ahead[side] > floor[side] then
			local lift = side == "Left" and liftL or liftR
			local w = Kit.smoothstep((lift - p.swingLiftStart) / p.swingLiftSpan)
			floor[side] += (ahead[side] - floor[side]) * w
		end
	end
	return floor.Left, floor.Right
end

-- One frame. frame = {
--   base      = { [joint] = CFrame }  Animate's Transforms this frame (read in PreSimulation)
--   dt        = seconds
--   grounded  = boolean
--   floorL/R  = root-space floor height under each foot (Core.resolveFloors), nil if none
--   velocity  = Vector3 world velocity of the HumanoidRootPart (only the horizontal part is used)
--   gravity   = Workspace.Gravity
--   clearance = root height above standing over the floor below, one step ahead (Kit.floorClearance); needed while
--               airborne (not grounded) and while landing
--   rootHeight= world Y of the HumanoidRootPart (floors are smoothed in world space; optional)
--   suspend   = boolean: climbing / seated / swimming / a full-body track owns the pose -> fade the layer out
-- }
-- Returns the pose to write ({ [joint] = CFrame }, every joint that was in base).
function Core.step(body, frame)
	local p, joints = body.p, body.joints
	local S = Kit.Secondary
	local base = frame.base
	local dt = finite(frame.dt) and math.clamp(frame.dt, 0, 0.1) or 0
	local grounded = frame.grounded == true
	local vy = frame.velocity and frame.velocity.Y or 0
	if not finite(vy) then vy = 0 end
	-- stepping down a stair: the Humanoid leaves the floor for a few frames, but the feet keep reaching for it
	local contact = grounded
		or (frame.clearance ~= nil and frame.clearance <= p.stepReach and vy > -p.stepFallSpeed and vy < 8)

	body.plantW += ((contact and 1 or 0) - body.plantW) * Kit.expAlpha(dt, p.plantTau)
	body.activeW += ((frame.suspend and 0 or 1) - body.activeW) * Kit.expAlpha(dt, p.activeTau)
	local velocity = frame.velocity or Vector3.zero
	if not (finite(velocity.X) and finite(velocity.Y) and finite(velocity.Z)) then velocity = Vector3.zero end

	-- 1. secondary motion (bank / pitch / head / arms), computed from velocity only -> same for player, NPC, remote
	S.measure(body.secondary, velocity, dt)
	local weights = frame.suspend and S.OFF or (contact and S.FULL or p.airWeights)
	S.settle(body.secondary, dt, frame.gravity, weights)
	local pose = table.clone(base)
	if body.secondary.active then
		for name, cf in S.apply(body.secondary, pose, joints) do pose[name] = cf end
	end

	-- 2. terrain fit while grounded (weighted in/out around take-off and landing, and while suspended)
	local w = body.plantW * body.activeW
	local floorL, floorR = frame.floorL, frame.floorR
	if p.floorSlew > 0 and frame.rootHeight and finite(frame.rootHeight) then
		-- slew each foot's floor in WORLD space: a planted foot's floor does not move, a swinging foot's floor steps
		-- at stair edges -> spread that step over a few frames (no one-frame knee pop)
		local maxStep = p.floorSlew * dt
		local function slew(side, floor)
			if not floor then
				body.floorWorld[side] = nil
				return nil
			end
			local world = floor + frame.rootHeight
			local prev = body.floorWorld[side]
			if prev and math.abs(world - prev) < p.floorSnap then
				world = prev + math.clamp(world - prev, -maxStep, maxStep)
			end
			body.floorWorld[side] = world
			return world - frame.rootHeight
		end
		floorL, floorR = slew("Left", floorL), slew("Right", floorR)
	end
	if w > 1e-3 and body.neutral then
		if floorL and floorR then
			-- Pelvis height: what Kit.fitFeetToFloor wants, but eased (pelvisTau). The height it wants switches between
			-- "the left foot decides" and "the right foot decides" at every foot swap on a slope or stair; applied raw,
			-- that switch lands on a nearly straight knee (the two-bone singularity) and flips it 18-70 deg in one frame
			-- (measured offline). Eased, the pelvis glides and the knees absorb the difference with IK.
			local fitted = Kit.fitFeetToFloor(pose, joints, floorL, floorR, w, { soft = p.soft })
			local rootName = Kit.rootName(joints)
			local rootData = rootName and Kit.jointData(joints[rootName])
			if rootName and rootData and fitted[rootName] and pose[rootName] then
				local wanted = rootData.c0:VectorToWorldSpace(fitted[rootName].Position - pose[rootName].Position).Y
				if body.pelvisDy == nil then body.pelvisDy = wanted end
				body.pelvisDy += (wanted - body.pelvisDy) * Kit.expAlpha(dt, p.pelvisTau)
				pose = Kit.shiftRootY(pose, joints, body.pelvisDy)
				-- feet only (the pelvis is placed): each foot to its target with two-bone IK
				pose = Kit.fitFeetToFloor(pose, joints, floorL, floorR, w, { soft = p.soft, maxDrop = 0, maxRise = 0 })
			else
				pose = fitted
			end
		else
			-- no floor under one foot (ledge, thin part): fall back to "lower foot at standing height" on the one we have
			local target = floorL or floorR or body.neutral
			local planted = Kit.groundLowest(pose, joints, target)
			local rootName = Kit.rootName(joints)
			if rootName and planted[rootName] and pose[rootName] then
				pose[rootName] = pose[rootName] + (planted[rootName].Position - pose[rootName].Position) * w
			end
		end
	end

	-- 3. airborne / landing: the lowest foot never below the floor predicted one physics step ahead (raise only)
	if frame.clearance and body.neutral and (not contact or body.plantW < 0.999) then
		pose = Kit.raiseLowest(pose, joints, body.neutral - frame.clearance)
	end

	-- 4. corrections appear and disappear at <= Animate's own motion + 360 deg/s (no one-frame pops at stair edges)
	if body.prevOut and body.prevBase and dt > 0 then
		for name, cf in pose do
			pose[name] = Kit.carryLimit(body.prevOut[name], body.prevBase[name], base[name], cf, dt, p.correctionRate)
		end
	end

	-- 5. safety net: the planted foot (the lower one in Animate's pose) is never drawn inside its own floor.
	--    Moves the whole body up (Root translation only): no joint rotates, so the rate limit above still holds.
	if contact and w > 0.5 and floorL and floorR then
		local liftL, liftR = lifts(base, joints)
		local side = liftL <= liftR and "Left" or "Right"
		local floorY = side == "Left" and floorL or floorR
		local sole = Kit.soleLow(pose, joints, side)
		if sole and sole < floorY then pose = Kit.shiftRootY(pose, joints, floorY - sole) end
	end

	-- NaN guard: never write a non-finite Transform (fall back to Animate's pose for that joint)
	for name, cf in pose do
		local x, y, z = cf.X, cf.Y, cf.Z
		local lv = cf.LookVector
		if not (finite(x) and finite(y) and finite(z) and finite(lv.X) and finite(lv.Y) and finite(lv.Z)) then
			pose[name] = base[name]
		end
	end

	body.prevBase, body.prevOut = base, pose
	body.debug.floorL, body.debug.floorR, body.debug.bank, body.debug.contact = floorL, floorR, body.secondary.bank, contact
	return pose
end

return table.freeze(Core)
