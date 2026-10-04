-- Pure buried-loot generation for ONE mine generation (docs/LOOT.md). The caller supplies a random source (a Roblox
-- `Random` seeded from a fresh server-only seed) and the loot-placement seed; nothing here touches the world and nothing
-- here is ever sent to a client. Tested in tests/loot_reset_test.luau.
--   * Each cell rolls its layer's TreasureChance, then a weighted layer table (Defs.PickTreasure).
--   * Important (carry-home) artifacts: only eligible cells; at most Config.Loot.ImportantLimits[id] per generation, chosen
--     UNIFORMLY among all rolled candidates (so the depth/position of the survivors is not biased toward the first cells in
--     index order); the rest become ordinary finds from the same layer.
--   * Discovery pockets are placed at random from the loot seed and own the loot of their cells.
local Config = require(script.Parent.Config)
local Defs = require(script.Parent.Defs)
local Grid = require(script.Parent.Grid)
local MineStyle = require(script.Parent.MineStyle)

local LootPlan = {}

-- May an important artifact be buried in this cell? Not on the outer ring of the grid, not on the bottom row (bedrock
-- below) and not near the exit shaft / elevator side.
function LootPlan.Eligible(x: number, y: number, z: number): boolean
	local S = Config.Site
	if x < 1 or x > S.SizeX - 2 or z < 1 or z > S.SizeZ - 2 or y < 1 or y > S.Depth - 2 then
		return false
	end
	local ex = Config.Exit
	if ex.Enabled then
		local clear = Config.Loot.ExitClearCells
		local cellMin = Grid.OriginX + x * Grid.CellSize
		local cellMax = cellMin + Grid.CellSize
		local shaftMin, shaftMax = ex.CenterX - ex.Width / 2, ex.CenterX + ex.Width / 2
		local margin = clear * Grid.CellSize
		local nearShaftColumn = cellMax > shaftMin - margin and cellMin < shaftMax + margin
		if nearShaftColumn and z >= S.SizeZ - 1 - clear then
			return false
		end
	end
	return true
end

local function limitFor(id: string): number
	return Config.Loot.ImportantLimits[id] or Config.Loot.DefaultImportantLimit
end

-- Returns { Loot = { [cellIndex] = treasureId }, Pockets = {...}, Counts = { [treasureId] = n } }.
function LootPlan.Generate(rng, lootSeed: number)
	local loot: { [number]: any } = {}
	local candidates: { [string]: { number } } = {}

	for idx = 1, Grid.Count do
		local x, y, z = Grid.FromIndex(idx)
		local layer = Defs.LayerAtCell(y)
		if rng:NextNumber() < layer.TreasureChance then
			local id = Defs.PickTreasure(layer.Id, rng)
			if id then
				local def = Defs.Treasure[id]
				if def.RequiresCarry then
					if LootPlan.Eligible(x, y, z) then
						candidates[id] = candidates[id] or {}
						table.insert(candidates[id], idx)
					else
						id = Defs.PickTreasure(layer.Id, rng, true)
					end
				end
				loot[idx] = id
			end
		end
	end

	-- Enforce per-generation limits: keep a uniformly random subset of each important artifact's candidates.
	local ids = {}
	for id in pairs(candidates) do
		table.insert(ids, id)
	end
	table.sort(ids) -- deterministic order for a given rng stream
	for _, id in ipairs(ids) do
		local list = candidates[id]
		for i = #list, 2, -1 do -- Fisher-Yates
			local j = 1 + math.floor(rng:NextNumber() * i)
			list[i], list[j] = list[j], list[i]
		end
		for i = limitFor(id) + 1, #list do
			local idx = list[i]
			local _, y = Grid.FromIndex(idx)
			loot[idx] = Defs.PickTreasure(Defs.LayerAtCell(y).Id, rng, true)
		end
	end

	-- Discovery pockets: random positions from the loot seed; their cells own their loot (ordinary rewards only).
	local pockets = MineStyle.Pockets(lootSeed)
	for _, pocket in ipairs(pockets) do
		for _, c in ipairs(pocket.Cells) do
			loot[Grid.ToIndex(c[1], c[2], c[3])] = c[4]
		end
	end

	local counts = {}
	for _, id in pairs(loot) do
		counts[id] = (counts[id] or 0) + 1
	end
	return { Loot = loot, Pockets = pockets, Counts = counts }
end

return LootPlan
