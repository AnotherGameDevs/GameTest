-- Dynamite: a throwable, single-use item (Defs.Consumables.dynamite). The client only sends an aim direction; the
-- server owns the inventory count, cooldown, the thrown stick, the fuse, which blocks break, and all rewards.
-- The blast is deliberately capped (Blast.MaxCells nearest blocks within Blast.Radius cells) and harms no players.
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ToolModels = require(ReplicatedStorage.Shared.ToolModels)

local DataService = require(script.Parent.DataService)
local SiteService = require(script.Parent.SiteService)
local LootService = require(script.Parent.LootService)
local StateService = require(script.Parent.StateService)
local MetricsService = require(script.Parent.MetricsService)
local CarryRegistry = require(script.Parent.CarryRegistry)
local RateLimiter = require(script.Parent.RateLimiter)
local AnalyticsService = require(script.Parent.AnalyticsService)

local DynamiteService = {}

local notifyRemote = Remotes.Get("Notify")
local explosionRemote = Remotes.Get("Explosion")
local digResult = Remotes.Get("DigResult")
local lastThrow: { [Player]: number } = {}
local active: { [Player]: number } = {}
local folder: Folder

local function explode(thrower: Player, stick: Model)
	if not stick.Parent or not stick.PrimaryPart then
		active[thrower] = math.max((active[thrower] or 1) - 1, 0)
		stick:Destroy()
		return
	end
	local def = Defs.Consumables.dynamite
	local pos = stick.PrimaryPart.Position
	stick:Destroy()
	active[thrower] = math.max((active[thrower] or 1) - 1, 0)

	local thrownBy = thrower.Parent and DataService.Get(thrower)
	local destroyed, hits = {}, {}
	-- The blast respects layer gating by the thrower's equipped tool tier (dynamite is not a way to skip the ladder).
	local tool = thrownBy and Defs.Tools[thrownBy.Equipment.ToolId] or Defs.Tools[Config.Starting.ToolId]
	local function allow(row: number): boolean
		return Defs.LayerAllows(tool, Defs.LayerAtCell(row))
	end
	for _, idx in ipairs(SiteService.CellsNear(pos, def.Blast.Radius, def.Blast.MaxCells, allow)) do
		local _, dead, treasureId = SiteService.Damage(idx, 1e9)
		if dead then
			table.insert(destroyed, idx)
			table.insert(hits, { idx, 0, 1 })
			if thrownBy then
				thrownBy.Stats.BlocksDug += 1
				if treasureId then
					LootService.Award(thrower, treasureId, idx) -- normal rules: backpack space, or artifact discovery
				end
			end
		end
	end
	for _, idx in ipairs(destroyed) do
		SiteService.ExposeAround(idx)
	end
	if thrownBy then
		DataService.MarkDirty(thrower)
		MetricsService.Hit(thrower, #destroyed)
		StateService.Push(thrower)
	end

	-- cosmetic feedback to everyone nearby
	for _, other in ipairs(Players:GetPlayers()) do
		local hrp = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - pos).Magnitude <= Config.Dig.MaxBroadcastDistance then
			explosionRemote:FireClient(other, pos, #destroyed)
			if #hits > 0 then
				digResult:FireClient(other, { Digger = thrower.UserId, Hits = hits })
			end
		end
	end
	AnalyticsService.Log(thrower, "DynamiteBlast", { blocks = #destroyed })
end

local function handleThrow(player: Player, dx: any, dy: any, dz: any)
	if type(dx) ~= "number" or type(dy) ~= "number" or type(dz) ~= "number" then
		return
	end
	if dx ~= dx or dy ~= dy or dz ~= dz or math.abs(dx) > 10 or math.abs(dy) > 10 or math.abs(dz) > 10 then
		return
	end
	if not RateLimiter.Check(player, "ThrowDynamite") then
		return
	end
	local dir = Vector3.new(dx, dy, dz)
	if dir.Magnitude < 0.1 then
		return
	end
	dir = dir.Unit

	local def = Defs.Consumables.dynamite
	local data = DataService.Get(player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not data or not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end
	-- throwing counts as a digging action: forbidden while carrying an important artifact
	if CarryRegistry.IsCarrying(player) then
		notifyRemote:FireClient(player, "Place your artifact down before throwing dynamite.", "Danger")
		return
	end
	local count = data.Consumables.dynamite or 0
	if count <= 0 then
		notifyRemote:FireClient(player, "You have no dynamite. Buy some at the Equipment Shop.", "Danger")
		return
	end
	local now = os.clock()
	if now - (lastThrow[player] or 0) < def.Cooldown or (active[player] or 0) >= def.MaxActive then
		return
	end
	lastThrow[player] = now

	-- consume first (atomic): one stick is gone the moment it is thrown
	data.Consumables.dynamite = count - 1
	DataService.MarkDirty(player)
	StateService.Push(player)

	local stick = ToolModels.BuildProjectile(def.Appearance)
	local origin = hrp.Position + dir * 2.5 + Vector3.new(0, 1.2, 0)
	stick:PivotTo(CFrame.new(origin) * CFrame.Angles(math.rad(80), 0, 0))
	stick.Parent = folder
	local root = stick.PrimaryPart :: BasePart
	root:SetNetworkOwner(nil)
	root.AssemblyLinearVelocity = dir * def.ThrowSpeed + Vector3.new(0, def.ThrowLift, 0)
	root.AssemblyAngularVelocity = Vector3.new(6, 2, 0)
	active[player] = (active[player] or 0) + 1
	task.delay(def.FuseSeconds, explode, player, stick)
end

function DynamiteService.Init()
	folder = Workspace:FindFirstChild("Projectiles") or Instance.new("Folder")
	folder.Name = "Projectiles"
	folder.Parent = Workspace
	Remotes.Get("ThrowDynamite").OnServerEvent:Connect(handleThrow)
	Players.PlayerRemoving:Connect(function(p)
		lastThrow[p] = nil
		active[p] = nil
	end)
end

return DynamiteService
