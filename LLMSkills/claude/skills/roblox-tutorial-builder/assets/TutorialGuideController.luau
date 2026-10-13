-- TutorialGuideController (template from the roblox-tutorial-builder skill): the client side of the welcome and the
-- basic-controls stage. It follows the server's stage (TutorialFlow, replicated as the player's attributes), runs
-- the detector for the current step, drives the game's own UI and reports a finished step to the server.
--
-- It has NO visuals of its own: `view` is built from the game's UI kit (its HUD cards, fonts, colours, safe areas;
-- references/ui-and-text.md). A generic card here would be the "AI default UI" the tutorial must not look like.
--
--   local c = Controller.new({
--       config = Config, detector = Detector,
--       read = function() return player:GetAttribute("TutorialStage"), player:GetAttribute("TutorialStepId") end,
--       sample = function()            -- this frame's input, the way the GAME moves
--           local jumpedNow = jumped; jumped = false
--           return { moveDirection = humanoid.MoveDirection, lookVector = camera.CFrame.LookVector,
--                    jumping = jumpedNow, actions = GameInput.held() }   -- the game's own actions, if any
--       end,
--       device = function() return Detector.device(UserInputService) end,
--       keyString = function(name) return UserInputService:GetStringForKeyCode(Enum.KeyCode[name]) end,
--       report = function(payload) remote:FireServer(payload) end,
--       view = GuideView,                -- { stage(name), step(step, index, total, label), progress(f), hide() }
--   })
--   RunService.RenderStepped:Connect(function(dt) c:update(dt) end)
--   -- the welcome card's last button: c:confirm()
--
-- Detection per step (config.BASICS[i].detect), with its goal (hold seconds, count presses, or turn degrees):
--   "move_forward" | "move_back" | "move_left" | "move_right" | "move_side" | "move_any"
--                  Humanoid.MoveDirection against the camera (default controls, every device)
--   "jump"         sample.jumping (set it for one frame from Detector.watchJumps)
--   "camera"       with turn = <degrees>: the camera's look vector turning (look around; any device)
--   anything else  sample.actions[detect] == true: the game's own input module says the action is held / pressed
--                  (accelerate, steer_left, dash, spin, drift ...). Use this for custom movement.
-- The prompt per device: step.prompt[device] (else step.text), with {key:W} replaced by the key's label on the
-- player's keyboard layout (W shows "Z" on AZERTY).

local Controller = {}
Controller.__index = Controller
-- A report the server has not answered (it advanced no step) is sent again after this long.
Controller.RESEND_SECONDS = 1

local REQUIRED = { "config", "detector", "read", "sample", "device", "report", "view" }

function Controller.new(opts)
	assert(type(opts) == "table", "TutorialGuideController.new: options required")
	for _, name in ipairs(REQUIRED) do
		assert(opts[name] ~= nil, "TutorialGuideController.new: " .. name .. " required")
	end
	return setmetatable({
		_o = opts, _stage = nil, _stepId = nil, _device = nil, _meter = nil,
		_sentAt = nil, _sentFor = nil, _since = 0,
	}, Controller)
end

-- "{key:W}" -> the label of that key on this keyboard (keyString), else the key's name.
function Controller.formatPrompt(text, keyString)
	if type(text) ~= "string" then
		return ""
	end
	return (string.gsub(text, "{key:(%w+)}", function(name)
		if type(keyString) == "function" then
			local ok, label = pcall(keyString, name)
			if ok and type(label) == "string" and string.match(label, "%S") then -- Space gives " ": use the name
				return label
			end
		end
		return name
	end))
end

function Controller:label(step, device)
	local text = type(step.prompt) == "table" and step.prompt[device] or step.text
	return Controller.formatPrompt(text, self._o.keyString)
end

function Controller:_step(id)
	for index, step in ipairs(self._o.config.BASICS or {}) do
		if step.id == id then
			return step, index
		end
	end
	return nil, nil
end

function Controller:_doing(step, sample)
	local detect = step.detect
	if string.sub(detect, 1, 5) == "move_" then
		if sample.moveDirection == nil or sample.lookVector == nil then
			return false
		end
		return self._o.detector.isMoving(detect, sample.moveDirection, sample.lookVector)
	end
	if detect == "jump" then
		return sample.jumping == true
	end
	return type(sample.actions) == "table" and sample.actions[detect] == true
end

function Controller:_send(payload, key)
	self._sentFor, self._sentAt = key, self._since
	pcall(self._o.report, payload)
end

-- Every frame.
function Controller:update(dt)
	dt = (type(dt) == "number" and dt > 0) and dt or 0
	self._since += dt
	local stage, stepId = self._o.read()
	local device = self._o.device()
	if stage ~= self._stage then
		self._stage, self._stepId, self._meter, self._sentFor = stage, nil, nil, nil
		if stage == nil then
			self._o.view.hide()
			return
		end
		self._o.view.stage(stage)
	end
	if stage == "welcome" and self._sentFor == "welcome" and self._since - self._sentAt >= Controller.RESEND_SECONDS then
		self:_send({ stage = "welcome" }, "welcome") -- the confirm was not taken yet (too soon): ask again
		return
	end
	if stage ~= "basics" then
		return
	end
	local step, index = self:_step(stepId)
	if step == nil then
		return
	end
	if stepId ~= self._stepId then
		self._stepId, self._sentFor = stepId, nil
		local detector = self._o.detector
		self._meter = if step.hold then detector.newHold(step.hold)
			elseif step.turn then detector.newTurn(step.turn)
			else detector.newCounter(step.count)
		self._device = nil
	end
	if device ~= self._device then
		self._device = device -- a new step, or the player switched device: relabel
		self._o.view.step(step, index, #self._o.config.BASICS, self:label(step, device))
	end
	local sample = self._o.sample()
	local progress, done
	if step.turn then
		progress, done = self._meter:step(sample.lookVector)
	elseif step.hold then
		progress, done = self._meter:step(dt, self:_doing(step, sample))
	else
		local doing = self:_doing(step, sample)
		local count
		count, done = self._meter:step(doing)
		progress = count / step.count
	end
	self._o.view.progress(progress)
	if done and (self._sentFor ~= stepId or self._since - self._sentAt >= Controller.RESEND_SECONDS) then
		self:_send({ stage = "basics", step = stepId }, stepId)
	end
end

-- The welcome's last button.
function Controller:confirm()
	if self._stage == "welcome" and self._sentFor ~= "welcome" then
		self:_send({ stage = "welcome" }, "welcome")
		return true
	end
	return false
end

return Controller
