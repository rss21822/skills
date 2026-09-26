-- SwordCombo/Spec: the 3-strike R15 sword combo as data + a pure sampler (no Instances; runs offline in Lune).
--
-- Angles are joint Transform rotations CFrame.Angles(rad(x), rad(y), rad(z)) (= fromEulerAnglesXYZ), in degrees.
-- Sign conventions (checked by forward kinematics on rig-r15.json in tests/test_sword_combo.luau; character faces -Z):
--   Root   : +Y turn LEFT, +Z roll = lean to the character's LEFT, +X pitch back.  dy = pelvis height offset (studs, - = down)
--   Waist  : -X chest forward, +X arch back, +Y chest turns LEFT, +Z lean LEFT
--   Neck   : +X look up, +Y look LEFT
--   Shoulder: +X arm forward/up, Z: Right + / Left - = arm out to the side
--   Elbow  : +X flexes (forearm forward/up with the arm hanging). NOTE: the skill's r15-rig.md says -X; FK on this rig says
--            -X would hyperextend. Confirm with a +-30 deg single-axis hold pose in Studio before shipping.
--   Elbow Y: forearm twist (pronation / supination) — used to aim the blade; Wrist X / Z cock the hand.
--   Arm keys were solved from hand position + blade direction targets in UpperTorso space (tools/solve_arm_keys.luau)
--   under the blade = RightHand -Z assumption; re-run that tool if the real Tool.Grip differs.
--   Legs   : not keyed. Feet are planted targets in HumanoidRootPart space and the legs are solved by two-bone IK
--            (SwordCombo/Player), so the feet never slide when the pelvis turns, dips or rises.
-- Blade: assumed along the RightHand's -Z (default Tool grip holds the blade forward from the fist). Spec.BLADE_LENGTH.
local Spec = {}

