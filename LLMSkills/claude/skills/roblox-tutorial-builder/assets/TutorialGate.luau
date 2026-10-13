-- TutorialGate (template from the roblox-tutorial-builder skill): who gets the tutorial on this join. Server only.
--
-- * Testers (Roblox UserIds in opts.testers) get it on EVERY login. No record is read or written for them, so
--   their own first-login state is never used up and the tutorial can be checked again and again.
-- * Everyone else gets it on the first login only: the record (TutorialRecord) has no start and no completion,
--   and (optional) the game's own signal says the player is new (opts.isExperienced: e.g. matches played > 0,
--   which also keeps out players who were here before the tutorial existed).
-- * A login is a join from outside the experience. Roblox sets JoinData.SourcePlaceId when a player was teleported
--   in, so an arrival from one of the experience's own Places (a match, the tutorial Place, another server of this
--   Place) is not a login, for testers too: nobody loops between the Lobby and the tutorial.
-- * A failed read or write skips the tutorial for this visit and never blocks the game; nothing was counted, so the
--   next login tries again.
--
-- In-place tutorial (the tutorial runs in this server):
--   local verdict, why = gate:decide(player)     -- after the profile loaded; yields (DataStore read)
--   if verdict == nil and why == "not_loaded" then (retry a little later) end
--   if verdict and gate:begin(player) then startTutorial(player) end
--   ...when it ends: gate:complete(player); on PlayerRemoving: gate:forget(player)
-- Tutorial Place: TutorialRouting drives the same gate around the teleport, and the tutorial Place calls
-- gate:complete (or the record store's markCompleted) when the player finishes.
--
-- opts:
--   store           TutorialRecord store (:read, :markStarted, :markCompleted, :refundStart)
--   rules           TutorialRecord (the pure rules); default require(script.Parent.TutorialRecord)
--   testers         { UserId, ... } for THIS environment; anything that is not a whole number > 0 is ignored
--   ownPlaceIds     { PlaceId, ... } of the experience (this Place is always included)
--   isExperienced   optional function(player) -> true | false | nil (nil: not known yet, decide later)
--   log             optional function(event, player, detail)

local Gate = {}
Gate.__index = Gate

local function wholePositive(n)
	return type(n) == "number" and n > 0 and n == math.floor(n) and n < 2 ^ 53
end

function Gate.new(opts)
	assert(type(opts) == "table", "TutorialGate.new: options required")
	assert(type(opts.store) == "table", "TutorialGate.new: store required")
	local rules = opts.rules or require(script.Parent.TutorialRecord)
	local testers = {}
	for _, id in ipairs(opts.testers or {}) do
		if wholePositive(id) then
			testers[id] = true
		end
	end
	local own = {}
	for _, id in ipairs(opts.ownPlaceIds or {}) do
		if wholePositive(id) then
			own[id] = true
		end
	end
	local ok, placeId = pcall(function()
		return game.PlaceId
	end)
	if ok and wholePositive(placeId) then
		own[placeId] = true
	end
	return setmetatable({
		_store = opts.store, _rules = rules, _testers = testers, _own = own,
		_isExperienced = opts.isExperienced, _log = opts.log, _record = {},
	}, Gate)
end

function Gate:_note(event, player, detail)
	if type(self._log) == "function" then
		pcall(self._log, event, player, detail)
	end
end

function Gate:isTester(player)
	return self._testers[player.UserId] == true
end

-- A join from outside the experience (not a teleport from one of its own Places).
function Gate:isLogin(player)
	local ok, join = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(join) ~= "table" then
		return true
	end
	local source = join.SourcePlaceId
	return not (type(source) == "number" and self._own[source] == true)
end

-- No yield. "tester" | "check" (read the record next) | "later" (the game's signal is not known yet) | "skip", why
function Gate:precheck(player)
	if not self:isLogin(player) then
		return "skip", "arrival"
	end
	if self:isTester(player) then
		return "tester"
	end
	if self._isExperienced then
		local experienced = self._isExperienced(player)
		if experienced == nil then
			return "later", "not_loaded"
		end
		if experienced then
			return "skip", "experienced"
		end
	end
	return "check"
end

-- Yields (one record read per visit). "tester" | "first_time" | nil, why
-- why: "arrival" | "not_loaded" | "experienced" | "completed" | "attempts" | "store_unavailable" |
--      "store_invalid_record"
function Gate:decide(player)
	local quick, why = self:precheck(player)
	if quick == "tester" then
		return "tester"
	end
	if quick ~= "check" then
		return nil, why
	end
	local record = self._record[player]
	if record == nil then
		local ok, value = self._store:read(player.UserId)
		if not ok then
			self:_note("read_failed", player, value)
			return nil, "store_" .. tostring(value)
		end
		record = value
		self._record[player] = record
	end
	local can, reason = self._rules.canStart(record)
	if not can then
		return nil, reason
	end
	return "first_time"
end

-- Counts the start right before the tutorial begins (or the teleport is sent). Testers write nothing.
-- false, why: the stored record says no after all (another server wrote meanwhile) or the write failed -- then do
-- not start the tutorial on this visit (it would run uncounted and come back next login).
function Gate:begin(player)
	if self:isTester(player) then
		return true, "tester"
	end
	local ok, value = self._store:markStarted(player.UserId)
	if ok then
		self._record[player] = value
	else
		self:_note("start_failed", player, value)
	end
	return ok, value
end

-- The start surely never reached the player (the teleport threw / TeleportInitFailed): give it back.
function Gate:refund(player)
	if self:isTester(player) then
		return true, "tester"
	end
	local ok, value = self._store:refundStart(player.UserId)
	if not ok then
		self:_note("refund_failed", player, value)
	end
	return ok, value
end

-- The player finished. Testers write nothing.
function Gate:complete(player)
	if self:isTester(player) then
		return true, "tester"
	end
	local ok, value = self._store:markCompleted(player.UserId)
	if not ok then
		self:_note("complete_failed", player, value)
	end
	return ok, value
end

-- Call on PlayerRemoving (the record read is cached per visit).
function Gate:forget(player)
	self._record[player] = nil
end

return Gate
