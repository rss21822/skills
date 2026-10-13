-- BasicControlsDetector (template from the roblox-tutorial-builder skill): "is the player doing this basic control
-- right now?" on the client, for the basic-controls stage of a tutorial.
--
-- Default Roblox character controls: movement is read from Humanoid.MoveDirection. The PlayerModule turns the keys,
-- a gamepad stick or the touch thumbstick into it, relative to the camera, so comparing it with the camera's flat
-- look vector tells forward / back / left / right on every device and with any key bindings. Jumps come from the
-- Humanoid's state. A game with its own movement (vehicles, skating, flying, click-to-move) reads its own input
-- module instead and keeps only the counting helpers (newHold / newCounter) from here.
--
--   local f, r = Detector.moveIntent(humanoid.MoveDirection, camera.CFrame.LookVector)
--   if Detector.isMoving("move_forward", humanoid.MoveDirection, camera.CFrame.LookVector) then ... end
--   local hold = Detector.newHold(1.2); local progress, done = hold:step(dt, doing)
--   local jumps = Detector.newCounter(2); local count, done = jumps:step(isJumpingNow)
--   local look = Detector.newTurn(120); local progress, done = look:step(camera.CFrame.LookVector)

local Detector = {}

-- Share of full stick / key input that counts as "doing it" (a key gives 1; a thumbstick near its rim ~1).
Detector.DEADZONE = 0.35

-- forward, right in -1..1 from a world move direction and the camera's look vector (both Vector3).
function Detector.moveIntent(moveDirection, lookVector)
	if moveDirection.Magnitude < 1e-3 then
		return 0, 0
	end
	local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flat.Magnitude < 1e-3 then
		return 0, 0 -- looking straight down / up: no horizontal frame to compare with
	end
	flat = flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X) -- the camera's right on the ground plane
	return moveDirection:Dot(flat), moveDirection:Dot(right)
end

-- action: "move_forward" | "move_back" | "move_left" | "move_right" | "move_side" (left or right) | "move_any"
function Detector.isMoving(action, moveDirection, lookVector, deadzone)
	local dz = deadzone or Detector.DEADZONE
	local forward, right = Detector.moveIntent(moveDirection, lookVector)
	if action == "move_forward" then
		return forward > dz
	elseif action == "move_back" then
		return forward < -dz
	elseif action == "move_left" then
		return right < -dz
	elseif action == "move_right" then
		return right > dz
	elseif action == "move_side" then
		return math.abs(right) > dz
	elseif action == "move_any" then
		return math.max(math.abs(forward), math.abs(right)) > dz
	end
	error("BasicControlsDetector.isMoving: unknown action " .. tostring(action), 2)
end

-- Accumulates the time the player spends doing it. Progress never goes back (a key released early, a thumbstick
-- crossing the deadzone edge): the step teaches, it does not test.
function Detector.newHold(seconds)
	assert(type(seconds) == "number" and seconds > 0, "BasicControlsDetector.newHold: seconds > 0")
	local hold = { seconds = seconds, held = 0 }
	function hold:step(dt, doing)
		if doing and type(dt) == "number" and dt > 0 then
			self.held = math.min(self.seconds, self.held + math.min(dt, 0.25)) -- a long frame counts as 0.25 s
		end
		return self.held / self.seconds, self.held >= self.seconds
	end
	function hold:reset()
		self.held = 0
	end
	return hold
end

-- Counts presses: rising edges of `doing` (jumps, the game's action button).
function Detector.newCounter(target)
	assert(type(target) == "number" and target >= 1, "BasicControlsDetector.newCounter: target >= 1")
	local counter = { target = target, count = 0, last = false }
	function counter:step(doing)
		doing = doing == true
		if doing and not self.last then
			self.count = math.min(self.target, self.count + 1)
		end
		self.last = doing
		return self.count, self.count >= self.target
	end
	function counter:reset()
		self.count, self.last = 0, false
	end
	return counter
end

-- Accumulates how far the camera turned around the vertical axis, in degrees: the "look around" step (right stick,
-- mouse drag, touch drag -- any device). Feed it the camera's look vector each frame.
function Detector.newTurn(degrees)
	assert(type(degrees) == "number" and degrees > 0, "BasicControlsDetector.newTurn: degrees > 0")
	local turn = { target = degrees, turned = 0, last = nil }
	function turn:step(lookVector)
		if lookVector ~= nil then
			local flat = Vector3.new(lookVector.X, 0, lookVector.Z)
			if flat.Magnitude > 1e-3 then
				flat = flat.Unit
				if self.last ~= nil then
					local dot = math.clamp(self.last:Dot(flat), -1, 1)
					self.turned = math.min(self.target, self.turned + math.deg(math.acos(dot)))
					if self.turned > self.target - 0.01 then
						self.turned = self.target -- Vector3 is single precision: 45 + 45 lands a hair under 90
					end
				end
				self.last = flat
			end
		end
		return self.turned / self.target, self.turned >= self.target
	end
	function turn:reset()
		self.turned, self.last = 0, nil
	end
	return turn
end

-- The device the prompt should show: "touch" | "gamepad" | "keyboard" (the last input first, then the hardware).
function Detector.device(userInputService)
	local uis = userInputService or game:GetService("UserInputService")
	local last = uis:GetLastInputType()
	if last == Enum.UserInputType.Touch then
		return "touch"
	end
	if string.sub(last.Name, 1, 7) == "Gamepad" then
		return "gamepad"
	end
	if uis.TouchEnabled and not uis.KeyboardEnabled then
		return "touch"
	end
	return "keyboard"
end

-- Calls onJump() each time the humanoid starts a jump (any device). Returns the connection.
function Detector.watchJumps(humanoid, onJump)
	return humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Jumping then
			onJump()
		end
	end)
end

return Detector