Spec.BLADE_LENGTH = 3.2
Spec.ENTER_FADE = 0.10 -- Animate -> combo (the first key is the guard; strike 1's windup also carries the entry)
Spec.CHAIN_FADE = 0.08 -- strike N -> strike N+1 (from the rendered pose, velocity carried)
Spec.EXIT_FADE = 0.28 -- combo -> Animate
Spec.RATE = math.rad(360) -- correction budget on top of the authored motion (deg/s), like every hand-off in the kit

-- Stance (HumanoidRootPart space offsets from each foot's bind-pose frame). Left foot leads; right foot back and turned out.
Spec.STANCE = {
	Left = { dx = -0.05, dz = -0.50, yaw = 12 }, -- +yaw = toe turns LEFT (left foot: out)
	Right = { dx = 0.08, dz = 0.42, yaw = -32 }, -- -yaw = toe turns RIGHT (right foot: out)
	enterStep = { Left = { from = 0.00, to = 0.14, lift = 0.16 }, Right = { from = 0.05, to = 0.19, lift = 0.10 } },
	exitStep = { Left = { from = 0.02, to = 0.16, lift = 0.12 }, Right = { from = 0.08, to = 0.22, lift = 0.08 } },
}

local UPPER = { "Root", "Waist", "Neck", "RightShoulder", "RightElbow", "RightWrist", "LeftShoulder", "LeftElbow", "LeftWrist" }
Spec.UPPER = UPPER

local function pose(t)
	return t
end

-- Guard (中段・片手): sword forward-up in front of the chest, left hand in front of the belly.
local GUARD = pose({
	Root = { 0, -15, 0, dy = -0.24 },
	Waist = { -6, 10, 0 },
	Neck = { -2, 6, 0 },
	RightShoulder = { 14, -2, -49 },
	RightElbow = { 45, 32, 0 },
	RightWrist = { -24, 0, -3 },
	LeftShoulder = { 22, 0, -12 },
	LeftElbow = { 48, 0, 0 },
	LeftWrist = { 0, 0, 0 },
})
Spec.GUARD = GUARD

-- ease of the segment ENDING at a key: "inOut" (smoothstep), "in" (accelerate: t^2), "out" (decelerate), "linear"
-- Strike 1: 袈裟斬り (upper right -> lower left)
local S1 = {
	name = "Kesa",
	duration = 1.03,
	contact = 0.41, -- sword crosses the target line, max speed
	inputOpen = 0.28, -- presses before this are ignored (mash guard); later presses are buffered
	chainAt = 0.60, -- earliest frame the buffered next strike starts (after the follow-through overshoot)
	hitStop = 0.06, shake = 0.8,
	keys = {
		{ t = 0.00, ease = "linear", pose = GUARD },
		-- anticipation: coil right, sword cocked over the right shoulder, weight onto the back leg, slight rise
		{ t = 0.28, ease = "inOut", pose = {
			Root = { 4, -32, -4, dy = -0.17 }, Waist = { 10, -22, -6 }, Neck = { -6, 34, 8 },
			RightShoulder = { 106, 9, -39 }, RightElbow = { 101, 78, 0 }, RightWrist = { -52, 0, 13 },
			LeftShoulder = { 55, 0, -20 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- the "間": a hair more coil while speed builds (ease out into it)
		{ t = 0.34, ease = "out", pose = {
			Root = { 5, -35, -5, dy = -0.18 }, Waist = { 12, -25, -7 }, Neck = { -6, 36, 9 },
			RightShoulder = { 116, 9, -34 }, RightElbow = { 96, 73, 0 }, RightWrist = { -57, 0, 11 },
			LeftShoulder = { 58, 0, -22 }, LeftElbow = { 62, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- contact: unwinding hard, chest square to the target, blade diagonal in front at shoulder height
		{ t = 0.41, ease = "in", pose = {
			Root = { -4, -5, 3, dy = -0.30 }, Waist = { -14, 12, 6 }, Neck = { -8, 2, -3 },
			RightShoulder = { 42, -15, -52 }, RightElbow = { 41, 74, 0 }, RightWrist = { -75, 0, -4 },
			LeftShoulder = { 10, 0, -30 }, LeftElbow = { 35, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- end of the swing: blade low left, weight on the front leg
		{ t = 0.48, ease = "out", pose = {
			Root = { -8, 18, 5, dy = -0.36 }, Waist = { -22, 24, 8 }, Neck = { -10, -14, -6 },
			RightShoulder = { 18, -28, -70 }, RightElbow = { 0, -22, 0 }, RightWrist = { -82, 0, -2 },
			LeftShoulder = { -25, 0, -38 }, LeftElbow = { 20, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- follow-through overshoot (heavy blade keeps pulling)
		{ t = 0.63, ease = "out", pose = {
			Root = { -9, 22, 6, dy = -0.38 }, Waist = { -25, 28, 9 }, Neck = { -10, -18, -7 },
			RightShoulder = { 26, -19, -71 }, RightElbow = { 0, -44, 0 }, RightWrist = { -76, 0, 18 },
			LeftShoulder = { -30, 0, -40 }, LeftElbow = { 18, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- recovery (settles back a little; strike 2 starts from here)
		{ t = 0.83, ease = "inOut", pose = {
			Root = { -6, 14, 4, dy = -0.32 }, Waist = { -16, 20, 6 }, Neck = { -6, -10, -4 },
			RightShoulder = { 31, -24, -70 }, RightElbow = { 0, -36, 0 }, RightWrist = { -67, 0, 14 },
			LeftShoulder = { -10, 0, -30 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		{ t = 1.03, ease = "inOut", pose = GUARD },
	},
}

-- Strike 2: 横薙ぎ (backhand, left -> right). Anticipation = coil further LEFT from where strike 1 ended.
local S2 = {
	name = "Yokonagi",
	duration = 0.95,
	contact = 0.30,
	inputOpen = 0.18,
	chainAt = 0.50,
	hitStop = 0.07, shake = 0.8,
	keys = {
		{ t = 0.00, ease = "linear", pose = S1.keys[7].pose },
		{ t = 0.18, ease = "inOut", pose = {
			Root = { -2, 30, 4, dy = -0.30 }, Waist = { -8, 30, 5 }, Neck = { -4, -30, -5 },
			RightShoulder = { 77, 59, -63 }, RightElbow = { 34, 68, 0 }, RightWrist = { -16, 0, 23 },
			LeftShoulder = { -15, 0, -35 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		{ t = 0.23, ease = "out", pose = {
			Root = { -2, 33, 4, dy = -0.31 }, Waist = { -8, 33, 5 }, Neck = { -4, -32, -5 },
			RightShoulder = { 82, 60, -68 }, RightElbow = { 37, 69, 0 }, RightWrist = { -19, 0, 18 },
			LeftShoulder = { -16, 0, -36 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- contact: chest square, arm sweeping through the front at chest height
		{ t = 0.30, ease = "in", pose = {
			Root = { -3, 0, 0, dy = -0.34 }, Waist = { -10, 2, 0 }, Neck = { -4, 0, 0 },
			RightShoulder = { 14, -33, -100 }, RightElbow = { 49, 24, 0 }, RightWrist = { -75, 0, -2 },
			LeftShoulder = { 0, 0, -40 }, LeftElbow = { 30, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- end of the sweep: arm out to the right
		{ t = 0.37, ease = "out", pose = {
			Root = { -3, -24, -3, dy = -0.35 }, Waist = { -10, -26, -4 }, Neck = { -4, 28, 3 },
			RightShoulder = { 8, -58, -100 }, RightElbow = { 84, 81, 0 }, RightWrist = { -75, 0, 2 },
			LeftShoulder = { 25, 0, -25 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		{ t = 0.52, ease = "out", pose = {
			Root = { -3, -30, -4, dy = -0.36 }, Waist = { -10, -31, -5 }, Neck = { -4, 32, 4 },
			RightShoulder = { 33, -83, -100 }, RightElbow = { 94, 87, 0 }, RightWrist = { -75, 0, 4 },
			LeftShoulder = { 30, 0, -22 }, LeftElbow = { 64, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		-- recovery: sword comes up on the right (strike 3 raises it from here)
		{ t = 0.72, ease = "inOut", pose = {
			Root = { -2, -24, -3, dy = -0.32 }, Waist = { -6, -24, -3 }, Neck = { -3, 26, 3 },
			RightShoulder = { 44, -18, -85 }, RightElbow = { 115, 90, 0 }, RightWrist = { -40, 0, 15 },
			LeftShoulder = { 30, 0, -20 }, LeftElbow = { 60, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		{ t = 0.95, ease = "inOut", pose = GUARD },
	},
}

-- Strike 3: 振りかぶって叩きつけ (overhead slam, two hands at the top, lead foot stamps at impact)
local S3 = {
	name = "Slam",
	duration = 1.30,
	contact = 0.47, -- impact at the bottom of the slam
	inputOpen = math.huge, -- last strike: no chain
	chainAt = math.huge,
	hitStop = 0.12, shake = 1.6,
	step = { foot = "Left", dz = -0.30, from = 0.32, to = 0.47, lift = 0.20 }, -- 踏み込み: lands on the impact frame
	keys = {
		{ t = 0.00, ease = "linear", pose = S2.keys[7].pose },
		-- furikaburi: arch back, rise, both hands overhead, blade hanging behind the head
		{ t = 0.30, ease = "inOut", pose = {
			Root = { 8, -8, 0, dy = -0.20 }, Waist = { 16, 4, 0 }, Neck = { 6, 4, 0 },
			RightShoulder = { 98, -12, -85 }, RightElbow = { 55, 85, 0 }, RightWrist = { 1, 0, 2 },
			LeftShoulder = { 135, -57, 50 }, LeftElbow = { 59, -2, 0 }, LeftWrist = { 0, 0, 1 } } },
		{ t = 0.38, ease = "out", pose = { -- hang at the top
			Root = { 9, -8, 0, dy = -0.19 }, Waist = { 18, 4, 0 }, Neck = { 7, 4, 0 },
			RightShoulder = { 107, -15, -78 }, RightElbow = { 47, 79, 0 }, RightWrist = { 5, 0, 0 },
			LeftShoulder = { 144, -52, 50 }, LeftElbow = { 51, 1, 0 }, LeftWrist = { -1, 0, 1 } } },
		-- impact: crouched deep, chest pitched forward, arms driven down in front
		{ t = 0.47, ease = "in", pose = {
			Root = { -10, -6, 0, dy = -0.62 }, Waist = { -26, 4, 0 }, Neck = { 8, 2, 0 },
			RightShoulder = { 29, -25, -69 }, RightElbow = { 29, 17, 0 }, RightWrist = { -51, 0, -3 },
			LeftShoulder = { 105, -90, 78 }, LeftElbow = { 23, -21, 0 }, LeftWrist = { 21, 0, 26 } } },
		-- follow-through: body keeps compressing after the blade stops
		{ t = 0.60, ease = "out", pose = {
			Root = { -12, -6, 0, dy = -0.66 }, Waist = { -30, 4, 0 }, Neck = { 12, 2, 0 },
			RightShoulder = { 28, -22, -67 }, RightElbow = { 30, 16, 0 }, RightWrist = { -48, 0, -2 },
			LeftShoulder = { 105, -90, 78 }, LeftElbow = { 18, -25, 0 }, LeftWrist = { 29, 0, 33 } } },
		-- slow, heavy recovery
		{ t = 0.95, ease = "inOut", pose = {
			Root = { -6, -10, 0, dy = -0.45 }, Waist = { -16, 6, 0 }, Neck = { 2, 4, 0 },
			RightShoulder = { 21, -18, -62 }, RightElbow = { 54, -12, 0 }, RightWrist = { -74, 0, -19 },
			LeftShoulder = { 30, 0, -10 }, LeftElbow = { 40, 0, 0 }, LeftWrist = { 0, 0, 0 } } },
		{ t = 1.30, ease = "inOut", pose = GUARD },
	},
}

Spec.STRIKES = { S1, S2, S3 }

local function ease(kind, u)
	u = math.clamp(u, 0, 1)
	if kind == "in" then
		return u * u
	elseif kind == "out" then
		return 1 - (1 - u) * (1 - u)
	elseif kind == "inOut" then
		return u * u * (3 - 2 * u)
	end
	return u
end
Spec.ease = ease

-- The Transform CFrame for one keyed joint value (Root carries dy, applied by the Player through the Root's C0).
function Spec.jointCFrame(v)
	return CFrame.Angles(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

-- Sample strike `index` at pose-clock time t: { [joint] = CFrame } for UPPER joints, plus rootDy (studs).
function Spec.sample(index, t)
	local strike = Spec.STRIKES[index]
	local keys = strike.keys
	t = math.clamp(t, 0, strike.duration)
	local a, b = keys[1], keys[#keys]
	for i = 1, #keys - 1 do
		if t >= keys[i].t and t <= keys[i + 1].t then
			a, b = keys[i], keys[i + 1]
			break
		end
	end
	local span = b.t - a.t
	local u = span > 0 and ease(b.ease, (t - a.t) / span) or 1
	local out = {}
	for _, name in UPPER do
		local va, vb = a.pose[name], b.pose[name]
		out[name] = Spec.jointCFrame(va):Lerp(Spec.jointCFrame(vb), u)
	end
	local dy = a.pose.Root.dy + (b.pose.Root.dy - a.pose.Root.dy) * u
	return out, dy
end

return Spec
