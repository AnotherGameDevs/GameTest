-- Pushes a compact snapshot of the player's state to their client (debounced to once per frame).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local StateService = {}
local pending: { [Player]: boolean } = {}
local stateRemote = Remotes.Get("PlayerState")

function StateService.Snapshot(player: Player)
	local data = DataService.Get(player)
	if not data then
		return nil
	end
	return {
		Cash = data.Cash,
		Reputation = data.Reputation,
		Count = InventoryService.Count(data),
		Capacity = InventoryService.Capacity(data),
		BackpackValue = InventoryService.Value(data),
		ToolId = data.Equipment.ToolId,
		BackpackId = data.Equipment.BackpackId,
		OwnedTools = data.OwnedTools,
		OwnedBackpacks = data.OwnedBackpacks,
		Stats = data.Stats,
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
