-- Client-side mirror of the server's PlayerState snapshot. Read-only for the client.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Config = require(ReplicatedStorage.Shared.Config)

local State = {
	Data = {
		Cash = 0, Reputation = 0, Count = 0, Capacity = 1, BackpackValue = 0,
		ToolId = Config.Starting.ToolId, BackpackId = Config.Starting.BackpackId,
		OwnedTools = {}, OwnedBackpacks = {}, Carrying = nil, Consumables = {} :: any, Skins = {} :: any, Settings = {} :: any,
	},
	Loaded = false,
}

local listeners: { (any) -> () } = {}

function State.Connect(cb: (any) -> ())
	table.insert(listeners, cb)
	if State.Loaded then
		cb(State.Data)
	end
end

function State.Tool()
	return Defs.Tools[State.Data.ToolId] or Defs.Tools[Config.Starting.ToolId]
end

function State.Init()
	Remotes.Get("PlayerState").OnClientEvent:Connect(function(snap)
		State.Data = snap
		State.Loaded = true
		for _, cb in ipairs(listeners) do
			task.spawn(cb, snap)
		end
	end)
end

return State
