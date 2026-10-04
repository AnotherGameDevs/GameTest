-- Pure data migrations (no Roblox APIs) so they can be unit-tested outside Studio: see tests/migration_test.luau.
-- Each step [n] upgrades data from schema version n to n+1. `defs` is Shared/Defs (or a test double).
local DataMigrations = {}

-- v1 -> v2: the old two-tool progression is replaced by the seven-tool ladder + Dynamite.
--   * "rusty_shovel" keeps its id and meaning (tier 1).
--   * "digging_shovel" used to be the strong early upgrade (Power 18, 3 swings/s, 3x3x3 splash, $180). The id now
--     means the modest tier-2 tool. To honour what legacy owners paid for, they KEEP it and are also granted the
--     tiers listed here (no refund, no further skipping); their equipped tool becomes the best tier they own.
DataMigrations.LEGACY_TOOL_GRANTS = {
	digging_shovel = { "heavy_shovel" },
}

local function highestOwnedTool(owned, defs): string
	local best, bestTier = nil, -1
	for id in pairs(owned) do
		local def = defs.Tools[id]
		if def and def.Tier > bestTier then
			best, bestTier = id, def.Tier
		end
	end
	return best or "rusty_shovel"
end

local function toolsV2(data, defs)
	data.OwnedTools = data.OwnedTools or {}
	local granted = {}
	for legacyId, grants in pairs(DataMigrations.LEGACY_TOOL_GRANTS) do
		if data.OwnedTools[legacyId] then
			for _, id in ipairs(grants) do
				if defs.Tools[id] and not data.OwnedTools[id] then
					data.OwnedTools[id] = true
					table.insert(granted, id)
				end
			end
			table.insert(granted, "(legacy " .. legacyId .. ")")
		end
	end
	data.OwnedTools.rusty_shovel = true
	data.Equipment = data.Equipment or {}
	if #granted > 0 or not defs.Tools[data.Equipment.ToolId or ""] or not data.OwnedTools[data.Equipment.ToolId or ""] then
		data.Equipment.ToolId = highestOwnedTool(data.OwnedTools, defs)
	end
	data.MigrationLog = data.MigrationLog or {}
	if #granted > 0 then
		data.MigrationLog.ToolsV2 = table.concat(granted, ",")
	end
end

DataMigrations.Steps = {
	[1] = toolsV2,
}

-- Runs every pending step in order, then stamps the new version.
function DataMigrations.Migrate(data, currentVersion: number, defs)
	local v = data.Version or 0
	while v < currentVersion do
		local step = DataMigrations.Steps[v]
		if step then
			step(data, defs)
		end
		v += 1
		data.Version = v
	end
	return data
end

-- Always-on repair: drops unknown tool/backpack ids and makes sure the equipped items are valid and owned.
function DataMigrations.Sanitize(data, defs, starterTool: string, starterBackpack: string)
	data.OwnedTools = data.OwnedTools or {}
	for id in pairs(data.OwnedTools) do
		if not defs.Tools[id] then
			data.OwnedTools[id] = nil
		end
	end
	data.OwnedTools[starterTool] = true
	data.OwnedBackpacks = data.OwnedBackpacks or {}
	for id in pairs(data.OwnedBackpacks) do
		if not defs.Backpacks[id] then
			data.OwnedBackpacks[id] = nil
		end
	end
	data.OwnedBackpacks[starterBackpack] = true
	data.Equipment = data.Equipment or {}
	if not defs.Tools[data.Equipment.ToolId or ""] or not data.OwnedTools[data.Equipment.ToolId] then
		data.Equipment.ToolId = highestOwnedTool(data.OwnedTools, defs)
	end
	if not defs.Backpacks[data.Equipment.BackpackId or ""] or not data.OwnedBackpacks[data.Equipment.BackpackId] then
		data.Equipment.BackpackId = starterBackpack
	end
end

return DataMigrations
