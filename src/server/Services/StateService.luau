-- Pushes a compact snapshot of the player's state to their client (debounced to once per frame).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local CarryRegistry = require(script.Parent.CarryRegistry)
local Workspace = game:GetService("Workspace")
local Defs = require(ReplicatedStorage.Shared.Defs)
local SettingsSpec = require(ReplicatedStorage.Shared.SettingsSpec)

local StateService = {}
local pending: { [Player]: boolean } = {}
local stateRemote = Remotes.Get("PlayerState")

function StateService.Snapshot(player: Player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	local carried = CarryRegistry.Get(player)
	return {
		Carrying = carried and { Id = carried.Id, Name = Defs.Treasure[carried.TreasureId].Name, Value = carried.Value }
			or (CarryRegistry.CarriesRelic(player) and { Id = "relic", Name = Workspace:GetAttribute("RelicName") or "Relic", Value = 0, Relic = true }) or nil,
		Cash = data.Cash,
		Reputation = data.Reputation,
		Consumables = data.Consumables,
		Settings = SettingsSpec.Sanitize(data.Settings),
		Skins = data.EquippedCosmetics,
		Count = InventoryService.Count(data),
		Capacity = InventoryService.Capacity(data),
		BackpackValue = InventoryService.Value(data),
		ToolId = data.Equipment.ToolId,
		BackpackId = data.Equipment.BackpackId,
		OwnedTools = data.OwnedTools,
		OwnedBackpacks = data.OwnedBackpacks,
		Stats = data.Stats,
		Collection = data.Collection,
		Display = data.Display,
		Guide = data.Guide,
		GuideBase = data.GuideBase,
	}
end

function StateService.Push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(function()
		pending[player] = nil
		if player.Parent then
			local snap = StateService.Snapshot(player)
			if snap then
				stateRemote:FireClient(player, snap)
			end
		end
	end)
end

return StateService
