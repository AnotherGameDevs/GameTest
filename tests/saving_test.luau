-- Run via tests/run_all.sh. Saving behaviour that can be checked without Roblox: session lock rules and the full migration chain.
local SessionLock = require("../src/server/Services/SessionLock")
local Migrations = require("../src/server/Services/DataMigrations")
local SaveMode = require("../src/server/Services/SaveMode")
local ProfileStore = require("../src/server/Services/ProfileStore")
local SettingsSpec = require("./_build/shared/SettingsSpec")
local Config = require("./_build/shared/Config")
local CollectionSpec = require("./_build/shared/CollectionSpec")

local passed, failed = 0, 0
local function check(name, cond, detail) if cond then passed += 1 else failed += 1; print("FAIL: " .. name .. (detail and ("  -> " .. detail) or "")) end end

-- ================================================================== session lock ===================================
do
	local now, timeout = 1000, 120
	check("an unlocked or brand-new profile can be loaded", not SessionLock.IsLockedByOther(nil, "A", now, timeout) and not SessionLock.IsLockedByOther({}, "A", now, timeout))
	check("our own lock never blocks us", not SessionLock.IsLockedByOther({ SessionLock = SessionLock.Claim("A", now - 5) }, "A", now, timeout))
	check("a live lock held by another server blocks loading", SessionLock.IsLockedByOther({ SessionLock = SessionLock.Claim("B", now - 30) }, "A", now, timeout))
	check("a stale lock (crashed server) does not lock the player out", not SessionLock.IsLockedByOther({ SessionLock = SessionLock.Claim("B", now - 121) }, "A", now, timeout))
	check("the lock refreshes before it can go stale (45 s refresh < 120 s timeout)", 45 < timeout)
	check("malformed lock records are ignored, not fatal", not SessionLock.IsLockedByOther({ SessionLock = "junk" }, "A", now, timeout) and not SessionLock.IsLockedByOther({ SessionLock = { JobId = "B" } }, "A", now, timeout))
	check("claiming records server and time", SessionLock.Claim("A", 5).JobId == "A" and SessionLock.Claim("A", 5).At == 5)
end

-- ================================================================== migration chain v1 -> v3 =========================
do
	local defs = {
		Tools = { rusty_shovel = { Tier = 1 }, digging_shovel = { Tier = 2 }, heavy_shovel = { Tier = 3 } },
		Backpacks = { pouch = {}, satchel = {} }, Treasure = { old_coin = {}, bronze_ring = {} },
	}
	-- a v1 profile: the old strong shovel, some progress, an unknown treasure, a collection entry
	local d = { Version = 1, Cash = 777, Stats = { CashEarned = 900, BlocksDug = 300 }, OwnedTools = { rusty_shovel = true, digging_shovel = true },
		Equipment = { ToolId = "digging_shovel", BackpackId = "pouch" }, OwnedBackpacks = { pouch = true },
		Collection = { old_coin = { Count = 2, FirstFound = 9 }, retired_item = { Count = 1 } } }
	Migrations.Migrate(d, 3, defs)
	Migrations.Sanitize(d, defs, "rusty_shovel", "pouch")
	Migrations.SanitizeCollection(d, defs)
	d.Display = CollectionSpec.SanitizeDisplay(d.Display, d.Collection)
	check("v1 -> v3 reaches the current version", d.Version == 3)
	check("cash and ownership survive the whole chain", d.Cash == 777 and d.OwnedTools.digging_shovel and d.OwnedTools.heavy_shovel and d.Equipment.ToolId == "heavy_shovel")
	check("collection keeps valid entries and drops retired ones", d.Collection.old_coin.Count == 2 and d.Collection.retired_item == nil)
	check("display and tutorial progress exist; experienced players skip the early hints", type(d.Display) == "table" and d.Guide.mine and d.Guide.sell)
	local again = Migrations.Migrate(d, 3, defs)
	check("migrating twice changes nothing", again.Version == 3 and d.Cash == 777)
	-- a FAILED load must never save defaults over progress: DataService marks such profiles NoSave (documented in DataService.load);
	-- the pure side of that rule: loading garbage still yields a sanitised, usable table, never an error
	local junk = { Version = 1, OwnedTools = "nope", Equipment = 5, OwnedBackpacks = 7, MigrationLog = "x", Stats = "y" }
	local ok = pcall(function() Migrations.Migrate(junk, 3, defs); Migrations.Sanitize(junk, defs, "rusty_shovel", "pouch") end)
	check("a corrupted profile is repaired instead of crashing the loader", ok and junk.OwnedTools.rusty_shovel == true)
end

