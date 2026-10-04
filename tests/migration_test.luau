-- Run: luau tests/migration_test.luau  (pure logic)
local Migrations = require("../src/server/Services/DataMigrations")
local passed, failed = 0, 0
local function check(name, cond) if cond then passed += 1 else failed += 1; print("FAIL: " .. name) end end

local defs = {
	Tools = {
		rusty_shovel = { Tier = 1 }, digging_shovel = { Tier = 2 }, heavy_shovel = { Tier = 3 },
		power_shovel = { Tier = 4 },
	},
	Backpacks = { pouch = {}, satchel = {} },
}

-- A v1 save that bought the old powerful Digging Shovel
do
	local d = { Version = 1, Cash = 500, OwnedTools = { rusty_shovel = true, digging_shovel = true },
		Equipment = { ToolId = "digging_shovel", BackpackId = "pouch" }, OwnedBackpacks = { pouch = true } }
	Migrations.Migrate(d, 2, defs)
	Migrations.Sanitize(d, defs, "rusty_shovel", "pouch")
	check("version stamped", d.Version == 2)
	check("keeps digging_shovel ownership", d.OwnedTools.digging_shovel == true)
	check("granted heavy_shovel", d.OwnedTools.heavy_shovel == true)
	check("tier 4 NOT granted", not d.OwnedTools.power_shovel)
	check("equips best owned tier", d.Equipment.ToolId == "heavy_shovel")
	check("cash untouched", d.Cash == 500)
	check("log recorded", d.MigrationLog and d.MigrationLog.ToolsV2 ~= nil)
	-- idempotent: re-running does not change anything
	Migrations.Migrate(d, 2, defs)
	check("rerun keeps version", d.Version == 2)
end

-- A v1 save that only ever owned the rusty shovel
do
	local d = { Version = 1, Cash = 10, OwnedTools = { rusty_shovel = true }, Equipment = { ToolId = "rusty_shovel", BackpackId = "pouch" } }
	Migrations.Migrate(d, 2, defs)
	check("no grants for starter-only", not d.OwnedTools.heavy_shovel and d.Equipment.ToolId == "rusty_shovel")
	check("no log entry", d.MigrationLog.ToolsV2 == nil)
end

-- Corrupt / unknown ids are repaired
do
	local d = { Version = 2, OwnedTools = { ghost_tool = true }, Equipment = { ToolId = "ghost_tool", BackpackId = "nope" },
		OwnedBackpacks = { nope = true } }
	Migrations.Sanitize(d, defs, "rusty_shovel", "pouch")
	check("unknown tool removed", d.OwnedTools.ghost_tool == nil)
	check("starter restored", d.OwnedTools.rusty_shovel == true and d.Equipment.ToolId == "rusty_shovel")
	check("bad backpack replaced", d.Equipment.BackpackId == "pouch" and d.OwnedBackpacks.nope == nil)
end

-- Equipped tool that is not owned gets fixed
do
	local d = { Version = 2, OwnedTools = { rusty_shovel = true }, Equipment = { ToolId = "power_shovel", BackpackId = "pouch" } }
	Migrations.Sanitize(d, defs, "rusty_shovel", "pouch")
	check("cannot equip unowned tool", d.Equipment.ToolId == "rusty_shovel")
end

print(("migration tests: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("tests failed") end
