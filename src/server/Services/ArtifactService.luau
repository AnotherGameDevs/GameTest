-- Important artifacts: found -> physically placed in the world -> picked up -> carried -> deposited at camp.
-- Ownership/state lives in CarryRegistry.Store (pure, tested). This service does the world side effects.
--
-- Recovery policy (server session only; NOTHING here is saved to a DataStore):
--   * Death / respawn / disconnect while carrying: the artifact is dropped at the carrier's last supported spot (or,
--     failing that, where it was found, or finally on the camp "lost & found" pad) and stays claimed by its
--     discoverer. If the discoverer rejoins the SAME server they can pick it up again.
--   * If the server shuts down, an unbanked artifact is lost. There is no cross-session recovery.
--   * Dying never awards or secures an artifact; cash/collection are written only by a successful deposit.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Defs = require(ReplicatedStorage.Shared.Defs)
local Grid = require(ReplicatedStorage.Shared.Grid)
local Kit = require(ReplicatedStorage.Shared.ModelKit)
local CollectionSpec = require(ReplicatedStorage.Shared.CollectionSpec)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local TreasureModels = require(ReplicatedStorage.Shared.TreasureModels)

local CarryRegistry = require(script.Parent.CarryRegistry)
local DataService = require(script.Parent.DataService)
local StateService = require(script.Parent.StateService)
local EquipmentService = require(script.Parent.EquipmentService)
local WorldBuilder = require(script.Parent.WorldBuilder)
local MetricsService = require(script.Parent.MetricsService)
local RateLimiter = require(script.Parent.RateLimiter)
local AnalyticsService = require(script.Parent.AnalyticsService)

local ArtifactService = {}

local store = CarryRegistry.Store
local folder: Folder
local worldModels: { [string]: Model } = {}
local carryTools: { [string]: Tool } = {}
local lastSafe: { [Player]: Vector3 } = {}
local sizeCache: { [string]: Vector3 } = {}
local notifyRemote = Remotes.Get("Notify")
local depositedRemote = Remotes.Get("ArtifactDeposited")

local function say(player: Player, text: string, kind: string?)
	if player.Parent then
		notifyRemote:FireClient(player, text, kind or "Info")
	end
end

-- Physics query params that ignore characters and our own artifact models but respect everything solid.
local function queryParams(): (RaycastParams, OverlapParams)
	local ignore: { Instance } = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(ignore, p.Character)
		end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = ignore
	rp.RespectCanCollide = true
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	op.RespectCanCollide = true
	return rp, op
end

local function artifactSize(treasureId: string): Vector3
	local cached = sizeCache[treasureId]
	if cached then
		return cached
	end
	local m = TreasureModels.BuildAny(treasureId, Defs.Treasure[treasureId])
	local size = m:GetExtentsSize()
	m:Destroy()
	sizeCache[treasureId] = size
	return size
end

-- First candidate point that has an upward-facing support within reach AND a clear (non-overlapping) volume.
-- Returns the CFrame where the model's centre should rest.
local function findResting(candidates: { Vector3 }, size: Vector3, accept: ((Vector3) -> boolean)?): CFrame?
	local rp, op = queryParams()
	for _, c in ipairs(candidates) do
		local hit = Workspace:Raycast(c + Vector3.new(0, 1.5, 0), Vector3.new(0, -16, 0), rp)
		if hit and hit.Normal.Y > 0.7 then
			local center = hit.Position + Vector3.new(0, size.Y / 2 + 0.05, 0)
			if not accept or accept(center) then
				-- shrink the test volume slightly so resting ON the ground does not count as overlapping it
				local box = Vector3.new(size.X, math.max(size.Y - 0.4, 0.2), size.Z)
				local boxCF = CFrame.new(center + Vector3.new(0, 0.15, 0))
				if #Workspace:GetPartBoundsInBox(boxCF, box, op) == 0 then
					return CFrame.new(center)
				end
			end
		end
	end
	return nil
end

local function ringAround(origin: Vector3, look: Vector3, radius: number): { Vector3 }
	local right = look:Cross(Vector3.yAxis)
	return {
		origin + look * radius, origin + (look + right).Unit * radius, origin + (look - right).Unit * radius,
		origin + right * radius, origin - right * radius, origin - look * radius, origin,
	}
end

-- World model ------------------------------------------------------------------------------------------------
local function destroyWorldModel(id: string)
	local m = worldModels[id]
	if m then
		worldModels[id] = nil
		m:Destroy()
	end
end

