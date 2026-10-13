-- Lune test for the roblox-tutorial-builder templates (TutorialRecord, TutorialGate, TutorialRouting,
-- BasicControlsDetector, TutorialConfig, TutorialFlow, TutorialGuideController; the examples compile).
-- Run from the skill folder (or pass the assets folder):
--   lune run assets/tests/test_tutorial_templates.luau [assets/]
-- After copying the templates into a game, copy this test too and point ROOT at the game's copies; keep every case
-- (they are the first-login / tester contract) and add the game's own.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local ROOT = process.args[1] or "assets/"
local checks = 0
local function check(cond, msg)
	checks += 1
	if not cond then
		error("FAIL: " .. msg, 2)
	end
end

local function load(name, env)
	env = env or {}
	env.require = env.require or function()
		error("unexpected require")
	end
	return luau.load(fs.readFile(ROOT .. name), { environment = env })()
end

local Record = load("TutorialRecord.luau")

-- Record rules ------------------------------------------------------------------------------------------------
check(Record.MAX_STARTS == 1, "first login only: one start")
check(Record.storeName("ObbyRush", "staging") == "ObbyRush_staging_tutorial_v1", "store name per environment")
check(not pcall(Record.storeName, "Obby Rush", "staging"), "store name prefix is checked")
check(Record.key(42) == "u:42", "key u:<UserId>")
local fresh = Record.sanitize(nil)
check(fresh.v == 1 and fresh.starts == 0, "missing key = fresh record")
check(Record.sanitize({ v = 1, starts = 1, startedAt = 10, completedAt = 20 }).completedAt == 20, "full record")
check(Record.sanitize({ v = 2, starts = 0 }) == nil, "other version rejected")
check(Record.sanitize({ v = 1, starts = 1.5 }) == nil, "fractional starts rejected")
check(Record.sanitize({ v = 1, starts = -1 }) == nil, "negative starts rejected")
check(Record.sanitize({ v = 1, starts = 0, extra = true }) == nil, "unknown field rejected")
check(Record.sanitize({ v = 1, starts = 0, startedAt = -5 }) == nil, "bad time rejected")
check(Record.sanitize("x") == nil, "not a table rejected")
check(Record.canStart(fresh) == true, "fresh -> can start")
check(select(2, Record.canStart({ v = 1, starts = 1 })) == "attempts", "started once -> never again")
check(select(2, Record.canStart({ v = 1, starts = 0, completedAt = 5 })) == "completed", "completed -> never")
check(select(2, Record.canStart(nil)) == "invalid_record", "no record -> invalid")
local started = Record.started(fresh, 100)
check(started.starts == 1 and started.startedAt == 100, "started counts")
check(Record.completed(started, 200).completedAt == 200, "completed stamps")
check(Record.completed({ v = 1, starts = 1, completedAt = 50 }, 200).completedAt == 50, "first completion kept")
check(Record.unstarted(started).starts == 0 and Record.unstarted(fresh).starts == 0, "refund never below 0")
check(Record.retryable("502: busy") and Record.retryable("oops") and not Record.retryable("403: denied")
	and not Record.retryable("105: too big"), "retry policy")

-- Record store over a fake DataStore -----------------------------------------------------------------------------
local function fakeStore()
	local ds = { data = {}, gets = 0, updates = 0, failGet = 0, failUpdate = 0, failCode = "502: busy" }
	function ds:GetAsync(key)
		self.gets += 1
		if self.failGet > 0 then
			self.failGet -= 1
			error(self.failCode, 0) -- engine errors carry no script position
		end
		return self.data[key]
	end
	function ds:UpdateAsync(key, fn)
		self.updates += 1
		if self.failUpdate > 0 then
			self.failUpdate -= 1
			error(self.failCode, 0)
		end
		local value = fn(self.data[key])
		if value ~= nil then
			self.data[key] = value
		end
		return value
	end
	return ds
end

