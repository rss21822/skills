-- TutorialFlow -------------------------------------------------------------------------------------------------------
local Flow = load("TutorialFlow.luau", { table = table })
local now = 0
local changes, completes = {}, {}
local flow = Flow.new(Config, {
	clock = function()
		return now
	end,
	onChange = function(p, state, why)
		table.insert(changes, { p = p, stage = state.stage, stepId = state.stepId, why = why })
	end,
	onComplete = function(p, why)
		table.insert(completes, { p = p, why = why })
	end,
})
local pa = { UserId = 1 }
check(flow:start(pa) and flow:state(pa).stage == "welcome" and changes[1].why == "start", "starts at the first stage")
check(not flow:start(pa), "one run per player per server")
check(flow:isRunning(pa) and not flow:isRunning({ UserId = 9 }), "isRunning")
check(select(2, flow:report(pa, { stage = "welcome" })) == "too_soon", "the welcome cannot end at once")
now = 1
check(flow:report(pa, { stage = "welcome" }) and flow:state(pa).stage == "basics" and flow:state(pa).stepId == "forward",
	"the client ends the welcome; the basics start at their first step")
check(flow:state(pa).step == 1 and flow:state(pa).stepCount == #Config.BASICS, "step index / count")
check(select(2, flow:report(pa, "x")) == "payload", "the payload must be a table")
check(select(2, flow:report(pa, { stage = "core" })) == "stage", "only the current stage")
now = 1.3
check(select(2, flow:report(pa, { stage = "basics", step = "turn" })) == "step", "only the current step")
now = 1.4
check(select(2, flow:report(pa, { stage = "basics", step = "forward" })) == "rate", "reports are rate limited")
now = 1.6
check(flow:report(pa, { stage = "basics", step = "forward" }) and flow:state(pa).stepId == "turn", "a step done moves on")
now = 1.9
check(select(2, flow:report(pa, { stage = "basics", step = "turn" })) == "too_soon", "not sooner than MIN_STEP_SECONDS")
now = 1.6 + Config.STEP_FALLBACK_SECONDS
flow:tick()
check(flow:state(pa).stepId == "back" and changes[#changes].why == "fallback",
	"a step nobody finishes passes after STEP_FALLBACK_SECONDS")
now += 1
check(flow:report(pa, { stage = "basics", step = "back" }), "back")
now += 1
check(flow:report(pa, { stage = "basics", step = "jump" }) and flow:state(pa).stage == "core",
	"the last step ends the basics stage")
now += 1
check(select(2, flow:report(pa, { stage = "core" })) == "server_stage", "a server stage is not ended by a client report")
check(flow:serverEvent(pa, "core") and flow:state(pa).stage == "first_success", "the server ends its stage")
check(select(2, flow:serverEvent(pa, "core")) == "stage", "a stale server event is ignored")
now += Config.STAGE_FALLBACK_SECONDS.first_success
flow:tick()
check(flow:state(pa).stage == "complete" and flow:state(pa).done, "a stage nobody finishes passes after its fallback")
check(#completes == 1 and completes[1].p == pa and completes[1].why == "fallback", "entering the last stage completes")
check(select(2, flow:report(pa, { stage = "complete" })) == "not_running", "nothing is accepted after completion")
flow:tick()
check(#completes == 1 and not flow:isRunning(pa), "completes once")
flow:remove(pa)
check(flow:state(pa) == nil, "remove")
local pb = { UserId = 2 }
flow:start(pb)
check(flow:skipStage(pb) and flow:state(pb).stage == "basics" and changes[#changes].why == "skip", "skipStage")
check(flow:finish(pb, "skip_button") and flow:state(pb).done and completes[#completes].why == "skip_button",
	"finish ends at the completion stage (it counts as completed)")
check(not flow:finish(pb) and not flow:skipStage(pb), "nothing after finish")
local stageFlow = Flow.new({ STAGES = { "welcome", "basics", "done" }, BASICS = {}, MIN_STEP_SECONDS = 0 }, {
	clock = function()
		return now
	end,
	onChange = function()
		error("a broken onChange must not break the flow")
	end,
})
local pc = { UserId = 3 }
stageFlow:start(pc)
now += 1
check(stageFlow:report(pc, { stage = "welcome" }) and stageFlow:state(pc).stage == "done",
	"an empty basics list is passed over; a throwing onChange is contained")
check(not pcall(Flow.new, { STAGES = { "only" } }), "a flow needs a stage and the completion stage")

-- TutorialGuideController ---------------------------------------------------------------------------------------------
local Controller = load("TutorialGuideController.luau", { table = table })
check(Controller.formatPrompt("Hold {key:W}", function(name)
	return if name == "W" then "Z" else name
end) == "Hold Z", "the key label follows the keyboard layout")
check(Controller.formatPrompt("Press {key:Space}", function()
	return " "
end) == "Press Space", "a blank key label falls back to the key name")
check(Controller.formatPrompt("Hold {key:W}", function()
	error("no layout")
end) == "Hold W", "a failing keyString falls back to the key name")
local server = { stage = "welcome", stepId = nil }
local sent, viewLog = {}, {}
local input = { move = V(0, 0, 0), jumping = false, actions = {} }
local device = "keyboard"
local lastProgress = 0
local function newController(config)
	return Controller.new({
		config = config,
		detector = Detector,
		read = function()
			return server.stage, server.stepId
		end,
		sample = function()
			return { moveDirection = input.move, lookVector = look, jumping = input.jumping, actions = input.actions }
		end,
		device = function()
			return device
		end,
		keyString = function(name)
			return name
		end,
		report = function(payload)
			table.insert(sent, payload)
		end,
		view = {
			stage = function(stage)
				table.insert(viewLog, "stage:" .. tostring(stage))
			end,
			step = function(step, index, total, label)
				table.insert(viewLog, "step:" .. step.id .. ":" .. index .. "/" .. total .. ":" .. label)
			end,
			progress = function(fraction)
				lastProgress = fraction
			end,
			hide = function()
				table.insert(viewLog, "hide")
			end,
		},
	})
end
check(not pcall(Controller.new, { config = Config }), "the controller needs all its options")
local c = newController(Config)
c:update(1 / 60)
check(viewLog[1] == "stage:welcome", "the view follows the server's stage")
check(c:confirm() and sent[1].stage == "welcome" and not c:confirm(), "the welcome confirm reports once")
c:update(Controller.RESEND_SECONDS + 0.1)
check(#sent == 2 and sent[2].stage == "welcome", "an unanswered confirm is sent again")
server.stage, server.stepId = "basics", "forward"
c:update(1 / 60)
check(viewLog[#viewLog] == "step:forward:1/4:Hold W", "the step card gets the device prompt")
input.move = V(0, 0, -1)
for _ = 1, 4 do
	c:update(0.2)
end
check(lastProgress > 0.6 and sent[#sent].stage == "welcome", "the meter fills; nothing is reported early")
for _ = 1, 3 do
	c:update(0.2)
end
check(sent[#sent].stage == "basics" and sent[#sent].step == "forward", "a finished hold reports its step")
local reports = #sent
c:update(0.2)
check(#sent == reports, "no second report before RESEND_SECONDS")
device = "touch"
c:update(0.2)
check(viewLog[#viewLog] == "step:forward:1/4:Push the stick up", "switching device relabels the step")
c:update(Controller.RESEND_SECONDS)
check(#sent == reports + 1 and sent[#sent].step == "forward", "a report the server did not take is sent again")
device = "keyboard"
server.stepId = "jump"
input.move = V(0, 0, 0)
c:update(0.1)
check(viewLog[#viewLog] == "step:jump:4/4:Press Space twice", "a new step gets a new card")
input.jumping = true
c:update(0.1)
input.jumping = false
c:update(0.1)
check(sent[#sent].step == "forward", "one jump is not two")
input.jumping = true
c:update(0.1)
check(sent[#sent].stage == "basics" and sent[#sent].step == "jump", "two jumps report the jump step")
server.stage, server.stepId = nil, nil
c:update(0.1)
check(viewLog[#viewLog] == "hide", "no stage: the view hides")
local custom = table.clone(Config)
custom.BASICS = { { id = "gas", detect = "accelerate", hold = 0.5, title = "GAS", text = "Accelerate." } }
local cc = newController(custom)
server.stage, server.stepId = "basics", "gas"
input.actions = { accelerate = true }
for _ = 1, 3 do
	cc:update(0.2)
end
check(sent[#sent].step == "gas", "a custom step reads the game's own action")
input.move = nil
local blind = newController(Config)
server.stepId = "forward"
blind:update(0.2)
check(lastProgress == 0, "no character yet: nothing is detected, nothing errors")

-- The examples and every template compile -------------------------------------------------------------------------------
local compiled = 0
for _, folder in ipairs({ ROOT, ROOT .. "examples/" }) do
	for _, name in ipairs(fs.readDir(folder)) do
		if string.sub(name, -5) == ".luau" then
			local ok, err = pcall(luau.compile, fs.readFile(folder .. name))
			check(ok, "compiles: " .. folder .. name .. " " .. tostring(err))
			compiled += 1
		end
	end
end
check(compiled >= 9, "all templates and examples were compiled (" .. compiled .. ")")
