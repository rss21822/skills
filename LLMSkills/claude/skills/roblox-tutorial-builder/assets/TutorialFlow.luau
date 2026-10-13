-- TutorialFlow (template from the roblox-tutorial-builder skill): the server's stage machine for the tutorial.
--
-- The server owns the stage. The client guide only REPORTS that the player did the current step (the player's input
-- lives on the client); the server accepts a report only for the current stage and step, not sooner than
-- MIN_STEP_SECONDS after it began, and not faster than REPORT_MIN_INTERVAL. Goals the server can see itself (the
-- first knock-out, the first checkpoint, the first coin) end their stage with flow:serverEvent -- never from a client
-- report. Nobody gets stuck: a basics step passes after STEP_FALLBACK_SECONDS and a stage after its
-- STAGE_FALLBACK_SECONDS (flow:tick from a Heartbeat). Entering the LAST stage of STAGES completes the tutorial
-- (opts.onComplete, where the game calls gate:complete); that stage is the completion card / hand-off.
--
-- Pure Luau (no services, testable in Lune). Wire it in the game's server:
--   local flow = Flow.new(Config, {
--       clock = os.clock,
--       onChange = function(player, state, why)   -- replicate for the client guide
--           player:SetAttribute("TutorialStage", state.stage)
--           player:SetAttribute("TutorialStepId", state.stepId)
--       end,
--       onComplete = function(player, why) gate:complete(player) end,
--   })
--   remote.OnServerEvent:Connect(function(player, payload) flow:report(player, payload) end)
--   RunService.Heartbeat:Connect(function() flow:tick() end)
--   -- the game's own code, when it sees the player's first success: flow:serverEvent(player, "first_success")
--
-- opts:
--   clock()                    seconds (os.clock); tests pass a fake
--   onChange(player, state, why)   state = flow:state(player); why = "start" | "done" | "server" | "fallback" | "skip"
--   onComplete(player, why)    once per run, when the last stage is entered
--   clientStages               stages the client may end by a report (default { welcome = true, basics = true });
--                              every other stage ends by serverEvent, skipStage or its fallback

local Flow = {}
Flow.__index = Flow
Flow.REPORT_MIN_INTERVAL = 0.2

function Flow.new(config, opts)
	assert(type(config) == "table" and type(config.STAGES) == "table" and #config.STAGES >= 2,
		"TutorialFlow.new: config.STAGES needs at least a stage and the completion stage")
	opts = opts or {}
	return setmetatable({
		_config = config,
		_clock = opts.clock or os.clock,
		_onChange = opts.onChange,
		_onComplete = opts.onComplete,
		_client = opts.clientStages or { welcome = true, basics = true },
		_players = {},
	}, Flow)
end

function Flow:_stageName(run)
	return self._config.STAGES[run.stageIndex]
end

function Flow:_steps(stageName)
	if stageName == "basics" then
		return self._config.BASICS or {}
	end
	return nil
end

-- nil when the player is not in the tutorial; otherwise a frozen
-- { stage, stageIndex, stageCount, step (index, 0 outside basics), stepCount, stepId, done }
function Flow:state(player)
	local run = self._players[player]
	if not run then
		return nil
	end
	local stage = self:_stageName(run)
	local steps = self:_steps(stage)
	local step = steps and steps[run.stepIndex]
	return table.freeze({
		stage = stage,
		stageIndex = run.stageIndex,
		stageCount = #self._config.STAGES,
		step = if steps then run.stepIndex else 0,
		stepCount = if steps then #steps else 0,
		stepId = if step then step.id else nil,
		done = run.done,
	})
end

function Flow:isRunning(player)
	local run = self._players[player]
	return run ~= nil and not run.done
end

function Flow:_emit(player, why)
	if type(self._onChange) == "function" then
		pcall(self._onChange, player, self:state(player), why)
	end
end