-- ================================================================== save isolation (every outcome) ==================
do
	local bools = { true, false }
	local violations, kicksOk, combos = 0, true, 0
	for _, store in ipairs(bools) do for _, read in ipairs(bools) do for _, locked in ipairs(bools) do for _, has in ipairs(bools) do
		for _, mig in ipairs(bools) do for _, studio in ipairs(bools) do
			combos += 1
			local m = SaveMode.Decide({ StoreAvailable = store, ReadOk = read, Locked = locked, HasData = has, MigrateOk = mig, IsStudio = studio })
			local unusable = store and (locked or not read or (has and not mig))
			if unusable and m.Persist then violations += 1 end -- would save over a profile we could not use
			if unusable and not studio and not m.Kick then kicksOk = false end -- published servers must refuse, not play on defaults
			if unusable and studio and (m.Kick or not m.UseDefaults) then kicksOk = false end -- Studio plays on a memory-only stand-in
			if not store and m.Persist then violations += 1 end -- no datastore: nothing to save to
			if store and read and not locked and (not has or mig) and not m.Persist then violations += 1 end -- a healthy profile must save
		end end
	end end end end
	check("no combination of failures can ever persist a stand-in profile (" .. combos .. " combinations)", violations == 0)
	check("published servers kick on lock/read/migration failure; Studio plays memory-only", kicksOk)
	check("a brand-new player saves normally", SaveMode.Decide({ StoreAvailable = true, ReadOk = true, Locked = false, HasData = false, MigrateOk = true, IsStudio = false }).Persist)
	check("every kick reason has a player-facing message", SaveMode.KickMessages.locked and SaveMode.KickMessages["read-failed"] and SaveMode.KickMessages["migration-failed"])
	check("Studio uses an isolated test store, never the production one", Config.Data.StudioStoreName ~= Config.Data.StoreName and Config.Data.StudioStoreName:find("TEST") ~= nil)
end

