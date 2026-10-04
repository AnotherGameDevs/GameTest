-- DIG & RUN! server entry point. Order matters: remotes -> world -> services.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local BuildInfo = require(ReplicatedStorage.Shared.BuildInfo)
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
local SettingsService = require(Services.SettingsService)
local ElevatorService = require(Services.ElevatorService)
local CollectionService = require(Services.CollectionService)
local MineShiftService = require(Services.MineShiftService)
local RelicService = require(Services.RelicService)
local DevService = require(Services.DevService)

WorldBuilder.Build()
SiteService.Generate() -- fresh server-only loot seed (never the constant Config.Site.Seed)

for name, init in pairs({
	Data = DataService.Init,
	Equipment = EquipmentService.Init,
	Dig = DigService.Init,
	Economy = EconomyService.Init,
	Metrics = MetricsService.Init,
	Artifacts = ArtifactService.Init,
	Dynamite = DynamiteService.Init,
	Settings = SettingsService.Init,
	Elevator = ElevatorService.Init,
	Collection = CollectionService.Init,
	MineShift = MineShiftService.Init,
	Relic = RelicService.Init,
	Dev = DevService.Init,
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

print(("[%s] Server ready. Build %s (source %s, built %s)"):format(Config.GameName, BuildInfo.Id, BuildInfo.Source, BuildInfo.Time))