function Flow:_enter(player, run, stageIndex, why)
	local now = self._clock()
	local stages = self._config.STAGES
	run.stageIndex = math.min(stageIndex, #stages)
	run.stepIndex = 1
	run.stageAt, run.stepAt = now, now
	local steps = self:_steps(stages[run.stageIndex])
	if steps and #steps == 0 and run.stageIndex < #stages then
		return self:_enter(player, run, run.stageIndex + 1, why) -- an empty basics list: nothing to teach here
	end
	if run.stageIndex == #stages then
		run.done = true
	end
	self:_emit(player, why)
	if run.done and type(self._onComplete) == "function" then
		pcall(self._onComplete, player, why)
	end
end

-- Starts the first stage. false if the player already runs (or ran) it in this server.
function Flow:start(player)
	if self._players[player] then
		return false
	end
	local run = { stageIndex = 1, stepIndex = 1, stageAt = 0, stepAt = 0, lastReport = -math.huge, done = false }
	self._players[player] = run
	self:_enter(player, run, 1, "start")
	return true
end

function Flow:_nextStep(player, run, why)
	local steps = self:_steps(self:_stageName(run)) or {}
	if run.stepIndex >= #steps then
		return self:_enter(player, run, run.stageIndex + 1, why)
	end
	run.stepIndex += 1
	run.stepAt = self._clock()
	self:_emit(player, why)
end

-- A client report: { stage = <current stage>, step = <current step id> (basics only) }. true | false, why
-- why: "not_running" | "payload" | "stage" | "server_stage" | "rate" | "step" | "too_soon"
function Flow:report(player, payload)
	local run = self._players[player]
	if not run or run.done then
		return false, "not_running"
	end
	if type(payload) ~= "table" then
		return false, "payload"
	end
	local stage = self:_stageName(run)
	if payload.stage ~= stage then
		return false, "stage"
	end
	if not self._client[stage] then
		return false, "server_stage"
	end
	local now = self._clock()
	if now - run.lastReport < Flow.REPORT_MIN_INTERVAL then
		return false, "rate"
	end
	run.lastReport = now
	local minimum = self._config.MIN_STEP_SECONDS or 0
	local steps = self:_steps(stage)
	if steps then
		local step = steps[run.stepIndex]
		if step == nil or payload.step ~= step.id then
			return false, "step"
		end
		if now - run.stepAt < minimum then
			return false, "too_soon"
		end
		self:_nextStep(player, run, "done")
	else
		if now - run.stageAt < minimum then
			return false, "too_soon"
		end
		self:_enter(player, run, run.stageIndex + 1, "done")
	end
	return true
end

-- The game's server saw the goal of `stage` (the player's first success). true | false, why
function Flow:serverEvent(player, stage)
	local run = self._players[player]
	if not run or run.done then
		return false, "not_running"
	end
	if self:_stageName(run) ~= stage then
		return false, "stage"
	end
	self:_enter(player, run, run.stageIndex + 1, "server")
	return true
end

-- Moves on from the current stage (a tester's skip key, an Owner-approved "Skip" from this stage on).
function Flow:skipStage(player)
	local run = self._players[player]
	if not run or run.done then
		return false
	end
	self:_enter(player, run, run.stageIndex + 1, "skip")
	return true
end

-- Ends the run at the completion stage (a "Skip tutorial" button): it counts as completed.
function Flow:finish(player, why)
	local run = self._players[player]
	if not run or run.done then
		return false
	end
	self:_enter(player, run, #self._config.STAGES, why or "skip")
	return true
end

-- Fallbacks; call every frame (Heartbeat) or every few tenths of a second.
function Flow:tick()
	local now = self._clock()
	local stageLimits = self._config.STAGE_FALLBACK_SECONDS or {}
	local stepLimit = self._config.STEP_FALLBACK_SECONDS
	for player, run in pairs(self._players) do
		if not run.done then
			local stage = self:_stageName(run)
			local limit = stageLimits[stage]
			if limit and now - run.stageAt >= limit then
				self:_enter(player, run, run.stageIndex + 1, "fallback")
			elseif stepLimit and self:_steps(stage) and now - run.stepAt >= stepLimit then
				self:_nextStep(player, run, "fallback")
			end
		end
	end
end

-- PlayerRemoving (an unfinished run is simply dropped: its start was counted when it began).
function Flow:remove(player)
	self._players[player] = nil
end

return Flow