local waits = {}
local ds = fakeStore()
local store = Record.newStore({ dataStore = ds, now = function() return 5 end, wait = function(s) table.insert(waits, s) end })
local ok, rec = store:read(1)
check(ok and rec.starts == 0, "read: missing -> fresh")
ds.data["u:2"] = { v = 9 }
ok, rec = store:read(2)
check(not ok and rec == "invalid_record", "read: broken value is an error, not fresh")
ok, rec = store:markStarted(2)
check(not ok and rec == "invalid_record" and ds.data["u:2"].v == 9, "a broken value is never overwritten")
ok, rec = store:markStarted(3)
check(ok and rec.starts == 1 and ds.data["u:3"].startedAt == 5, "markStarted counts")
ok, rec = store:markStarted(3)
check(not ok and rec == "attempts" and ds.data["u:3"].starts == 1, "markStarted: the stored record says no")
ok, rec = store:refundStart(3)
check(ok and rec.starts == 0, "refund")
ok, rec = store:markCompleted(3)
check(ok and ds.data["u:3"].completedAt == 5, "markCompleted")
ok, rec = store:markStarted(3)
check(not ok and rec == "completed", "completed -> no start")
ds.failGet = 2
ok, rec = store:read(4)
check(ok and #waits == 2 and waits[1] == 1 and waits[2] == 2, "transient read errors are retried (1 s, 2 s)")
ds.failGet, ds.failCode = 1, "403: denied"
local getsBefore = ds.gets
ok, rec = store:read(5)
check(not ok and rec == "unavailable" and ds.gets == getsBefore + 1, "permanent errors are not retried")
ds.failCode = "502: busy"
ds.failUpdate = 3
ok, rec = store:markStarted(6)
check(not ok and rec == "unavailable" and ds.data["u:6"] == nil, "a write that keeps failing reports unavailable")

local memory = Record.newMemoryStore()
ok, rec = memory:markStarted(7)
check(ok and rec.starts == 1 and memory.data["u:7"].starts == 1, "memory store: same API")

-- Gate --------------------------------------------------------------------------------------------------------------
local Gate = load("TutorialGate.luau")
local function player(id, source)
	local p = { UserId = id, live = true }
	function p:GetJoinData()
		return { SourcePlaceId = source }
	end
	return p
end

local gds = fakeStore()
local gstore = Record.newStore({ dataStore = gds, now = function() return 9 end, wait = function() end })
local experienced = {}
local gate = Gate.new({ store = gstore, rules = Record, testers = { 100, 101, "102", -5, 1.5, 0 },
	ownPlaceIds = { 500, 501 }, isExperienced = function(p) return experienced[p.UserId] end })

local t1 = player(100)
check(gate:decide(t1) == "tester", "a tester gets it")
check(gate:begin(t1) == true and gate:complete(t1) == true and gate:refund(t1) == true, "tester calls succeed")
check(gds.gets == 0 and gds.updates == 0, "nothing is read or written for a tester")
gate:forget(t1)
check(gate:decide(player(100)) == "tester", "a tester gets it again on the next login")
check(gate:decide(player(100, 500)) == nil and select(2, gate:decide(player(100, 500))) == "arrival",
	"a tester arriving from an own Place is not sent again (no loop)")
check(gate:decide(player(100, 999)) == "tester", "an arrival from another experience is a login")
experienced[102] = false
check(gate:isTester(player(102)) == false, "only whole positive UserIds count (\"102\" is not 102)")

local newbie = player(1)
check(select(2, gate:decide(newbie)) == "not_loaded", "the game's signal not known yet -> decide later")
experienced[1] = false
check(gate:decide(newbie) == "first_time", "a new player gets it")
check(gds.gets == 1, "the record is read")
check(gate:decide(newbie) == "first_time" and gds.gets == 1, "read once per visit")
check(gate:begin(newbie) == true and gds.data["u:1"].starts == 1, "begin counts the start")
gate:complete(newbie)
check(gds.data["u:1"].completedAt == 9, "complete stamps the record")
gate:forget(newbie)
local again = player(1)
check(select(2, gate:decide(again)) == "completed", "next login: never again")

local quitter = player(2)
experienced[2] = false
check(gate:decide(quitter) == "first_time" and gate:begin(quitter) == true, "started")
gate:forget(quitter)
check(select(2, gate:decide(player(2))) == "attempts", "started but not finished -> not again (first login only)")

local veteran = player(3)
experienced[3] = true
local gets = gds.gets
check(select(2, gate:decide(veteran)) == "experienced" and gds.gets == gets, "an experienced player: no read")

local unlucky = player(4)
experienced[4] = false
gds.failGet = 9
check(select(2, gate:decide(unlucky)) == "store_unavailable", "a failed read skips this visit")
gds.failGet = 0
gate:forget(unlucky)
check(gate:decide(player(4)) == "first_time", "and the next login tries again")
gds.failUpdate = 9
local okBegin, why = gate:begin(player(4))
check(not okBegin and why == "unavailable" and gds.data["u:4"] == nil, "a failed start write: do not start")
gds.failUpdate = 0

local ok2, problem = pcall(Gate.new, { rules = Record })
check(not ok2, "store required: " .. tostring(problem))

-- Routing -----------------------------------------------------------------------------------------------------------
local Routing = load("TutorialRouting.luau", { os = { clock = function() return 0 end } })
local function newWorld(testers)
	local w = { clock = 0, teleports = {}, locks = {}, logs = {}, free = {}, before = true, sendOk = true,
		experienced = {}, players = {} }
	w.ds = fakeStore()
	w.store = Record.newStore({ dataStore = w.ds, now = function() return 5 end, wait = function() end })
	w.gate = Gate.new({ store = w.store, rules = Record, testers = testers or {}, ownPlaceIds = { 111, 999 },
		isExperienced = function(p) return w.experienced[p] end })
	function w.player(id, source)
		local p = player(id, source)
		table.insert(w.players, p)
		w.free[p] = true
		return p
	end
	function w.leave(p)
		p.live = false
		table.remove(w.players, table.find(w.players, p))
		w.r:forget(p)
	end
	w.r = Routing.new({
		gate = w.gate, placeId = 999,
		players = function() return w.players end,
		isLive = function(p) return p.live end,
		isFree = function(p) return w.free[p] == true and not w.locks[p] end,
		lock = function(p) w.locks[p] = true end,
		unlock = function(p) w.locks[p] = nil end,
		beforeTeleport = function() if w.beforeHook then w.beforeHook() end return w.before end,
		teleport = function(placeId, list, options, onFailed)
			table.insert(w.teleports, { placeId = placeId, player = list[1], options = options, onFailed = onFailed })
			if w.onTeleport then w.onTeleport() end
			return w.sendOk, if w.sendOk then nil else "boom"
		end,
		newOptions = function() return { reserved = true } end,
		log = function(stage, code, p) table.insert(w.logs, { stage = stage, code = code, p = p }) end,
		clock = function() return w.clock end,
		spawn = function(fn) fn() end,
	})
	return w
end

do -- a first-time player: waits for the game's signal, then is counted, locked and sent once
	local w = newWorld()
	local p = w.player(1)
	w.r:step()
	check(#w.teleports == 0 and w.r:status(p) == nil, "nothing before the game's signal is known")
	w.experienced[p] = false
	w.r:step()
	check(#w.teleports == 0, "looked at again after POLL_SECONDS only")
	w.clock += Routing.POLL_SECONDS
	w.r:step()
	check(#w.teleports == 1 and w.teleports[1].placeId == 999 and w.teleports[1].options.reserved,
		"sent to a new reserved server of the tutorial Place")
	check(w.ds.data["u:1"].starts == 1, "the start was counted before the send")
	check(w.locks[p] == true and w.r:status(p) == "teleporting", "locked while it goes")
	w.r:step()
	check(#w.teleports == 1, "sent once")
	w.teleports[1].onFailed(p, "Failure", "nope")
	check(w.locks[p] == nil and w.r:status(p) == "failed_teleport", "a failed teleport unlocks, stays in the Lobby")
	check(w.ds.data["u:1"].starts == 0, "a teleport that surely failed gives its start back")
	w.r:step()
	check(#w.teleports == 1, "not retried this visit")
	w.leave(p)
	local back = w.player(1)
	w.experienced[back] = false
	w.r:step()
	check(#w.teleports == 2 and w.ds.data["u:1"].starts == 1, "the next login sends the player who never got there")
	w.leave(back) -- it arrived in the tutorial and left the game half-way
	local later = w.player(1)
	w.experienced[later] = false
	w.r:step()
	check(#w.teleports == 2 and w.r:status(later) == "skip_attempts", "a later login: never again, finished or not")
end

do -- testers: every login, nothing counted, never on an arrival from an own Place
	local w = newWorld({ 71 })
	local tester = w.player(71)
	w.experienced[tester] = true -- a veteran account
	local returning = w.player(72, 999)
	w.experienced[returning] = false
	w.r:step()
	check(#w.teleports == 1 and w.teleports[1].player == tester, "a tester is sent whatever the profile says")
	check(w.r:status(returning) == "skip_arrival", "nobody coming back from the tutorial is sent again")
	check(w.ds.gets == 0 and w.ds.updates == 0, "nothing is read or written for a tester")
	w.teleports[1].onFailed(tester, "Failure", "nope")
	check(w.ds.updates == 0 and not w.locks[tester], "a tester's failed send: unlocked, no refund write")
	w.leave(tester)
	local next = w.player(71)
	w.r:step()
	check(#w.teleports == 2, "a tester's next login sends again")
	w.leave(next)
	local fromTutorial = w.player(71, 999)
	w.r:step()
	check(#w.teleports == 2 and w.r:status(fromTutorial) == "skip_arrival", "a tester back from the tutorial: not again")
end

do -- experienced, completed, arrivals: never sent, no writes
	local w = newWorld()
	local vet = w.player(2)
	w.experienced[vet] = true
	local done = w.player(3)
	w.experienced[done] = false
	w.ds.data["u:3"] = { v = 1, starts = 1, completedAt = 9 }
	local fromMatch = w.player(5, 111)
	w.experienced[fromMatch] = false
	w.r:step()
	check(#w.teleports == 0, "none of them is sent")
	check(w.r:status(vet) == "skip_experienced" and w.r:status(done) == "skip_completed"
		and w.r:status(fromMatch) == "skip_arrival", "each skip has its reason")
	check(w.ds.updates == 0, "no write for a skipped player")
end

do -- busy, practice that cannot end, store failures, timeouts, leaving mid-start
	local w = newWorld()
	local p = w.player(10)
	w.experienced[p] = false
	w.free[p] = false
	w.r:step()
	check(#w.teleports == 0 and w.r:status(p) == "waiting", "waits while busy")
	w.free[p] = true
	w.before = false
	w.clock += Routing.POLL_SECONDS
	w.r:step()
	check(#w.teleports == 0 and w.locks[p] == nil and w.r:status(p) == "waiting", "cannot leave yet: unlocked, waits")
	check(w.ds.updates == 0, "no start counted when the move cannot begin")
	w.before = true
	w.r:step()
	check(#w.teleports == 0, "retry waits RETRY_SECONDS")
	w.clock += Routing.RETRY_SECONDS + 0.1
	w.r:step()
	check(#w.teleports == 1 and w.ds.gets == 1, "sent after the retry; the record read once per visit")

	local w2 = newWorld()
	local q = w2.player(11)
	w2.experienced[q] = false
	w2.ds.failGet = 9
	w2.r:step()
	check(w2.r:status(q) == "failed_store" and #w2.teleports == 0 and w2.locks[q] == nil, "unreadable record: stays")

	local w3 = newWorld()
	local s = w3.player(12)
	w3.experienced[s] = false
	w3.ds.failUpdate = 9
	w3.r:step()
	check(w3.r:status(s) == "failed_store" and #w3.teleports == 0 and w3.locks[s] == nil, "start not counted: not sent")

	local w4 = newWorld()
	w4.sendOk = false
	local u = w4.player(13)
	w4.experienced[u] = false
	w4.r:step()
	check(w4.r:status(u) == "failed_teleport" and w4.ds.data["u:13"].starts == 0, "a send that throws refunds")

	local w5 = newWorld()
	local v = w5.player(14)
	w5.experienced[v] = false
	w5.r:step()
	w5.clock += Routing.SEND_TIMEOUT_SECONDS + 1
	w5.r:step()
	check(w5.r:status(v) == "failed_teleport" and w5.locks[v] == nil, "an unanswered send is released")
	check(w5.ds.data["u:14"].starts == 1, "an unanswered send keeps its start (it may still land)")
	w5.teleports[1].onFailed(v, "Failure", "late")
	check(w5.ds.data["u:14"].starts == 1, "a late failure after the release refunds nothing")

	local w6 = newWorld()
	local x = w6.player(15)
	w6.experienced[x] = false
	w6.beforeHook = function() end
	local realBegin = w6.gate.begin
	w6.gate.begin = function(g, pl)
		local a, b = realBegin(g, pl)
		pl.live = false -- the player left while the start was being written
		return a, b
	end
	w6.r:step()
	check(#w6.teleports == 0 and w6.ds.data["u:15"].starts == 0, "left before the send: the start is given back")

	local w7 = newWorld()
	local y = w7.player(16)
	w7.experienced[y] = false
	w7.beforeHook = function() w7.ds.data["u:16"] = { v = 1, starts = 0, completedAt = 77 } end
	w7.r:step()
	check(w7.r:status(y) == "skip_completed" and w7.locks[y] == nil, "completed meanwhile: not sent, unlocked")
end

do -- the breaker
	local w = newWorld()
	w.sendOk = false
	for i = 1, Routing.BREAKER_FAILURES do
		local p = w.player(40 + i)
		w.experienced[p] = false
	end
	w.r:step()
	check(#w.teleports == Routing.BREAKER_FAILURES, "each one was tried")
	w.sendOk = true
	local late = w.player(50)
	w.experienced[late] = false
	w.clock += 1
	w.r:step()
	check(w.r:status(late) == nil, "paused: nobody else is sent")
	w.clock += Routing.BREAKER_SECONDS
	w.r:step()
	check(w.r:status(late) == "teleporting", "sent again after the pause")
end

-- BasicControlsDetector --------------------------------------------------------------------------------------------
local Detector = load("BasicControlsDetector.luau", { Vector3 = roblox.Vector3 })
local V = roblox.Vector3.new
local look = V(0, -0.3, -1) -- a camera looking -Z, a little down
local f, r = Detector.moveIntent(V(0, 0, -1), look)
check(f > 0.99 and math.abs(r) < 1e-6, "forward")
f, r = Detector.moveIntent(V(1, 0, 0), look)
check(math.abs(f) < 1e-6 and r > 0.99, "right is +X when looking -Z")
check(Detector.isMoving("move_left", V(-1, 0, 0), look) and Detector.isMoving("move_back", V(0, 0, 1), look),
	"left / back")
check(Detector.isMoving("move_side", V(-1, 0, 0), look) and not Detector.isMoving("move_side", V(0, 0, -1), look),
	"side")
check(not Detector.isMoving("move_any", V(0, 0, 0), look), "standing still")
check(not Detector.isMoving("move_forward", V(0, 0, -0.2), look), "a light touch is inside the deadzone")
f, r = Detector.moveIntent(V(0, 0, -1), V(0, -1, 0))
check(f == 0 and r == 0, "looking straight down: no frame")
check(not pcall(Detector.isMoving, "fly", V(0, 0, -1), look), "unknown action errors")
local hold = Detector.newHold(1)
local progress, done
for _ = 1, 3 do
	progress, done = hold:step(0.2, true)
end
check(progress > 0.59 and not done, "hold accumulates")
progress = hold:step(0.2, false)
check(progress > 0.59, "letting go keeps the progress")
for _ = 1, 3 do
	progress, done = hold:step(0.2, true)
end
check(done and progress == 1, "hold completes")
local frame = Detector.newHold(1)
check(frame:step(5, true) == 0.25, "a long frame counts as 0.25 s")
local counter = Detector.newCounter(2)
counter:step(true)
counter:step(true)
local count, finished = counter:step(false)
check(count == 1 and not finished, "holding the button counts once")
count, finished = counter:step(true)
check(count == 2 and finished, "two presses")
local turn = Detector.newTurn(90)
turn:step(V(0, 0, -1))
local turned, turnedDone = turn:step(V(1, 0, -1).Unit)
check(math.abs(turned - 0.5) < 1e-4 and not turnedDone, "45 degrees of a 90 degree look")
turn:step(V(0, -1, 0))
check(math.abs(turn.turned - 45) < 1e-3, "looking straight down adds nothing")
turned, turnedDone = turn:step(V(1, 0, 0))
check(turnedDone and turned == 1, "90 degrees turned, either way")

-- TutorialConfig -----------------------------------------------------------------------------------------------------
local Config = load("TutorialConfig.luau", { table = table })
local valid, problems = Config.validate()
check(valid, "the template is valid: " .. table.concat(problems or {}, "; "))
local broken = { STAGES = { "welcome", "core" }, BASICS = {}, TESTER_USER_IDS = { staging = { "7" } },
	STEP_FALLBACK_SECONDS = 0 }
valid, problems = Config.validate(broken)
check(not valid and #problems == 5 and string.find(table.concat(problems, ";"), "STAGE_FALLBACK_SECONDS.welcome", 1, true),
	"missing basics, empty BASICS, a bad tester id, no step fallback and a stage without fallback are caught")
local noPrompt = table.clone(Config.BASICS[1])
noPrompt.prompt = { keyboard = "Hold W" }
valid, problems = Config.validate({ STAGES = Config.STAGES, BASICS = { noPrompt }, TESTER_USER_IDS = {},
	STEP_FALLBACK_SECONDS = 25, STAGE_FALLBACK_SECONDS = Config.STAGE_FALLBACK_SECONDS })
check(not valid and #problems == 2, "a prompt must cover keyboard, gamepad and touch")
check(#Config.testersFor("production") == 0 and #Config.testersFor("nowhere") == 0, "no production testers by default")

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
local looking = table.clone(Config)
looking.BASICS = { { id = "look", detect = "camera", turn = 90, title = "LOOK", text = "Look around." } }
check(looking.validate(looking), "a camera step with turn is valid")
local lc = newController(looking)
server.stepId = "look"
local yaw = 0
local savedLook = look
for _ = 1, 4 do
	look = V(math.sin(math.rad(yaw)), -0.3, -math.cos(math.rad(yaw)))
	lc:update(0.1)
	yaw += 35
end
look = savedLook
check(sent[#sent].step == "look" and lastProgress == 1, "turning the camera 90 degrees reports the look step")
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

print("PASS tutorial templates: " .. checks .. " checks")
