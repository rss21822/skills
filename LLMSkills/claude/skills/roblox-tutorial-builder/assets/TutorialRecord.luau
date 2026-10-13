-- TutorialRecord (template from the roblox-tutorial-builder skill): the persistent record of whether a player was
-- given the tutorial. Copy it into the game, next to TutorialGate.
--
-- One DataStore per environment (Record.storeName), key "u:<UserId>", value
--   { v = 1, starts = <whole number>, startedAt = <server time>?, completedAt = <server time>? }
-- * A missing key is a fresh record (starts 0).
-- * A stored value that fails sanitize is an ERROR, never a fresh record: a broken value must not show the
--   tutorial again and again.
-- * MAX_STARTS = 1: the tutorial is given once ever, on the first login. The start is counted right before the
--   tutorial begins (or before the teleport to a tutorial Place), so quitting half-way, closing the game or a later
--   login never shows it again. A start that surely never reached the player (the teleport threw, or
--   TeleportInitFailed) is given back with refundStart. A teleport with no answer is NOT sure (it may still land):
--   keep its start.
-- * Kept apart from the player profile on purpose: a new profile field usually needs a schema bump that every
--   Place must ship at once. If the project's profile has a safe optional-field mechanism, the same rules can live
--   there instead.
-- The rules are pure (testable in Lune). Record.newStore wraps a DataStore; Record.newMemoryStore is the same API in
-- memory, for Studio (DataStoreService throws in an unpublished file) and for tests.

local Record = {}

Record.VERSION = 1
Record.MAX_STARTS = 1

local MAX_SAFE = 2 ^ 53 - 1

local function finite(n)
	return type(n) == "number" and n == n and n > -math.huge and n < math.huge
end

local function wholeNumber(n)
	return finite(n) and n >= 0 and n == math.floor(n) and n <= MAX_SAFE
end

local function time(n)
	return finite(n) and n > 0
end

-- "<prefix>_<environment>_tutorial_v1", e.g. "ObbyRush_staging_tutorial_v1". Environments never share a store.
function Record.storeName(prefix, environment)
	assert(type(prefix) == "string" and string.match(prefix, "^[%w_]+$") ~= nil, "TutorialRecord.storeName: prefix")
	assert(type(environment) == "string" and string.match(environment, "^[%w_]+$") ~= nil,
		"TutorialRecord.storeName: environment")
	return prefix .. "_" .. environment .. "_tutorial_v" .. Record.VERSION
end

function Record.key(userId)
	return "u:" .. tostring(userId)
end

function Record.fresh()
	return { v = Record.VERSION, starts = 0 }
end

-- A stored value -> a record, or nil + "invalid_record". nil (a missing key) is a fresh record.
function Record.sanitize(raw)
	if raw == nil then
		return Record.fresh()
	end
	if type(raw) ~= "table" or raw.v ~= Record.VERSION or not wholeNumber(raw.starts) then
		return nil, "invalid_record"
	end
	for key in pairs(raw) do
		if key ~= "v" and key ~= "starts" and key ~= "startedAt" and key ~= "completedAt" then
			return nil, "invalid_record"
		end
	end
	if (raw.startedAt ~= nil and not time(raw.startedAt)) or (raw.completedAt ~= nil and not time(raw.completedAt)) then
		return nil, "invalid_record"
	end
	return { v = Record.VERSION, starts = raw.starts, startedAt = raw.startedAt, completedAt = raw.completedAt }
end

-- Whether this record still allows a start: true | false, "completed" | "attempts" | "invalid_record".
function Record.canStart(record)
	if type(record) ~= "table" or not wholeNumber(record.starts) then
		return false, "invalid_record"
	end
	if record.completedAt ~= nil then
		return false, "completed"
	end
	if record.starts >= Record.MAX_STARTS then
		return false, "attempts"
	end
	return true
end

-- Pure updates (also the UpdateAsync transforms).
function Record.started(record, now)
	return { v = Record.VERSION, starts = record.starts + 1, startedAt = now, completedAt = record.completedAt }
end

function Record.completed(record, now)
	return { v = Record.VERSION, starts = record.starts, startedAt = record.startedAt,
		completedAt = record.completedAt or now }
end