local function spawnWorldModel(id: string)
	local rec = store:Get(id)
	if not rec or rec.State ~= "Dropped" or worldModels[id] then
		return
	end
	local def = Defs.Treasure[rec.TreasureId]
	local rar = Defs.Rarity[def.Rarity]
	local model = TreasureModels.BuildAny(rec.TreasureId, def)
	model:PivotTo(CFrame.new(rec.Position))
	model:SetAttribute("ArtifactId", id)
	model:SetAttribute("OwnerUserId", rec.OwnerId)
	model:SetAttribute("TreasureName", def.Name)

	local root = model.PrimaryPart :: BasePart
	local hl = Instance.new("Highlight")
	hl.FillColor = rar.Color
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.FillTransparency = 0.8
	hl.DepthMode = Enum.HighlightDepthMode.Occluded -- never visible through walls
	hl.Parent = model
	local light = Instance.new("PointLight")
	light.Color = rar.Color
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = root

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PickupPrompt"
	prompt.ObjectText = def.Name
	prompt.ActionText = "Pick up artifact"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = Config.Artifacts.PickupReach - 2
	prompt.RequiresLineOfSight = false
	prompt.Parent = root
	prompt.Triggered:Connect(function(player)
		ArtifactService.Pickup(player, id)
	end)

	model.Parent = folder
	worldModels[id] = model
end

-- Carry tool --------------------------------------------------------------------------------------------------
local function buildCarryTool(rec): Tool
	local def = Defs.Treasure[rec.TreasureId]
	local specs = Kit.Transform(TreasureModels.Specs(rec.TreasureId, def), Config.Artifacts.CarryScale, Config.Artifacts.CarryRotation)
	local tool = Instance.new("Tool")
	tool.Name = "CarriedArtifact"
	tool.CanBeDropped = false
	tool.ManualActivationOnly = true
	tool.RequiresHandle = true
	tool.ToolTip = def.Name
	tool.Grip = Config.Artifacts.CarryGrip
	tool:SetAttribute("ArtifactId", rec.Id)
	tool:SetAttribute("TreasureId", rec.TreasureId)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.one * 0.3
	handle.Transparency = 1
	handle.CanCollide = false -- the held model must never collide with the player or the world
	handle.CanTouch = false
	handle.Massless = true
	handle.Parent = tool
	for _, s in ipairs(specs) do
		local p = Kit.make(s)
		p.Massless = true
		p.Parent = tool
		local w = Instance.new("Weld")
		w.Part0 = handle
		w.Part1 = p
		w.C0 = s.Offset
		w.Parent = p
	end
	return tool
end

-- Removes the carry tool and brings the shovel back. The registry transition must already have happened.
local function finishCarry(player: Player, recId: string)
	local tool = carryTools[recId]
	carryTools[recId] = nil
	if tool then
		tool:Destroy()
	end
	lastSafe[player] = nil
	StateService.Push(player)
	if player.Parent then
		task.spawn(EquipmentService.Refresh, player)
	end
end

-- Discovery ----------------------------------------------------------------------------------------------------
function ArtifactService.Discover(player: Player, treasureId: string, cellIndex: number): boolean
	local def = Defs.Treasure[treasureId]
	if not def or not def.RequiresCarry or not DataService.Get(player) then
		return false
	end
	local x, y, z = Grid.FromIndex(cellIndex)
	local center = Grid.CellCenter(x, y, z)
	local size = artifactSize(treasureId)

	-- Prefer the cell it was found in (visible + accessible, never inside remaining dirt); otherwise near the player.
	local cf = findResting({ center, center + Vector3.new(1, 0, 0), center - Vector3.new(1, 0, 0),
		center + Vector3.new(0, 0, 1), center - Vector3.new(0, 0, 1) }, size)
	if not cf then
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			cf = findResting(ringAround(hrp.Position, hrp.CFrame.LookVector, 3.5), size)
		end
	end
	local position = cf and cf.Position or (center + Vector3.new(0, size.Y / 2 - Grid.CellSize / 2 + 0.05, 0))

	local rec = store:Create(treasureId, def.Value, player.UserId, position)
	task.delay(Config.Artifacts.SpawnDelay, spawnWorldModel, rec.Id)
	say(player, "Important artifact found - carry it to camp.", "Good")
	AnalyticsService.Log(player, "ArtifactDiscovered", { id = rec.Id, treasure = treasureId })
	return true
end

