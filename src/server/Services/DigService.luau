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
local MineState = require(script.Parent.MineState)

local DigService = {}

local lastHit: { [Player]: number } = {}
local lastGateNote: { [Player]: number } = {}
local notifyRemote = Remotes.Get("Notify")
local digResult = Remotes.Get("DigResult")

local function isInt(n: any): boolean
	return type(n) == "number" and n == math.floor(n) and n == n and math.abs(n) < 1e6
end

local function handleHit(player: Player, x: any, y: any, z: any, gen: any)
	if not (isInt(x) and isInt(y) and isInt(z)) then
		return
	end
	if not RateLimiter.Check(player, "DigHit") then
		return
	end
	-- The mine must be accepting requests (not mid-reset) and the request must name the CURRENT generation, so a delayed
	-- or replayed hit from an old mine can never damage the new cells that happen to sit at the same coordinates.
	if not MineState.Accepting() or gen ~= SiteService.Generation() then
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
	-- Layer gating: a tool too weak for this layer does nothing (and does not use up the swing).
	local targetLayer = Defs.LayerAtCell(y)
	if not Defs.LayerAllows(tool, targetLayer) then
		if now - (lastGateNote[player] or 0) > 1.5 then
			lastGateNote[player] = now
			notifyRemote:FireClient(player, ("Too hard! %s blocks need a %s or better."):format(
				targetLayer.Name:sub(1, 1) .. targetLayer.Name:sub(2):lower(), Defs.ToolNameForTier(targetLayer.MinToolTier)), "Danger")
		end
		return
	end
	lastHit[player] = now

	-- Resolve target + splash (splash never damages a layer this tool cannot break)
	local targets = { { idx, tool.Power } }
	if tool.Splash then
		for _, ni in ipairs(SiteService.PickSplash(idx, tool.Splash.Radius, tool.Splash.MaxExtra, hrp.Position)) do
			local _, ny = Grid.FromIndex(ni)
			if Defs.LayerAllows(tool, Defs.LayerAtCell(ny)) then
				table.insert(targets, { ni, tool.Power * tool.Splash.Fraction })
			end
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
	local payload = { Digger = player.UserId, Hits = hits, Tool = data.Equipment.ToolId } -- Tool: cosmetic profile choice only
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
		lastGateNote[player] = nil
		RateLimiter.Forget(player)
		LootService.Forget(player)
	end)
end

return DigService
