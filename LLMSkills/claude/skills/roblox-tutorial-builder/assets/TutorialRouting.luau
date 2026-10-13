-- TutorialRouting (template from the roblox-tutorial-builder skill): the Lobby sends a player who should get the
-- tutorial (TutorialGate) to a NEW reserved server of the tutorial Place, alone, and only when nothing else holds
-- the player. Server only; step it from a Heartbeat: routing:step().
--
-- Each player is decided once per visit:
--   * the gate's quick checks first (an arrival from an own Place, a tester, the game's "experienced" signal; a
--     signal not known yet is looked at again every POLL_SECONDS);
--   * the player waits until free (no party, queue, menu flow or other teleport holds it: opts.isFree), polled;
--   * the record is read once per visit (gate:decide), then the player is locked (opts.lock: the Lobby's shared
--     transfer lock, so nothing else starts meanwhile), the start is counted (gate:begin; testers count nothing)
--     and the player alone is teleported (opts.teleport).
-- A failed read, write or teleport unlocks the player and leaves it in the Lobby for this visit (opts.log). A
-- teleport that surely failed (the send threw, or TeleportInitFailed) gives the start back (gate:refund); so does a
-- player who left before the send. A send with no answer for SEND_TIMEOUT_SECONDS is released WITHOUT a refund (it
-- may still land). BREAKER_FAILURES failed sends in a row (any players) pause the routing in this server for
-- BREAKER_SECONDS, so an unreachable tutorial Place does not hold every new player once per visit.
-- Build it only outside Studio (no DataStore, no teleport) and only while the tutorial PlaceId is set (0 = the
-- Owner has not created the Place yet: routing off).
--
-- opts:
--   gate                              TutorialGate
--   placeId                           the tutorial Place
--   players()                         the Players in this server
--   isLive(player)                    still the same Player in this server (player.Parent == Players)
--   isFree(player)                    nothing else holds the player
--   lock(player), unlock(player)      the Lobby's shared transfer lock
--   beforeTeleport({player}) -> bool  optional: end what the player is doing (practice, a menu); false = later
--   teleport(placeId, players, options, onFailed) -> ok, err   (the game's safe teleport helper)
--   newOptions() -> TeleportOptions   with ShouldReserveServer = true (a new server per student)
--   log(stage, code, player, detail)  optional
--   clock(), spawn(fn)                optional os.clock / task.spawn (tests)

local Routing = {}
Routing.__index = Routing
Routing.POLL_SECONDS = 0.5
Routing.RETRY_SECONDS = 5
Routing.SEND_TIMEOUT_SECONDS = 60
Routing.BREAKER_FAILURES = 3
Routing.BREAKER_SECONDS = 600

function Routing.new(opts)
	assert(type(opts) == "table", "TutorialRouting.new: options required")
	assert(type(opts.gate) == "table", "TutorialRouting.new: gate required")
	for _, name in ipairs({ "players", "isLive", "isFree", "lock", "unlock", "teleport", "newOptions" }) do
		assert(type(opts[name]) == "function", "TutorialRouting.new: " .. name .. " required")
	end
	assert(type(opts.placeId) == "number" and opts.placeId > 0, "TutorialRouting.new: placeId required")
	return setmetatable({
		_o = opts, _state = {}, _retryAt = {}, _sentAt = {}, _destroyed = false,
		_failStreak = 0, _pausedUntil = -math.huge,
		_clock = opts.clock or os.clock,
		_spawn = opts.spawn or function(fn)
			task.spawn(fn)
		end,
	}, Routing)
end

-- nil (undecided) | waiting | checking | locked | teleporting | skip_<why> | failed_store | failed_teleport | failed
function Routing:status(player)
	return self._state[player]
end

function Routing:forget(player)
	if self._state[player] == "teleporting" then
		self._failStreak = 0 -- left while being sent: the tutorial Place can be reached
	end
	self._state[player], self._retryAt[player], self._sentAt[player] = nil, nil, nil
	self._o.gate:forget(player)
end

function Routing:destroy()
	self._destroyed = true
	table.clear(self._state)
	table.clear(self._retryAt)
	table.clear(self._sentAt)
end

function Routing:_log(stage, code, player, detail)
	if type(self._o.log) == "function" then
		pcall(self._o.log, stage, code, player, detail)
	end
end

function Routing:_refund(player)
	self._spawn(function()
		local ran, err = pcall(self._o.gate.refund, self._o.gate, player)
		if not ran then
			self:_log("refund", "exception", player, err)
		end
	end)
end

function Routing:_noteFailure(player)
	self._failStreak += 1
	if self._failStreak >= Routing.BREAKER_FAILURES then
		self._failStreak = 0
		self._pausedUntil = self._clock() + Routing.BREAKER_SECONDS
		self:_log("teleport", "paused", player)
	end
end

-- Releases the lock this routing holds (locked / teleporting) and records the outcome. refund: the start surely
-- never reached the player.
function Routing:_release(player, outcome, refund)
	local state = self._state[player]
	if state == "locked" or state == "teleporting" then
		pcall(self._o.unlock, player)
	end
	self._sentAt[player] = nil
	if state ~= nil then
		self._state[player] = outcome
		if outcome == "waiting" then
			self._retryAt[player] = self._clock() + Routing.RETRY_SECONDS
		end
		if state == "teleporting" and outcome == "failed_teleport" then
			self:_noteFailure(player)
		end
	end
	if refund then
		self:_refund(player)
	end
end

function Routing:step()
	if self._destroyed then
		return
	end
	local now = self._clock()
	local paused = now < self._pausedUntil
	for _, player in ipairs(self._o.players()) do
		local state = self._state[player]
		if state == "teleporting" then
			local sentAt = self._sentAt[player]
			if sentAt and now - sentAt > Routing.SEND_TIMEOUT_SECONDS and self._o.isLive(player) then
				self:_log("teleport", "timeout", player)
				self:_release(player, "failed_teleport", false)
			end
		elseif not paused and (state == nil or state == "waiting") and now >= (self._retryAt[player] or -math.huge) then
			self:_consider(player)
		end
	end
end

function Routing:_consider(player)
	if self._state[player] == nil then
		local quick, why = self._o.gate:precheck(player)
		if quick == "later" then
			self._retryAt[player] = self._clock() + Routing.POLL_SECONDS
			return
		end
		if quick == "skip" then
			self._state[player] = "skip_" .. tostring(why)
			return
		end
		self._state[player] = "waiting"
	end
	if not self._o.isFree(player) then
		self._retryAt[player] = self._clock() + Routing.POLL_SECONDS
		return
	end
	self._state[player] = "checking"
	self._spawn(function()
		local ok, err = pcall(self._route, self, player)
		if not ok then
			self:_release(player, "failed")
			self:_log("route", "exception", player, err)
		end
	end)
end

function Routing:_current(player)
	return not self._destroyed and self._o.isLive(player) and self._state[player] ~= nil
end

function Routing:_route(player)
	local o, gate = self._o, self._o.gate
	local verdict, why = gate:decide(player)
	if not self:_current(player) then
		return
	end
	if not verdict then
		if why == "not_loaded" then
			self._state[player] = nil
			self._retryAt[player] = self._clock() + Routing.POLL_SECONDS
		elseif why == "store_unavailable" or why == "store_invalid_record" then
			self._state[player] = "failed_store"
			self:_log("read", why, player)
		else
			self._state[player] = "skip_" .. tostring(why)
		end
		return
	end
	if not o.isFree(player) then
		return self:_release(player, "waiting")
	end
	-- Committed: hold the player before any further yield so nothing else starts meanwhile.
	o.lock(player)
	self._state[player] = "locked"
	if o.beforeTeleport and o.beforeTeleport({ player }) ~= true then
		return self:_release(player, "waiting")
	end
	if not self:_current(player) then
		return self:_release(player, "failed")
	end
	local okStart, started = gate:begin(player)
	if not self:_current(player) then
		-- Gone (or the routing stopped) while the start was counted: nothing was sent, so give it back.
		return self:_release(player, "failed", okStart == true)
	end
	if not okStart then
		if started == "completed" or started == "attempts" then
			return self:_release(player, "skip_" .. started) -- the stored record says no after all
		end
		self:_log("start", tostring(started), player)
		return self:_release(player, "failed_store")
	end
	self._state[player] = "teleporting"
	self._sentAt[player] = self._clock()
	local sent, err = o.teleport(o.placeId, { player }, o.newOptions(), function(_, resultName, message)
		if self._state[player] == "teleporting" then
			self:_log("teleport", tostring(resultName), player, message)
			self:_release(player, "failed_teleport", true)
		end
	end)
	if not sent and self._state[player] == "teleporting" then
		self:_log("teleport", "send_failed", player, err)
		self:_release(player, "failed_teleport", true)
	end
end

return Routing