-- Pickup ---------------------------------------------------------------------------------------------------------
function ArtifactService.Pickup(player: Player, recId: any)
	if type(recId) ~= "string" then
		return
	end
	local rec = store:Get(recId)
	local model = worldModels[recId]
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rec or not model or not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (hrp.Position - rec.Position).Magnitude > Config.Artifacts.PickupReach then
		return
	end
	-- Atomic check-and-set: duplicate/simultaneous pickups fail here.
	local ok, reason = store:Pickup(recId, player.UserId)
	if not ok then
		if reason == "NotOwner" then
			say(player, "This artifact was claimed by its discoverer.", "Danger")
		elseif reason == "AlreadyCarrying" then
			say(player, "You can only carry one important artifact at a time.", "Danger")
		end
		return
	end

	destroyWorldModel(recId)
	local tool = buildCarryTool(rec)
	carryTools[recId] = tool
	tool.Parent = player:FindFirstChildOfClass("Backpack")
	humanoid:UnequipTools() -- stows the shovel
	humanoid:EquipTool(tool)
	lastSafe[player] = hrp.Position

	-- If anything pulls the artifact out of the player's hands, put it back.
	tool.Unequipped:Connect(function()
		task.defer(function()
			local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and carryTools[recId] == tool and tool.Parent == player:FindFirstChildOfClass("Backpack") then
				h:EquipTool(tool)
			end
		end)
	end)

	StateService.Push(player)
	say(player, ("Carrying %s - take it to the receiving table at camp."):format(Defs.Treasure[rec.TreasureId].Name), "Good")
	AnalyticsService.Log(player, "ArtifactPickedUp", { id = recId })
end

