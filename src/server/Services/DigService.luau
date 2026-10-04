-- Validates and resolves dig hits. The client only says "I hit cell (x,y,z)"; the server decides
-- everything else: which tool, damage, cooldown, reach, target validity, loot and rewards.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataService = require(script.Parent.DataService)
local SiteService = require(script.Parent.SiteService)
local LootService = require(script.Parent.LootService)
local StateService = require(script.Parent.StateService)
local RateLimiter = require(script.Parent.RateLimiter)
local MetricsService = require(script.Parent.MetricsService)
local CarryRegistry = require(script.Parent.CarryRegistry)

local DigService = {}

local lastHit: { [Player]: number } = {}
local digResult = Remotes.Get("DigResult")

local function isInt(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n == n and math.abs(n) < 1e6
end

local function handleHit(player: Player, x: any, y: any, z: any)
	if not (isInt(x) and isInt(y) and isInt(z)) then
		return
	end
	if not RateLimiter.Check(player, "DigHit") then
		return
	end
	if not Grid.InBounds(x, y, z) then
		return
	end
	if CarryRegistry.IsCarrying(player) then
		return -- no mining while carrying an important artifact
	end
	local data = DataService.Get(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not data or not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end

	local tool = Defs.Tools[data.Equipment.ToolId]
	local now = os.clock()
	if now - (lastHit[player] or 0) < (1 / tool.Rate) * Config.Dig.CooldownTolerance then
		return
	end

	local idx = Grid.ToIndex(x, y, z)
	if not SiteService.IsExposed(idx) then
		return
	end
	local center = Grid.CellCenter(x, y, z)
	if not Defs.CellInReach(tool, hrp.Position, x, y, z, Config.Dig.ReachTolerance) then
		return
	end
	lastHit[player] = now

	-- Resolve target + splash
	local targets = { { idx, tool.Power } }
	if tool.Splash then
		for _, ni in ipairs(SiteService.PickSplash(idx, tool.Splash.Radius, tool.Splash.MaxExtra, hrp.Position)) do
			table.insert(targets, { ni, tool.Power * tool.Splash.Fraction })
		end
	end

	local hits = {}
	local destroyed = {}
	for _, t in ipairs(targets) do
		local frac, dead, treasureId = SiteService.Damage(t[1], t[2])
		table.insert(hits, { t[1], frac, dead and 1 or 0 })
		if dead then
			table.insert(destroyed, t[1])
			data.Stats.BlocksDug += 1
			local _, cy = Grid.FromIndex(t[1])
			local depthM = (cy + 1) * Grid.CellSize / Config.Site.StudsPerMeter
			if depthM > data.Stats.DeepestDepth then
				data.Stats.DeepestDepth = math.floor(depthM)
			end
			if treasureId then
				LootService.Award(player, treasureId, t[1])
			end
		end
	end
	for _, di in ipairs(destroyed) do
		SiteService.ExposeAround(di)
	end
	MetricsService.Hit(player, #destroyed)
	DataService.MarkDirty(player)

	-- Feedback to everyone nearby (cosmetic only)
	local payload = { Digger = player.UserId, Hits = hits }
	for _, other in ipairs(Players:GetPlayers()) do
		local oh = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if other == player or (oh and (oh.Position - center).Magnitude <= Config.Dig.MaxBroadcastDistance) then
			digResult:FireClient(other, payload)
		end
	end
	if #destroyed > 0 then
		StateService.Push(player)
	end
end

function DigService.Init()
	Remotes.Get("DigHit").OnServerEvent:Connect(handleHit)
	Players.PlayerRemoving:Connect(function(player)
		lastHit[player] = nil
		RateLimiter.Forget(player)
		LootService.Forget(player)
	end)
end

return DigService
