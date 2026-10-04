-- Player settings persistence. The client sends its whole settings table; the server never trusts it: every value is
-- clamped/validated by SettingsSpec and only known keys are stored, in the existing profile (data.Settings), which the
-- DataService already saves. Settings survive death/respawn (they never live on the character) and rejoining.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local SettingsSpec = require(ReplicatedStorage.Shared.SettingsSpec)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)

local SettingsService = {}

function SettingsService.Init()
	Remotes.Get("UpdateSettings").OnServerEvent:Connect(function(player: Player, payload: any)
		if type(payload) ~= "table" or not RateLimiter.Check(player, "UpdateSettings") then
			return
		end
		local data = DataService.Get(player)
		if not data then
			return
		end
		data.Settings = SettingsSpec.Sanitize(payload)
		DataService.MarkDirty(player)
	end)
	Players.PlayerRemoving:Connect(RateLimiter.Forget)
end

return SettingsService
