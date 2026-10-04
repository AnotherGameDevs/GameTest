-- Run via tests/run_all.sh. Saving behaviour that can be checked without Roblox: session lock rules and the full migration chain.
local SessionLock = require("../src/server/Services/SessionLock")
local Migrations = require("../src/server/Services/DataMigrations")
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

print(("saving: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