-- Place down -----------------------------------------------------------------------------------------------------
local function placeDown(player: Player)
	if not RateLimiter.Check(player, "PlaceArtifact") then
		return
	end
	local rec = CarryRegistry.Get(player)
	if not rec then
		say(player, "You are not carrying an artifact.", "Info")
		return
	end
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not hrp or not humanoid or humanoid.Health <= 0 then
		return
	end
	local size = artifactSize(rec.TreasureId)
	local look = Vector3.new(hrp.CFrame.LookVector.X, 0, hrp.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
	local base = hrp.Position
	local cf = findResting(ringAround(base, look, 3.5), size, function(center: Vector3)
		local flat = Vector3.new(center.X - base.X, 0, center.Z - base.Z).Magnitude
		return flat <= Config.Artifacts.PlaceReach and math.abs(center.Y - base.Y) <= 6
	end)
	if not cf then
		say(player, "No safe spot to put it down here. Find open, flat ground.", "Danger")
		return
	end
	-- Re-check the carry state right before committing (the search above has no yields, but be explicit).
	local ok = store:Place(rec.Id, player.UserId, cf.Position)
	if not ok then
		return
	end
	finishCarry(player, rec.Id)
	spawnWorldModel(rec.Id)
	say(player, "Artifact placed. Pick it up again when you are ready.", "Info")
	AnalyticsService.Log(player, "ArtifactPlaced", { id = rec.Id })
end

-- Deposit ---------------------------------------------------------------------------------------------------------
function ArtifactService.Deposit(player: Player)
	local rec = CarryRegistry.Get(player)
	local data = DataService.Get(player)
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rec or not data or not hrp or not humanoid or humanoid.Health <= 0 then
		if player.Parent and not rec then
			say(player, "You are not carrying an important artifact.", "Info")
		end
		return
	end
	if (hrp.Position - WorldBuilder.ReceivingCenter).Magnitude > Config.Artifacts.DepositReach then
		return
	end
	-- Atomic: pays out exactly once.
	local ok, value = store:Deposit(rec.Id, player.UserId)
	if not ok then
		return
	end
	local def = Defs.Treasure[rec.TreasureId]
	data.Cash += value
	data.Stats.CashEarned += value
	data.Stats.TreasureFound += 1
	data.Stats.RelicsExtracted += 1
	local isNew, completed = CollectionSpec.Register(data.Collection, rec.TreasureId, os.time())
	if completed then
		Remotes.Get("SetCompleted"):FireClient(player, completed, Defs.LayerName(completed))
	end
	DataService.MarkDirty(player)
	MetricsService.Sold(player, value, 1)

	finishCarry(player, rec.Id)
	depositedRemote:FireClient(player, def.Name, value, isNew)
	ArtifactService.ShowOnTable(rec.TreasureId)
	AnalyticsService.Log(player, "ArtifactDeposited", { id = rec.Id, value = value })
end

-- Briefly displays a deposited artifact on the receiving table (visual only; not tracked as an artifact).
function ArtifactService.ShowOnTable(treasureId: string)
	local def = Defs.Treasure[treasureId]
	local model = TreasureModels.BuildAny(treasureId, def)
	model:PivotTo(CFrame.new(WorldBuilder.ReceivingDisplayPosition))
	model.Name = "DepositedDisplay"
	local hl = Instance.new("Highlight")
	hl.FillColor = Defs.Rarity[def.Rarity].Color
	hl.FillTransparency = 0.6
	hl.Parent = model
	model.Parent = folder
	task.delay(Config.Artifacts.DisplaySeconds, function()
		model:Destroy()
	end)
end

-- Mine refresh support --------------------------------------------------------------------------------------------
-- Inside the mine volume (grid footprint plus the exit shaft beside it), below the rim.
local function inMine(pos: Vector3): boolean
	local b = Grid.Bounds()
	local ex = Config.Exit
	local maxZ = b.MaxZ + (ex.Enabled and ex.Run or 0)
	return pos.X >= b.MinX - 1 and pos.X <= b.MaxX + 1 and pos.Z >= b.MinZ - 1 and pos.Z < maxZ and pos.Y < b.TopY + 3
end
ArtifactService.InMine = inMine

-- Players currently carrying an artifact while standing inside the mine.
function ArtifactService.CarriersInMine(): { Player }
	local out = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if CarryRegistry.IsCarrying(player) then
			local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if hrp and inMine(hrp.Position) then
				table.insert(out, player)
			end
		end
	end
	return out
end

-- Moves every resting artifact that lies inside the mine onto the camp Lost & Found pad (they are never deleted; the
-- owner can still pick them up there). Returns how many were moved.
function ArtifactService.RelocateFromMine(): number
	local moved = 0
	for _, rec in ipairs(store:Dropped()) do
		if inMine(rec.Position) then
			local spot = WorldBuilder.LostFoundPosition + Vector3.new((moved % 3 - 1) * 2.2, 0, (moved // 3) * 2.2)
			if store:Relocate(rec.Id, spot) then
				destroyWorldModel(rec.Id)
				spawnWorldModel(rec.Id)
				moved += 1
				local owner = Players:GetPlayerByUserId(rec.OwnerId)
				if owner then
					say(owner, ("The mine was refreshed. Your %s is waiting at Lost & Found."):format(Defs.Treasure[rec.TreasureId].Name), "Good")
				end
			end
		end
	end
	return moved
end

-- Loss handling (death / respawn / disconnect) --------------------------------------------------------------------
local function onLoss(player: Player, reason: string)
	local rec = CarryRegistry.Get(player)
	if not rec then
		return
	end
	local size = artifactSize(rec.TreasureId)
	local cf
	local safe = lastSafe[player]
	if safe then
		cf = findResting(ringAround(safe, Vector3.new(0, 0, -1), 2.5), size)
	end
	if not cf then
		cf = findResting(ringAround(rec.Origin, Vector3.new(0, 0, -1), 2), size)
	end
	-- Last resort: the camp lost & found pad is always valid.
	local position = cf and cf.Position or WorldBuilder.LostFoundPosition
	if not store:Drop(rec.Id, position) then
		return
	end
	finishCarry(player, rec.Id)
	spawnWorldModel(rec.Id)
	if player.Parent then
		say(player, "You dropped your artifact. It is waiting where you lost it.", "Danger")
	end
	AnalyticsService.Log(player, "ArtifactDropped", { id = rec.Id, reason = reason })
end

-- Forces a carried artifact to be dropped (used by the mine refresh when a carrier will not leave the mine).
function ArtifactService.ForceDrop(player: Player)
	onLoss(player, "mine_refresh")
end

function ArtifactService.Init()
	folder = Workspace:FindFirstChild("Artifacts") or Instance.new("Folder")
	folder.Name = "Artifacts"
	folder.Parent = Workspace

	Remotes.Get("PlaceArtifact").OnServerEvent:Connect(placeDown)

	-- Deposit prompt at the receiving table
	local world = Workspace:FindFirstChild("World")
	local prompt = world and world:FindFirstChild("DepositPrompt", true)
	if prompt then
		prompt.Triggered:Connect(ArtifactService.Deposit)
	else
		warn("[ArtifactService] Deposit prompt not found - the receiving table was not built.")
	end

	local function watch(player: Player)
		player.CharacterRemoving:Connect(function()
			onLoss(player, "respawn")
		end)
		local function onChar(char: Model)
			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				(hum :: Humanoid).Died:Connect(function()
					onLoss(player, "died")
				end)
			end
		end
		player.CharacterAdded:Connect(onChar)
		if player.Character then
			task.spawn(onChar, player.Character)
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		onLoss(player, "disconnect")
		lastSafe[player] = nil
		RateLimiter.Forget(player)
	end)

	-- Remember where the carrier last stood on solid ground, for death/disconnect drops.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		for _, player in ipairs(Players:GetPlayers()) do
			if CarryRegistry.IsCarrying(player) then
				local char = player.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if hum and hrp and hum.Health > 0 and hum.FloorMaterial ~= Enum.Material.Air then
					lastSafe[player] = hrp.Position
				end
			end
		end
	end)
end

return ArtifactService
