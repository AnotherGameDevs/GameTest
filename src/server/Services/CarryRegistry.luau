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

-- The contested server relic carrier (at most one in the whole server; RelicService owns it). The relic counts as "carrying" for
-- EVERY gate (mining, throwing, equipping, return-to-camp), exactly like a personal artifact.
local relicCarrier: number? = nil

function CarryRegistry.SetRelicCarrier(userId: number?)
	relicCarrier = userId
end

function CarryRegistry.GetRelicCarrierId(): number?
	return relicCarrier
end

function CarryRegistry.CarriesRelic(player: Player): boolean
	return relicCarrier ~= nil and relicCarrier == player.UserId
end

function CarryRegistry.IsCarrying(player: Player): boolean
	return CarryRegistry.Store:CarriedBy(player.UserId) ~= nil or CarryRegistry.CarriesRelic(player)
end

return CarryRegistry
