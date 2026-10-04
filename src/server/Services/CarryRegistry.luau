-- The single source of truth for "is this player carrying an important artifact?". Required by every system that
-- must be gated on it (digging, equipment, teleport, state snapshots) without creating require cycles.
local HttpService = game:GetService("HttpService")
local ArtifactRecords = require(script.Parent.ArtifactRecords)

local CarryRegistry = {}

-- Recovery ids are server-generated GUIDs; the client never supplies or sees authority over them.
CarryRegistry.Store = ArtifactRecords.new(function()
	return HttpService:GenerateGUID(false)
end)

function CarryRegistry.Get(player: Player)
	return CarryRegistry.Store:CarriedBy(player.UserId)
end

function CarryRegistry.IsCarrying(player: Player): boolean
	return CarryRegistry.Store:CarriedBy(player.UserId) ~= nil
end

return CarryRegistry