-- A start that never reached the player is given back, never below 0.
function Record.unstarted(record)
	return { v = Record.VERSION, starts = math.max(0, record.starts - 1), startedAt = record.startedAt,
		completedAt = record.completedAt }
end

-- 1xx (validation) and 4xx (access) DataStore errors are permanent; 3xx, 5xx and unreadable errors are retried.
function Record.retryable(err)
	local code = string.match(tostring(err), "^(%d%d%d)")
	if code == nil then
		return true
	end
	local first = string.sub(code, 1, 1)
	return first ~= "4" and first ~= "1"
end

local Store = {}
Store.__index = Store

-- opts:
--   name          Record.storeName(prefix, environment) (the real DataStore)
--   dataStore     tests / Studio: an object with GetAsync(key, options) and UpdateAsync(key, fn)
--   now()         server time (default workspace:GetServerTimeNow())
--   wait(seconds) default task.wait; delays = retry delays in seconds (default { 1, 2 }: 3 tries in all)
function Record.newStore(opts)
	assert(type(opts) == "table", "TutorialRecord.newStore: options required")
	local dataStore, readOptions = opts.dataStore, opts.readOptions
	if dataStore == nil then
		assert(type(opts.name) == "string", "TutorialRecord.newStore: name required")
		dataStore = game:GetService("DataStoreService"):GetDataStore(opts.name)
		-- Read what another server (the tutorial Place) wrote moments ago, not a cached copy.
		readOptions = Instance.new("DataStoreGetOptions")
		readOptions.UseCache = false
	end
	return setmetatable({
		_store = dataStore,
		_readOptions = readOptions,
		_now = opts.now or function()
			return workspace:GetServerTimeNow()
		end,
		_wait = opts.wait or function(seconds)
			task.wait(seconds)
		end,
		_delays = opts.delays or { 1, 2 },
	}, Store)
end

function Store:_call(fn)
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local delay = self._delays[attempt]
		if delay == nil or not Record.retryable(result) then
			return false, result
		end
		self._wait(delay)
	end
end

-- ok, record | false, "unavailable" | "invalid_record"
function Store:read(userId)
	local ok, stored = self:_call(function()
		return self._store:GetAsync(Record.key(userId), self._readOptions)
	end)
	if not ok then
		return false, "unavailable"
	end
	local record, reason = Record.sanitize(stored)
	if not record then
		return false, reason
	end
	return true, record
end

-- One UpdateAsync with a pure transform. A stored value that fails sanitize cancels the write (nothing is
-- overwritten), and so does a transform that returns nil, why: the call returns false, why.
function Store:_update(userId, transform)
	local now = self._now()
	local rejected = nil
	local ok, result = self:_call(function()
		rejected = nil
		return self._store:UpdateAsync(Record.key(userId), function(old)
			local record, reason = Record.sanitize(old)
			if not record then
				rejected = reason
				return nil
			end
			local nextRecord, why = transform(record, now)
			if nextRecord == nil then
				rejected = why or "cancelled"
			end
			return nextRecord
		end)
	end)
	if not ok then
		return false, "unavailable"
	end
	if rejected then
		return false, rejected
	end
	local record = Record.sanitize(result)
	if not record or result == nil then
		return false, "invalid_record"
	end
	return true, record
end

-- The stored record decides, not an earlier read (another server may have written since):
-- false, "completed" | "attempts" when the player must not start after all.
function Store:markStarted(userId)
	return self:_update(userId, function(record, now)
		local can, why = Record.canStart(record)
		if not can then
			return nil, why
		end
		return Record.started(record, now)
	end)
end

function Store:markCompleted(userId)
	return self:_update(userId, Record.completed)
end

function Store:refundStart(userId)
	return self:_update(userId, Record.unstarted)
end

-- The same API kept in memory: for Studio (no DataStore in an unpublished file; every Play starts fresh) and tests.
function Record.newMemoryStore(opts)
	opts = opts or {}
	local data = opts.data or {}
	local fake = {}
	function fake:GetAsync(key)
		return data[key]
	end
	function fake:UpdateAsync(key, fn)
		local value = fn(data[key])
		if value ~= nil then
			data[key] = value
		end
		return data[key]
	end
	local store = Record.newStore({ dataStore = fake, now = opts.now or os.time, wait = function() end, delays = {} })
	store.data = data
	return store
end

return Record
