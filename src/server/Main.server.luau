-- DIG & RUN! server entry point. Order matters: remotes -> world -> services.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Services = script.Parent:WaitForChild("Services")
local WorldBuilder = require(Services.WorldBuilder)
local SiteService = require(Services.SiteService)
local DataService = require(Services.DataService)
local StateService = require(Services.StateService)
local EquipmentService = require(Services.EquipmentService)
local DigService = require(Services.DigService)
local EconomyService = require(Services.EconomyService)
local RateLimiter = require(Services.RateLimiter)
local MetricsService = require(Services.MetricsService)
local ArtifactService = require(Services.ArtifactService)
local DynamiteService = require(Services.DynamiteService)

WorldBuilder.Build()
SiteService.Generate(Config.Site.Seed)

for name, init in pairs({
	Data = DataService.Init,
	Equipment = EquipmentService.Init,
	Dig = DigService.Init,
	Economy = EconomyService.Init,
	Metrics = MetricsService.Init,
	Artifacts = ArtifactService.Init,
	Dynamite = DynamiteService.Init,
}) do
	local ok, err = pcall(init)
	if not ok then
		warn(("[Main] %sService failed to start: %s"):format(name, tostring(err)))
	end
end

DataService.OnLoaded(function(player)
	StateService.Push(player)
end)

Remotes.Get("ClientReady").OnServerEvent:Connect(function(player)
	if RateLimiter.Check(player, "ClientReady") then
		StateService.Push(player)
	end
end)

print(("[%s] Server ready."):format(Config.GameName))
