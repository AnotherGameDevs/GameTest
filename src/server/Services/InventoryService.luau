-- Backpack: simple counted capacity. Contents live in profile.BackpackItems = { [treasureId] = count }.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Defs = require(ReplicatedStorage.Shared.Defs)
local DataService = require(script.Parent.DataService)

local InventoryService = {}

function InventoryService.Capacity(data): number
	return Defs.Backpacks[data.Equipment.BackpackId].Capacity
end

function InventoryService.Count(data): number
	local n = 0
	for _, c in pairs(data.BackpackItems) do
		n += c
	end
	return n
end

function InventoryService.Value(data): number
	local v = 0
	for id, c in pairs(data.BackpackItems) do
		local def = Defs.Treasure[id]
		if def then
			v += def.Value * c
		end
	end
	return v
end

function InventoryService.IsFull(data): boolean
	return InventoryService.Count(data) >= InventoryService.Capacity(data)
end

-- Returns true if stored, false if the backpack was full.
function InventoryService.Add(player: Player, treasureId: string): boolean
	local data = DataService.Get(player)
	if not data or not Defs.Treasure[treasureId] then
		return false
	end
	if InventoryService.IsFull(data) then
		return false
	end
	data.BackpackItems[treasureId] = (data.BackpackItems[treasureId] or 0) + 1
	DataService.MarkDirty(player)
	return true
end

-- Empties the backpack and returns what was in it (and its sell value, priced by the server).
function InventoryService.TakeAll(player: Player): (number, number)
	local data = DataService.Get(player)
	if not data then
		return 0, 0
	end
	local count, value = InventoryService.Count(data), InventoryService.Value(data)
	data.BackpackItems = {}
	DataService.MarkDirty(player)
	return count, value
end

return InventoryService