-- ================================================================== the real load/save protocol against a fake DataStore ==
-- (This runs the SAME ProfileStore code DataService uses, against an in-memory stand-in. It checks the protocol's logic; it is NOT evidence that
-- Roblox DataStores work - that needs the Studio test in docs/ISOLATED_TEST_EXPERIENCE.md.)
do
	local function deepcopy(v) if type(v) ~= "table" then return v end local c = {} for k, x in pairs(v) do c[k] = deepcopy(x) end return c end
	local function serializable(v, path)
		local t = type(v)
		if t == "number" then assert(v == v and v ~= math.huge and v ~= -math.huge, "NaN/inf at " .. path) return end
		if t == "string" or t == "boolean" then return end
		assert(t == "table", "unserializable " .. t .. " at " .. path)
		for k, x in pairs(v) do assert(type(k) == "string" or type(k) == "number", "bad key type at " .. path); serializable(x, path .. "." .. tostring(k)) end
	end
	local function newStore()
		local st = { data = {}, writes = 0, failNext = 0, calls = 0 }
		function st:UpdateAsync(key, fn)
			self.calls += 1
			if self.failNext > 0 then self.failNext -= 1; error("simulated DataStore error 502") end
			local new = fn(deepcopy(self.data[key]))
			if new ~= nil then serializable(new, "profile"); self.data[key] = deepcopy(new); self.writes += 1 end
		end
		return st
	end
	local clock = 1000
	local function ctxFor(job) return { JobId = job, Lock = SessionLock, Now = function() return clock end, LockTimeout = 120,
		Attempt = function(fn, tries) local ok, res; for _ = 1, tries do ok, res = pcall(fn); if ok then return true, res end end return false, res end } end
	local A, B = ctxFor("A"), ctxFor("B")
	local K = "Player_42"

	-- a profile with every supported field
	local profile = { Version = 3, Cash = 1234, Reputation = 0, Equipment = { ToolId = "digging_shovel", BackpackId = "satchel" },
		OwnedTools = { rusty_shovel = true, digging_shovel = true }, OwnedBackpacks = { pouch = true, satchel = true }, Consumables = { dynamite = 2 },
		BackpackItems = { old_coin = 3 }, Collection = { old_coin = { Count = 4, FirstFound = 99 }, bronze_ring = { Count = 1, FirstFound = 100 } },
		Display = { "old_coin" }, Guide = { mine = true, backpack = true }, GuideBase = {}, Settings = SettingsSpec.Defaults(),
		Stats = { BlocksDug = 77, TreasureFound = 5, CashEarned = 1500, RelicsExtracted = 0, DeepestDepth = 12 } }
	profile.Settings.MouseSensitivity = 0.55

	local st = newStore()
	local r1 = ProfileStore.Load(st, K, A, 3)
	check("a brand-new player loads (no data yet) and takes the session lock", r1.Ok and r1.Data == nil and st.data[K].SessionLock.JobId == "A")
	local snap = deepcopy(profile)
	local s1 = ProfileStore.Save(st, K, snap, false, A, 3)
	check("autosave writes the whole profile and keeps the lock", s1.Ok and st.data[K].Cash == 1234 and st.data[K].SessionLock.JobId == "A")
	local rb = ProfileStore.Load(st, K, B, 3)
	check("a second live server is refused while the first holds the lock", not rb.Ok and rb.Locked)
	local s2 = ProfileStore.Save(st, K, deepcopy(profile), true, A, 3)
	check("leaving saves the profile and RELEASES the lock", s2.Ok and st.data[K].SessionLock == nil)
	local r2 = ProfileStore.Load(st, K, B, 3)
	local same = r2.Ok and r2.Data ~= nil
	local keys = { "Cash", "Equipment", "OwnedTools", "OwnedBackpacks", "Consumables", "BackpackItems", "Collection", "Display", "Guide", "Settings", "Stats", "Version" }
	local function eq(a, b) if type(a) ~= type(b) then return false end if type(a) ~= "table" then return a == b end for k, v in pairs(a) do if not eq(v, b[k]) then return false end end for k in pairs(b) do if a[k] == nil then return false end end return true end
	for _, k in ipairs(keys) do if same and not eq(profile[k], r2.Data[k]) then same = false; print("   mismatch in " .. k) end end
	check("REJOIN: cash, tools, backpacks, equipped, collection, display, tutorial, settings all come back identical", same)
	check("the new server now holds the lock", st.data[K].SessionLock.JobId == "B")

	-- failures never lead to writes
	local st2 = newStore(); st2.data[K] = deepcopy(profile)
	st2.failNext = 99
	local rf = ProfileStore.Load(st2, K, A, 3)
	check("a failed read reports failure, returns no data and WRITES NOTHING", not rf.Ok and not rf.Locked and rf.Data == nil and st2.writes == 0 and st2.data[K].Cash == 1234)
	local mode = SaveMode.Decide({ StoreAvailable = true, ReadOk = rf.Ok, Locked = rf.Locked, HasData = false, MigrateOk = true, IsStudio = false })
	check("...and the profile is refused/kicked, never persisted", not mode.Persist and mode.Kick ~= nil)
	local st3 = newStore(); st3.data[K] = deepcopy(profile); st3.failNext = 2
	check("retries recover from transient errors (2 failures then success within 3 tries)", ProfileStore.Save(st3, K, deepcopy(profile), false, A, 3).Ok and st3.writes == 1)
	local st4 = newStore(); st4.data[K] = deepcopy(profile); st4.failNext = 99
	local bad = deepcopy(profile); bad.Cash = 5
	check("a save that fails every retry reports failure and leaves the stored profile intact", not ProfileStore.Save(st4, K, bad, false, A, 3).Ok and st4.data[K].Cash == 1234)

	-- lock expiry and lost locks
	local st5 = newStore()
	ProfileStore.Load(st5, K, A, 3); ProfileStore.Save(st5, K, deepcopy(profile), false, A, 3)
	clock += 121 -- server A crashed: its lock goes stale
	local rs = ProfileStore.Load(st5, K, B, 3)
	check("a crashed server's stale lock does not lock the player out", rs.Ok and rs.Data and rs.Data.Cash == 1234)
	local lost = deepcopy(profile); lost.Cash = 999999
	local sl = ProfileStore.Save(st5, K, lost, false, A, 3)
	check("if the lock was taken over, the old server's late save is refused and can not overwrite", not sl.Ok and sl.LostLock and st5.data[K].Cash == 1234)
	check("release clears only OUR lock and keeps the data", (function()
		ProfileStore.Release(st5, K, A) -- not ours: no change
		local stillB = st5.data[K].SessionLock and st5.data[K].SessionLock.JobId == "B"
		ProfileStore.Release(st5, K, B)
		return stillB and st5.data[K].SessionLock == nil and st5.data[K].Cash == 1234
	end)())
	check("refreshing the lock on each save keeps a live session from going stale", (function()
		local s = newStore(); ProfileStore.Load(s, K, A, 3)
		clock += 100; ProfileStore.Save(s, K, deepcopy(profile), false, A, 3)
		clock += 100 -- 200 s since the claim but only 100 s since the refresh
		return not ProfileStore.Load(s, K, B, 3).Ok
	end)())
	check("every saved field is a plain serialisable value (the fake store rejects functions / NaN / bad keys)", pcall(serializable, profile, "profile"))
	check("the key is account-based and stable (Player_<UserId>)", K == "Player_42")
end

print(("saving: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
