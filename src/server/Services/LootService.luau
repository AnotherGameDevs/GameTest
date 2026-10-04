-- Turns a destroyed cell's pre-rolled treasure into a reward for the digger. The server alone
-- decides what drops (the table was rolled with a server-side seed at site generation).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local AnalyticsService = require(script.Parent.AnalyticsService)
local ArtifactService = require(script.Parent.ArtifactService)

local LootService = {}
local treasureRemote = Remotes.Get("TreasureFound")
local notifyRemote = Remotes.Get("Notify")
local lastFullWarn: { [Player]: number } = {}

-- Returns true if the treasure ended up in the backpack.
function LootService.Award(player: Player, treasureId: string, cellIndex: number): boolean
	local data = DataService.Get(player)
	local def = Defs.Treasure[treasureId]
	if not data or not def then
		return false
	end
	local x, y, z = Grid.FromIndex(cellIndex)

	-- Important artifacts are never auto-collected: they appear physically and must be carried to camp.
	-- No backpack slot, no cash and no collection credit until a successful deposit.
	if def.RequiresCarry then
		ArtifactService.Discover(player, treasureId, cellIndex)
		treasureRemote:FireClient(player, {
			Id = treasureId,
			Position = Grid.CellCenter(x, y, z),
			Stored = false,
			Carry = true,
			IsNew = data.Collection[treasureId] == nil,
		})
		AnalyticsService.Log(player, "ImportantArtifactFound", { id = treasureId })
		return true
	end

	local stored = InventoryService.Add(player, treasureId)

	local entry = data.Collection[treasureId]
	local isNew = false
	if stored then
		if not entry then
			entry = { Count = 0, FirstFound = os.time() }
			data.Collection[treasureId] = entry
			isNew = true
		end
		entry.Count += 1
		data.Stats.TreasureFound += 1
	end

	treasureRemote:FireClient(player, {
		Id = treasureId,
		Position = Grid.CellCenter(x, y, z),
		Stored = stored,
		IsNew = isNew,
	})

	if not stored then
		local now = os.clock()
		if now - (lastFullWarn[player] or 0) > 2 then
			lastFullWarn[player] = now
			notifyRemote:FireClient(player, "BACKPACK FULL! Treasure lost - return to Base Camp to sell!", "Danger")
		end
	end
	AnalyticsService.Log(player, "TreasureFound", { id = treasureId, stored = stored })
	return stored
end

function LootService.Forget(player: Player)
	lastFullWarn[player] = nil
end

return LootService
